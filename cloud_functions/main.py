"""
Hybrid Music Ingestion Cloud Function
======================================
Architecture:
    - Tier 1: SpotiFLAC (Official Spotify metadata + Tidal/Qobuz Studio Lossless Audio).
    - Tier 2: YouTube Fallback (yt-dlp with anti-blocking Android client extractor)
              Handles regional, Malayalam, Tamil, indie, and unstreamed tracks seamlessly.

Endpoints:
    - POST /ingest   -> Ingest via SpotiFLAC with automatic YouTube fallback
    - GET  /search   -> Search catalog / YouTube (used by Flutter Search)
    - GET  /preview  -> Audio preview streaming URL for Flutter Search
    - POST /delete   -> Complete track deletion (Cloudinary + Firestore)
    - GET  /ping     -> Health check & engine status
"""

from __future__ import annotations

import os
import re
import json
import time
import tempfile
import logging
import shutil
import subprocess
import urllib.parse
import base64
import io
import zipfile
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

import requests
import yt_dlp
import cloudinary
import cloudinary.uploader
import firebase_admin
from firebase_admin import credentials, firestore
from flask import Flask, request, jsonify
from pydub import AudioSegment

try:
    import mutagen
except ImportError:
    mutagen = None

# SpotiFLAC imports
try:
    from SpotiFLAC import SpotiFLAC  # type: ignore
    from SpotiFLAC.core.spotify_metadata import SpotifyMetadataClient  # type: ignore
    SPOTIFLAC_AVAILABLE = True
except ImportError:
    try:
        import spotiflac  # type: ignore
        from spotiflac.core.spotify_metadata import SpotifyMetadataClient  # type: ignore
        SPOTIFLAC_AVAILABLE = True
    except ImportError:
        SPOTIFLAC_AVAILABLE = False

# ─────────────────────────────────────────────────────────────────────────────
#  Bootstrap & Configuration
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")
log = logging.getLogger("hybrid_backend")

app = Flask(__name__)

# Ensure SpotiFLAC extension registry is configured
if "SPOTIFLAC_REGISTRIES" not in os.environ:
    os.environ["SPOTIFLAC_REGISTRIES"] = "https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json"

# Firebase Admin
_cred_path = os.environ.get(
    "FIREBASE_CREDENTIALS_JSON",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "../database/firebase-key.json")
)
db = None
try:
    if not firebase_admin._apps:
        if _cred_path.strip().startswith("{"):
            try:
                cred_dict = json.loads(_cred_path)
                cred = credentials.Certificate(cred_dict)
            except Exception as e:
                log.error("Failed to parse FIREBASE_CREDENTIALS_JSON as dictionary: %s", e)
                cred = credentials.Certificate(_cred_path)
        else:
            cred = credentials.Certificate(_cred_path)
        firebase_admin.initialize_app(cred)
    db = firestore.client()
    log.info("Firebase Admin initialized successfully ✓")
except Exception as e:
    log.warning("Firebase Admin initialization skipped or credentials missing: %s", e)

# Cloudinary
cloudinary.config(
    cloud_name=os.environ.get("CLOUDINARY_CLOUD_NAME", "YOUR_CLOUDINARY_CLOUD_NAME"),
    api_key=os.environ.get("CLOUDINARY_API_KEY", "YOUR_CLOUDINARY_API_KEY"),
    api_secret=os.environ.get("CLOUDINARY_API_SECRET", "YOUR_CLOUDINARY_API_SECRET"),
    secure=True,
)

TRACKS_COL      = "tracks"
PLAYLISTS_COL   = "playlists"
YT_MUSIC_SEARCH = "https://music.youtube.com/search?q="

# ─────────────────────────────────────────────────────────────────────────────
#  Anti-Blocking YouTube yt-dlp Configuration
# ─────────────────────────────────────────────────────────────────────────────
_COOKIES_TMP_FILE = None

def _sanitize_and_save_cookies(raw_text: str) -> str | None:
    """Sanitize cookies by stripping expired/mismatched LOGIN_INFO and ensuring Netscape header."""
    global _COOKIES_TMP_FILE
    try:
        lines = raw_text.splitlines()
        # Filter out LOGIN_INFO which triggers YouTube's 'The page needs to be reloaded' on cloud IPs
        clean_lines = [l for l in lines if "LOGIN_INFO" not in l]
        sanitized = "\n".join(clean_lines).strip()
        if not sanitized.startswith("# Netscape HTTP Cookie File"):
            sanitized = "# Netscape HTTP Cookie File\n" + sanitized

        tf = tempfile.NamedTemporaryFile(delete=False, suffix="_yt_cookies.txt", mode="w", encoding="utf-8")
        tf.write(sanitized + "\n")
        tf.flush()
        tf.close()
        _COOKIES_TMP_FILE = tf.name
        log.info("Saved sanitized cookies to: %s (%d bytes)", _COOKIES_TMP_FILE, len(sanitized))
        return _COOKIES_TMP_FILE
    except Exception as e:
        log.warning("Failed to sanitize cookies: %s", e)
        return None


def _get_cookie_file_path() -> str | None:
    """Check for local cookies.txt or decode YOUTUBE_COOKIES / YOUTUBE_COOKIES_BASE64 from environment."""
    global _COOKIES_TMP_FILE
    if _COOKIES_TMP_FILE and os.path.exists(_COOKIES_TMP_FILE):
        return _COOKIES_TMP_FILE

    # 1. Check local cookies files in current directory or cloud_functions/
    base_dirs = [
        os.path.dirname(__file__),
        os.path.join(os.path.dirname(__file__), ".."),
        os.getcwd(),
    ]
    for bd in base_dirs:
        if os.path.isdir(bd):
            for fname in ["cookies.txt", "www.youtube.com_cookies.txt", "youtube_cookies.txt"]:
                full_p = os.path.join(bd, fname)
                if os.path.exists(full_p) and os.path.getsize(full_p) > 10:
                    try:
                        with open(full_p, "r", encoding="utf-8", errors="ignore") as f:
                            content = f.read()
                        sanitized_path = _sanitize_and_save_cookies(content)
                        if sanitized_path:
                            return sanitized_path
                    except Exception as e:
                        log.warning("Error reading local cookie file %s: %s", full_p, e)
                        return full_p

            for p in Path(bd).glob("*cookie*.txt"):
                if p.is_file() and p.stat().st_size > 10:
                    try:
                        with open(str(p), "r", encoding="utf-8", errors="ignore") as f:
                            content = f.read()
                        sanitized_path = _sanitize_and_save_cookies(content)
                        if sanitized_path:
                            return sanitized_path
                    except Exception as e:
                        log.warning("Error reading local cookie file %s: %s", str(p), e)
                        return str(p)

    # 2. Check base64 encoded cookies environment variable
    cookies_b64 = os.environ.get("YOUTUBE_COOKIES_BASE64", "").strip()
    if cookies_b64:
        try:
            decoded = base64.b64decode(cookies_b64).decode("utf-8", errors="ignore")
            sanitized_path = _sanitize_and_save_cookies(decoded)
            if sanitized_path:
                return sanitized_path
        except Exception as e:
            log.warning("Failed to decode YOUTUBE_COOKIES_BASE64: %s", e)

    # 3. Check plain text cookies environment variable
    cookies_raw = os.environ.get("YOUTUBE_COOKIES", "").strip()
    if cookies_raw and len(cookies_raw) > 20:
        sanitized_path = _sanitize_and_save_cookies(cookies_raw)
        if sanitized_path:
            return sanitized_path

    return None


_JS_RUNTIME_PATH = None

def _ensure_js_runtime() -> str | None:
    """Ensure a modern JavaScript runtime (node or deno) is available for yt-dlp EJS challenges."""
    global _JS_RUNTIME_PATH
    if _JS_RUNTIME_PATH and (os.path.exists(_JS_RUNTIME_PATH) or shutil.which(_JS_RUNTIME_PATH)):
        return _JS_RUNTIME_PATH

    # 1. Check existing system binaries
    for name in ["node", "nodejs", "deno", "qjs"]:
        p = shutil.which(name)
        if p:
            _JS_RUNTIME_PATH = p
            return p

    # 2. Check common Linux locations
    for p in ["/usr/bin/node", "/usr/local/bin/node", "/usr/bin/nodejs", "/tmp/bin/deno"]:
        if os.path.exists(p) and os.access(p, os.X_OK):
            if "/tmp/bin" not in os.environ.get("PATH", ""):
                os.environ["PATH"] = f"/tmp/bin:{os.environ.get('PATH', '')}"
            _JS_RUNTIME_PATH = p
            return p

    # 3. Auto-download standalone Deno binary for Linux if running in Linux (e.g. Render)
    if os.name != "nt":
        target_dir = "/tmp/bin"
        target_bin = os.path.join(target_dir, "deno")
        if os.path.exists(target_bin) and os.access(target_bin, os.X_OK):
            if target_dir not in os.environ.get("PATH", ""):
                os.environ["PATH"] = f"{target_dir}:{os.environ.get('PATH', '')}"
            _JS_RUNTIME_PATH = target_bin
            return target_bin

        try:
            log.info("Downloading standalone Deno JS runtime for yt-dlp challenge solving...")
            os.makedirs(target_dir, exist_ok=True)
            deno_url = "https://github.com/denoland/deno/releases/download/v2.1.4/deno-x86_64-unknown-linux-gnu.zip"
            resp = requests.get(deno_url, timeout=45)
            if resp.status_code == 200:
                with zipfile.ZipFile(io.BytesIO(resp.content)) as z:
                    z.extract("deno", target_dir)
                os.chmod(target_bin, 0o755)
                os.environ["PATH"] = f"{target_dir}:{os.environ.get('PATH', '')}"
                log.info("Deno JS runtime installed successfully at: %s", target_bin)
                _JS_RUNTIME_PATH = target_bin
                return target_bin
        except Exception as e:
            log.warning("Failed to auto-install Deno JS runtime: %s", e)

    return None


def _get_ydl_opts(base_opts: dict) -> dict:
    """
    Return hardened yt-dlp options configured to prevent datacenter IP blocks.
    Uses authenticated cookies with JS challenge solving, or VisionOS/Android fallback.
    """
    opts = base_opts.copy()

    # Enable automated EJS challenge solver
    opts.setdefault("remote_components", ["ejs:github"])

    # Configure JS runtime if available (node, deno, etc.)
    js_bin = _ensure_js_runtime()
    if js_bin:
        runtime_name = "deno" if "deno" in os.path.basename(js_bin).lower() else "node"
        opts["js_runtimes"] = {runtime_name: {"path": js_bin}}
        log.info("yt-dlp using %s JS runtime at: %s", runtime_name, js_bin)
    else:
        log.warning("No JS runtime (node/deno) available for yt-dlp!")

    # Check for authentication cookies
    cookie_file = _get_cookie_file_path()
    if cookie_file:
        opts["cookiefile"] = cookie_file
        log.info("yt-dlp operating in Authenticated Cookie mode (%s)", cookie_file)
    else:
        # Fallback without cookies: Emulate VisionOS & Android player clients
        opts.setdefault("extractor_args", {
            "youtube": {
                "player_client": ["visionos", "android_vr", "android"],
            }
        })

    # Network timeouts and retries
    opts.setdefault("socket_timeout", 30)
    opts.setdefault("retries", 3)

    # Proxy support if configured
    proxy = os.environ.get("YT_PROXY") or os.environ.get("HTTPS_PROXY") or os.environ.get("HTTP_PROXY")
    if proxy:
        opts["proxy"] = proxy

    return opts


# ─────────────────────────────────────────────────────────────────────────────
#  Audio Transcoder (Lossless FLAC/Opus/WAV -> 256 kbps AAC M4A)
# ─────────────────────────────────────────────────────────────────────────────
def _transcode_audio_to_m4a(input_path: str, output_path: str, bitrate: str = "256k") -> bool:
    """
    Transcode audio to optimized 256 kbps AAC M4A.
    Includes +faststart for instant mobile streaming.
    """
    if shutil.which("ffmpeg"):
        try:
            cmd = [
                "ffmpeg", "-y", "-i", input_path,
                "-c:a", "aac",
                "-b:a", bitrate,
                "-ar", "44100",
                "-movflags", "+faststart",
                output_path
            ]
            subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            if os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
                log.info("Audio transcoded via ffmpeg -> %s (%d KB)", output_path, os.path.getsize(output_path) // 1024)
                return True
        except Exception as e:
            log.warning("ffmpeg CLI transcoding failed, falling back to pydub: %s", e)

    try:
        audio = AudioSegment.from_file(input_path)
        audio.export(output_path, format="ipod", codec="aac", bitrate=bitrate, parameters=["-movflags", "+faststart"])
        if os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
            log.info("Audio transcoded via pydub -> %s (%d KB)", output_path, os.path.getsize(output_path) // 1024)
            return True
    except Exception as e:
        log.warning("pydub audio export failed: %s", e)

    return False


def _get_audio_duration_ms(file_path: str) -> int:
    """Get accurate audio duration in milliseconds."""
    try:
        if mutagen:
            f = mutagen.File(file_path)
            if f and f.info and hasattr(f.info, "length"):
                return int(f.info.length * 1000)
    except Exception:
        pass
    try:
        seg = AudioSegment.from_file(file_path)
        return len(seg)
    except Exception:
        pass
    return 0


def _clean_track_title(raw_title: str) -> str:
    """Clean title formatting for search matching."""
    t = raw_title
    if "|" in t:
        parts = [p.strip() for p in t.split("|") if p.strip()]
        if parts:
            t = parts[0]
    t = re.sub(r"\(.*?\)", "", t)
    t = re.sub(r"\[.*?\]", "", t)
    buzzwords = [
        "official video", "video song", "lyric video", "lyrics", "audio song",
        "official audio", "full video song", "full song", "hd", "4k", "remastered"
    ]
    for b in buzzwords:
        t = re.sub(re.escape(b), "", t, flags=re.IGNORECASE)
    t = re.sub(r"\s+", " ", t).strip(" -_")
    return t or raw_title


# ─────────────────────────────────────────────────────────────────────────────
#  Spotify Metadata Resolution
# ─────────────────────────────────────────────────────────────────────────────
def _resolve_spotify_track(title: str, artist: str = "", spotify_url: str = None) -> tuple[dict | None, str | None]:
    """
    Search Spotify's catalog using SpotifyMetadataClient.
    Returns (track_metadata_dict, spotify_url) or (None, None).
    """
    if not SPOTIFLAC_AVAILABLE:
        return None, None

    try:
        sm = SpotifyMetadataClient()
    except Exception as e:
        log.warning("Could not initialize SpotifyMetadataClient: %s", e)
        return None, None

    # If direct Spotify URL provided
    if spotify_url and "spotify.com/track/" in spotify_url:
        track_id = spotify_url.split("/track/")[1].split("?")[0]
        try:
            track_obj = sm.get_track(track_id)
            if track_obj:
                meta = {
                    "spotify_id": getattr(track_obj, "id", track_id),
                    "title": getattr(track_obj, "title", title),
                    "artist": getattr(track_obj, "artists", artist),
                    "album": getattr(track_obj, "album", ""),
                    "cover_url": getattr(track_obj, "cover_url", None),
                    "duration_ms": getattr(track_obj, "duration_ms", 0),
                    "spotify_url": getattr(track_obj, "external_url", spotify_url),
                    "source": "spotiflac"
                }
                return meta, spotify_url
        except Exception as e:
            log.warning("Direct Spotify track fetch failed: %s", e)

    clean_t = _clean_track_title(title)
    clean_a = _clean_track_title(artist)
    queries = [
        f"{clean_t} {clean_a}".strip(),
        clean_t,
        f"{clean_a} {clean_t}".strip()
    ]

    for q in queries:
        if not q:
            continue
        try:
            log.info("Searching Spotify catalog for query: '%s'...", q)
            res = sm.search(q)
            tracks = res.get("tracks", []) if isinstance(res, dict) else []
            if tracks:
                t = tracks[0]
                resolved_url = getattr(t, "external_url", None) or f"https://open.spotify.com/track/{getattr(t, 'id', '')}"
                meta = {
                    "spotify_id": getattr(t, "id", ""),
                    "title": getattr(t, "title", clean_t),
                    "artist": getattr(t, "artists", clean_a),
                    "album": getattr(t, "album", ""),
                    "cover_url": getattr(t, "cover_url", None),
                    "duration_ms": getattr(t, "duration_ms", 0),
                    "spotify_url": resolved_url,
                    "source": "spotiflac"
                }
                log.info("Spotify resolved track: '%s' by '%s' -> %s", meta["title"], meta["artist"], resolved_url)
                return meta, resolved_url
        except Exception as e:
            log.warning("Spotify catalog search query '%s' failed: %s", q, e)

    return None, None


# ─────────────────────────────────────────────────────────────────────────────
#  SpotiFLAC Lossless Audio Downloader (Tier 1)
# ─────────────────────────────────────────────────────────────────────────────
def _download_via_spotiflac(spotify_url: str, output_dir: str) -> tuple[str | None, int]:
    """
    Download studio lossless audio from Tidal/Qobuz using SpotiFLAC and transcode to M4A.
    Returns (transcoded_m4a_path, duration_ms) or (None, 0).
    """
    if not SPOTIFLAC_AVAILABLE:
        return None, 0

    try:
        log.info("Running SpotiFLAC lossless engine on %s...", spotify_url)
        SpotiFLAC(spotify_url, output_dir=output_dir)

        downloaded = []
        for ext in ("*.flac", "*.wav", "*.m4a", "*.mp3", "*.ogg", "*.opus"):
            downloaded.extend(Path(output_dir).glob(ext))

        if not downloaded:
            log.info("SpotiFLAC found no lossless stream in Tidal/Qobuz catalog.")
            return None, 0

        source_file = str(downloaded[0])
        log.info("SpotiFLAC downloaded source: %s (%d KB)", source_file, os.path.getsize(source_file) // 1024)

        transcoded_m4a = os.path.join(output_dir, "transcoded_audio.m4a")
        if _transcode_audio_to_m4a(source_file, transcoded_m4a, bitrate="256k"):
            duration_ms = _get_audio_duration_ms(transcoded_m4a)
            return transcoded_m4a, duration_ms
        elif source_file.endswith(".m4a"):
            return source_file, _get_audio_duration_ms(source_file)

    except Exception as e:
        log.warning("SpotiFLAC download encountered exception: %s", e)

    return None, 0


# ─────────────────────────────────────────────────────────────────────────────
#  YouTube Downloader & Search (Tier 2 Fallback)
# ─────────────────────────────────────────────────────────────────────────────
def _search_youtube(title: str, artist: str) -> tuple[str | None, str | None, str | None]:
    """
    Search YouTube for best audio match.
    Returns (watch_url, thumbnail_url, video_id).
    """
    queries = [
        f"{artist} {title} official audio".strip(),
        f"{title} {artist} audio".strip(),
        f"{title} {artist}".strip(),
    ]

    ydl_opts = _get_ydl_opts({
        "quiet": True,
        "no_warnings": True,
        "extract_flat": True,
        "skip_download": True,
    })

    for q in queries:
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(f"ytsearch1:{q}", download=False)
                entries = info.get("entries") or []
                if entries and entries[0]:
                    e = entries[0]
                    vid_id = e.get("id")
                    if vid_id:
                        watch_url = f"https://www.youtube.com/watch?v={vid_id}"
                        thumb_url = e.get("thumbnail") or f"https://i.ytimg.com/vi/{vid_id}/maxresdefault.jpg"
                        log.info("YouTube search found match for query '%s': %s", q, vid_id)
                        return watch_url, thumb_url, vid_id
        except Exception as e:
            log.warning("YouTube search query '%s' failed: %s", q, e)

    return None, None, None


def _fetch_ytmusic_thumbnail(title: str, artist: str) -> str | None:
    """Scrape YouTube Music search page for high-res official audio artwork."""
    query = f"{artist} {title} official audio".strip()
    url = YT_MUSIC_SEARCH + urllib.parse.quote(query)
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
    }
    try:
        resp = requests.get(url, headers=headers, timeout=10)
        if resp.status_code == 200:
            ids = re.findall(r'"videoId":"([A-Za-z0-9_-]{11})"', resp.text)
            if ids:
                return f"https://i.ytimg.com/vi/{ids[0]}/maxresdefault.jpg"
    except Exception:
        pass
    return None


def _download_via_youtube(yt_url: str, output_dir: str) -> tuple[str | None, int, str | None]:
    """
    Download audio via yt-dlp with anti-blocking configuration and transcode to 256k AAC M4A.
    Returns (transcoded_m4a_path, duration_ms, error_message).
    """
    out_tpl = os.path.join(output_dir, "%(id)s.%(ext)s")
    ydl_opts = _get_ydl_opts({
        "format": "bestaudio/best",
        "outtmpl": out_tpl,
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "windowsfilenames": True,
        "restrictfilenames": True,
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "m4a",
            "preferredquality": "256",
        }],
    })

    try:
        log.info("Downloading audio via yt-dlp from: %s", yt_url)
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(yt_url, download=True)
            duration_sec = info.get("duration") or 0
            duration_ms = int(float(duration_sec) * 1000) if duration_sec else 0

        # Locate downloaded file (look for .m4a first)
        m4a_files = list(Path(output_dir).glob("*.m4a"))
        all_files = [f for f in Path(output_dir).iterdir() if f.is_file()]
        downloaded = m4a_files or all_files

        if not downloaded:
            log.error("yt-dlp downloaded no files into directory.")
            return None, 0, "No audio file produced by yt-dlp"

        source_file = str(downloaded[0])
        log.info("yt-dlp produced file: %s (%d KB)", source_file, os.path.getsize(source_file) // 1024)

        transcoded_m4a = os.path.join(output_dir, "transcoded_yt_audio.m4a")
        if _transcode_audio_to_m4a(source_file, transcoded_m4a, bitrate="256k"):
            dur = _get_audio_duration_ms(transcoded_m4a) or duration_ms
            return transcoded_m4a, dur, None
        elif source_file.endswith(".m4a"):
            dur = _get_audio_duration_ms(source_file) or duration_ms
            return source_file, dur, None

        return None, 0, "Audio transcoding to M4A failed"

    except Exception as e:
        log.exception("YouTube download failed: %s", e)
        return None, 0, str(e)


# ─────────────────────────────────────────────────────────────────────────────
#  Cloudinary Upload Helpers
# ─────────────────────────────────────────────────────────────────────────────
def _sanitize_public_id(raw: str) -> str:
    """Turn 'artist/title' into a safe Cloudinary public_id."""
    return re.sub(r"[^a-zA-Z0-9/_-]", "_", raw)[:200]


def _upload_square_cover(image_url: str | None, title: str, artist: str) -> tuple[str, str]:
    """Upload cover artwork to Cloudinary with square crop (640x640)."""
    if not image_url:
        return "", ""

    public_id = _sanitize_public_id(f"covers/{artist}/{title}")
    log.info("Uploading album cover to Cloudinary: %s", public_id)

    try:
        result = cloudinary.uploader.upload(
            image_url,
            public_id=public_id,
            overwrite=True,
            transformation=[{
                "width": 640,
                "height": 640,
                "crop": "fill",
                "gravity": "center",
            }],
            format="jpg",
        )
        return result["secure_url"], public_id
    except Exception as e:
        log.warning("Album cover upload to Cloudinary failed: %s", e)
        return image_url, ""


# ─────────────────────────────────────────────────────────────────────────────
#  Deduplication
# ─────────────────────────────────────────────────────────────────────────────
def _normalize(s: str) -> str:
    """Lowercase + collapse whitespace + strip punctuation for fuzzy matching."""
    s = s.lower().strip()
    s = re.sub(r"[^\w\s]", "", s)
    s = re.sub(r"\s+", " ", s)
    return s


def _find_existing_track(title: str, artist: str, spotify_id: str = "", video_id: str = "") -> str | None:
    """Check Firestore tracks collection for duplicates."""
    if not db:
        return None

    if spotify_id:
        snap = (db.collection(TRACKS_COL)
                  .where("spotify_id", "==", spotify_id)
                  .limit(1)
                  .get())
        if snap:
            log.info("Dedup hit (spotify_id): %s", snap[0].id)
            return snap[0].id

    if video_id:
        snap = (db.collection(TRACKS_COL)
                  .where("video_id", "==", video_id)
                  .limit(1)
                  .get())
        if snap:
            log.info("Dedup hit (video_id): %s", snap[0].id)
            return snap[0].id

    title_lc = _normalize(title)
    artist_lc = _normalize(artist)
    alias_key = f"{title_lc}||{artist_lc}"

    snap = (db.collection(TRACKS_COL)
              .where("title_lc", "==", title_lc)
              .where("artist_lc", "==", artist_lc)
              .limit(1)
              .get())
    if snap:
        log.info("Dedup hit (shadow fields): %s", snap[0].id)
        return snap[0].id

    snap2 = (db.collection(TRACKS_COL)
               .where("alias_keys", "array_contains", alias_key)
               .limit(1)
               .get())
    if snap2:
        log.info("Dedup hit (alias_keys): %s", snap2[0].id)
        return snap2[0].id

    return None


# ─────────────────────────────────────────────────────────────────────────────
#  Firestore Document Creation & Playlist Linking
# ─────────────────────────────────────────────────────────────────────────────
def _create_firestore_track(
    meta: dict,
    secure_url: str,
    audio_public_id: str,
    cover_url: str,
    cover_public_id: str,
    source: str = "spotiflac",
    quality: str = "256k_aac_studio_master",
    video_id: str = "",
) -> str:
    """Create a track document in Firestore."""
    if not db:
        log.warning("Firestore not initialized. Returning dummy doc id.")
        return f"track_{int(time.time())}"

    title = meta.get("title", "Unknown Title")
    artist = meta.get("artist", "Unknown Artist")
    doc_ref = db.collection(TRACKS_COL).document()

    alias_keys = [f"{_normalize(title)}||{_normalize(artist)}"]

    doc_data = {
        # Core player fields
        "title": title,
        "artist": artist,
        "album": meta.get("album", ""),
        "secure_url": secure_url,
        "audio_public_id": audio_public_id,
        "imageUrl": cover_url,
        "cover_public_id": cover_public_id,
        "duration_ms": meta.get("duration_ms", 0),
        "trackNumber": meta.get("track_number", 1),
        "isExplicit": meta.get("is_explicit", False),

        # Source & quality flags
        "meta_source": source,
        "audio_quality": quality,
        "spotify_id": meta.get("spotify_id", ""),
        "spotify_url": meta.get("spotify_url", ""),
        "video_id": video_id or meta.get("video_id", ""),

        # Deduplication fields
        "title_lc": _normalize(title),
        "artist_lc": _normalize(artist),
        "alias_keys": alias_keys,

        # Timestamps
        "addedAt": firestore.SERVER_TIMESTAMP,
    }

    doc_ref.set(doc_data)
    log.info("Firestore track created: %s (source=%s, quality=%s)", doc_ref.id, source, quality)
    return doc_ref.id


def _link_to_playlist(playlist_id: str, track_id: str) -> None:
    """Link track to a user playlist in Firestore."""
    if not db or not playlist_id:
        return
    try:
        db.collection(PLAYLISTS_COL).document(playlist_id).update({
            "trackIds": firestore.ArrayUnion([track_id])
        })
        log.info("Linked track %s -> playlist %s", track_id, playlist_id)
    except Exception as e:
        log.warning("Failed to link track to playlist: %s", e)


# ─────────────────────────────────────────────────────────────────────────────
#  API Endpoints
# ─────────────────────────────────────────────────────────────────────────────
@app.route("/ping", methods=["GET"])
def ping():
    cookie_present = bool(_get_cookie_file_path())
    js_bin = _ensure_js_runtime()
    return jsonify({
        "status": "online",
        "version": "1.3.1",
        "engine": "Hybrid (SpotiFLAC Studio Lossless + YouTube Regional Fallback)",
        "spotiflac_available": SPOTIFLAC_AVAILABLE,
        "youtube_available": True,
        "youtube_cookies_loaded": cookie_present,
        "js_runtime_available": bool(js_bin),
        "js_runtime_path": js_bin,
    }), 200




@app.route("/search", methods=["GET"])
def search():
    """
    Search endpoint supporting the Flutter app's Search and Ingestion views.
    Returns YouTube video matches with rich metadata (title, artist, thumbnail, duration).
    """
    q = (request.args.get("q") or "").strip()
    if not q:
        return jsonify({"results": []})

    log.info("Catalog search query: '%s'", q)

    ydl_opts = _get_ydl_opts({
        "quiet": True,
        "extract_flat": True,
        "no_warnings": True,
        "skip_download": True,
    })

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f"ytsearch10:{q}", download=False)

        entries = info.get("entries") or []
        results = []
        for e in entries:
            if not e:
                continue
            vid = e.get("id") or ""
            if not vid:
                continue
            title = e.get("title") or ""
            artist = e.get("uploader") or e.get("channel") or ""
            thumb = e.get("thumbnail") or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
            duration = int(e.get("duration") or 0)

            results.append({
                "video_id": vid,
                "title": title,
                "artist": artist,
                "thumbnail_url": thumb,
                "cover_url": thumb,
                "duration_sec": duration,
                "source": "youtube"
            })

        log.info("Search returned %d results for '%s'", len(results), q)
        return jsonify({"results": results})

    except Exception as exc:
        log.exception("Search failed: %s", exc)
        return jsonify({"error": str(exc), "results": []}), 500


@app.route("/preview", methods=["GET"])
def preview():
    """
    Direct audio preview streaming URL endpoint for Flutter client.
    """
    video_id = (request.args.get("video_id") or "").strip()
    if not video_id:
        return jsonify({"error": "video_id is required"}), 400

    log.info("Generating preview URL for video_id: %s", video_id)
    ydl_opts = _get_ydl_opts({
        "format": "m4a/bestaudio/best",
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
    })
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            url = info.get("url")
            return jsonify({"url": url})
    except Exception as exc:
        log.exception("Preview generation failed: %s", exc)
        return jsonify({"error": str(exc)}), 500


@app.route("/ingest", methods=["POST"])
def ingest():
    """
    Hybrid Ingestion Pipeline:
    1. Check Deduplication in Firestore.
    2. If video_id passed directly -> Ingest via YouTube immediately.
    3. If title/artist or spotify_url passed:
       - Tier 1: Try SpotiFLAC (Official Spotify metadata + Tidal/Qobuz Studio Lossless).
       - Tier 2: If SpotiFLAC fails or song is not on Tidal/Qobuz (regional, Malayalam, indie),
                 smoothly fall back to YouTube without raising an error.
    4. Transcode to 256k AAC M4A (+faststart) & upload to Cloudinary.
    5. Save track in Firestore & link to playlist.
    """
    data = request.get_json(force=True)
    title = (data.get("title") or "").strip()
    artist = (data.get("artist") or "").strip()
    playlist_id = (data.get("playlist_id") or "").strip()
    spotify_url = (data.get("spotify_url") or "").strip()
    video_id = (data.get("video_id") or "").strip()
    thumbnail_url = (data.get("thumbnail_url") or data.get("cover_url") or "").strip()
    bypass_dedup = data.get("bypass_dedup") == True

    if not title and not spotify_url and not video_id:
        return jsonify({"error": "title, spotify_url, or video_id is required"}), 400

    log.info(
        "Ingest request: title='%s', artist='%s', video_id='%s', spotify_url='%s', bypass_dedup=%s",
        title, artist, video_id or "none", spotify_url or "none", bypass_dedup
    )

    try:
        # ─────────────────────────────────────────────────────────────────────
        #  PATH 1: Direct Video ID provided (from Flutter YouTube search)
        # ─────────────────────────────────────────────────────────────────────
        if video_id:
            # Deduplication
            if not bypass_dedup:
                existing_id = _find_existing_track(title, artist, video_id=video_id)
                if existing_id:
                    log.info("Dedup hit for video_id %s -> track %s", video_id, existing_id)
                    if playlist_id:
                        _link_to_playlist(playlist_id, existing_id)
                    return jsonify({
                        "status": "duplicate",
                        "track_id": existing_id,
                        "message": f"Song already exists (id={existing_id}). Linked to playlist."
                    })

            yt_url = f"https://www.youtube.com/watch?v={video_id}"
            yt_thumb = thumbnail_url or f"https://i.ytimg.com/vi/{video_id}/maxresdefault.jpg"

            with tempfile.TemporaryDirectory() as tmpdir:
                m4a_path, duration_ms, err_msg = _download_via_youtube(yt_url, tmpdir)
                if not m4a_path or not os.path.exists(m4a_path):
                    details = f": {err_msg}" if err_msg else ""
                    return jsonify({"error": f"Could not download YouTube audio for video_id: {video_id}{details}"}), 500

                clean_t = title or "YouTube Track"
                clean_a = artist or "Unknown Artist"

                audio_pid = _sanitize_public_id(f"audio/{clean_a}/{clean_t}")
                log.info("Uploading audio to Cloudinary: %s", audio_pid)
                audio_res = cloudinary.uploader.upload(
                    m4a_path,
                    resource_type="video",
                    public_id=audio_pid,
                    overwrite=True,
                    format="m4a",
                )
                audio_url = audio_res["secure_url"]

                cover_url, cover_pid = _upload_square_cover(yt_thumb, clean_t, clean_a)

                meta = {
                    "title": clean_t,
                    "artist": clean_a,
                    "album": "",
                    "duration_ms": duration_ms,
                    "video_id": video_id,
                }
                track_id = _create_firestore_track(
                    meta=meta,
                    secure_url=audio_url,
                    audio_public_id=audio_pid,
                    cover_url=cover_url,
                    cover_public_id=cover_pid,
                    source="youtube",
                    quality="256k_aac_youtube",
                    video_id=video_id
                )

                if playlist_id:
                    _link_to_playlist(playlist_id, track_id)

                return jsonify({
                    "status": "created",
                    "track_id": track_id,
                    "secure_url": audio_url,
                    "cover_url": cover_url,
                    "source": "youtube",
                    "metadata": meta,
                })

        # ─────────────────────────────────────────────────────────────────────
        #  PATH 2: Title / Artist or Spotify URL (Hybrid SpotiFLAC + YouTube)
        # ─────────────────────────────────────────────────────────────────────
        # 1. Resolve Spotify Metadata
        spotify_meta, resolved_spotify_url = _resolve_spotify_track(title, artist, spotify_url=spotify_url)
        if spotify_meta:
            title = spotify_meta["title"]
            artist = spotify_meta["artist"]
            spotify_id = spotify_meta.get("spotify_id", "")
        else:
            spotify_id = ""

        # 2. Deduplication check
        if not bypass_dedup:
            existing_id = _find_existing_track(title, artist, spotify_id=spotify_id)
            if existing_id:
                log.info("Duplicate hit for '%s - %s' -> track %s", title, artist, existing_id)
                if playlist_id:
                    _link_to_playlist(playlist_id, existing_id)
                return jsonify({
                    "status": "duplicate",
                    "track_id": existing_id,
                    "message": f"Song already exists (id={existing_id}). Linked to playlist."
                })

        # 3. Attempt Tier 1: SpotiFLAC (Studio Lossless)
        downloaded_source = None
        duration_ms = 0
        used_engine = None

        with tempfile.TemporaryDirectory() as tmpdir:
            if resolved_spotify_url and SPOTIFLAC_AVAILABLE:
                log.info("Tier 1: Attempting SpotiFLAC lossless engine for '%s - %s'...", title, artist)
                m4a_path, dur = _download_via_spotiflac(resolved_spotify_url, tmpdir)
                if m4a_path and os.path.exists(m4a_path):
                    log.info("Tier 1 OK: SpotiFLAC lossless studio audio obtained ✓")
                    downloaded_source = m4a_path
                    duration_ms = dur
                    used_engine = "spotiflac"

            # 4. Attempt Tier 2: YouTube Fallback (Regional, Malayalam, or unstreamed tracks)
            if not downloaded_source:
                log.info(
                    "Tier 1 (SpotiFLAC) unavailable or track not in lossless catalog for '%s - %s'. "
                    "Engaging Tier 2 YouTube Fallback...", title, artist
                )
                yt_url, yt_thumb, found_vid = _search_youtube(title, artist)
                if not yt_url:
                    return jsonify({
                        "error": f"Track '{title} - {artist}' could not be resolved on Spotify lossless catalog or YouTube."
                    }), 404

                m4a_path, dur, err_msg = _download_via_youtube(yt_url, tmpdir)
                if not m4a_path or not os.path.exists(m4a_path):
                    details = f" ({err_msg})" if err_msg else ""
                    return jsonify({
                        "error": f"Failed to download audio for '{title} - {artist}' via YouTube fallback{details}."
                    }), 500

                log.info("Tier 2 OK: YouTube fallback audio downloaded & transcoded ✓")
                downloaded_source = m4a_path
                duration_ms = dur
                used_engine = "youtube_fallback"

                if not thumbnail_url:
                    thumbnail_url = yt_thumb or _fetch_ytmusic_thumbnail(title, artist)

            # 5. Upload Audio to Cloudinary
            audio_pid = _sanitize_public_id(f"audio/{artist}/{title}")
            log.info("Uploading audio to Cloudinary: %s (%d KB)", audio_pid, os.path.getsize(downloaded_source) // 1024)
            audio_res = cloudinary.uploader.upload(
                downloaded_source,
                resource_type="video",
                public_id=audio_pid,
                overwrite=True,
                format="m4a",
            )
            audio_url = audio_res["secure_url"]

        # 6. Upload Artwork (Prefers Spotify official high-res cover, falls back to YouTube)
        best_cover = (spotify_meta.get("cover_url") if spotify_meta else None) or thumbnail_url
        cover_url, cover_pid = _upload_square_cover(best_cover, title, artist)

        # 7. Save to Firestore
        track_meta = {
            "title": title,
            "artist": artist,
            "album": (spotify_meta.get("album") if spotify_meta else "") or "",
            "duration_ms": duration_ms,
            "spotify_id": spotify_id,
            "spotify_url": resolved_spotify_url or "",
            "video_id": video_id or (found_vid if used_engine == "youtube_fallback" else ""),
        }
        quality_str = "256k_aac_studio_master" if used_engine == "spotiflac" else "256k_aac_youtube_fallback"
        track_id = _create_firestore_track(
            meta=track_meta,
            secure_url=audio_url,
            audio_public_id=audio_pid,
            cover_url=cover_url,
            cover_public_id=cover_pid,
            source=used_engine,
            quality=quality_str,
            video_id=track_meta.get("video_id", "")
        )

        # 8. Link to Playlist
        if playlist_id:
            _link_to_playlist(playlist_id, track_id)

        return jsonify({
            "status": "created",
            "track_id": track_id,
            "secure_url": audio_url,
            "cover_url": cover_url,
            "engine": used_engine,
            "fallback_used": (used_engine == "youtube_fallback"),
            "message": "Spotify lossless unavailable — Retrieved via YouTube fallback ⚡" if used_engine == "youtube_fallback" else "Studio lossless audio added via SpotiFLAC ✓",
            "metadata": track_meta,
        })

    except Exception as exc:
        log.exception("Ingestion failed: %s", exc)
        return jsonify({"error": str(exc)}), 500


@app.route("/delete", methods=["POST"])
def delete_track():
    """
    Complete track deletion:
    1. Cloudinary audio + cover destruction
    2. Firestore playlist references cleanup
    3. Firestore track document deletion
    """
    data = request.get_json(force=True)
    track_id = data.get("track_id")

    if not track_id:
        return jsonify({"error": "track_id is required"}), 400

    try:
        track_ref = db.collection(TRACKS_COL).document(track_id)
        track = track_ref.get()

        if not track.exists:
            return jsonify({"error": "Track not found"}), 404

        d = track.to_dict()
        audio_pid = d.get("audio_public_id")
        cover_pid = d.get("cover_public_id")

        if audio_pid:
            log.info("Deleting audio from Cloudinary: %s", audio_pid)
            cloudinary.uploader.destroy(audio_pid, resource_type="video")
        if cover_pid:
            log.info("Deleting cover from Cloudinary: %s", cover_pid)
            cloudinary.uploader.destroy(cover_pid)

        playlists = db.collection(PLAYLISTS_COL).get()
        batch = db.batch()
        updated_playlists = 0

        for pl_doc in playlists:
            pl_data = pl_doc.to_dict()
            fields = ["trackIds", "track_ids", "songIds"]
            needs_update = False
            update_body = {}

            for f in fields:
                if f in pl_data and isinstance(pl_data[f], list):
                    if track_id in pl_data[f]:
                        update_body[f] = firestore.ArrayRemove([track_id])
                        needs_update = True

            if needs_update:
                batch.update(pl_doc.reference, update_body)
                updated_playlists += 1

        if updated_playlists > 0:
            batch.commit()

        track_ref.delete()

        return jsonify({
            "status": "deleted",
            "track_id": track_id,
            "playlists_cleaned": updated_playlists
        })

    except Exception as e:
        log.exception("Delete failed: %s", e)
        return jsonify({"error": str(e)}), 500


# ─────────────────────────────────────────────────────────────────────────────
#  Local Dev Server
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
