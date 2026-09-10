"""
High-Speed YouTube Music Ingestion Cloud Function
=================================================
Architecture:
    - YouTube Engine: yt-dlp with anti-blocking Android client extractor
      Fast (~10-15s), reliable, supports regional, international, indie, and unstreamed tracks.

Endpoints:
    - POST /ingest   -> Ingest audio track via YouTube directly into Cloudinary + Firestore
    - GET  /search   -> Search YouTube / YT Music catalog
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
import gc
import threading
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

# ─────────────────────────────────────────────────────────────────────────────
#  Bootstrap & Configuration
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")
log = logging.getLogger("youtube_backend")

app = Flask(__name__)

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
#  Keep-Alive Heartbeat Daemon (Prevents Render Free-Tier 15-min Sleep/Cooloff)
# ─────────────────────────────────────────────────────────────────────────────
_KEEP_ALIVE_ACTIVE = False

def _start_keep_alive_daemon():
    """
    Render Free Tier puts Web Services to sleep after 15 minutes of inactivity.
    Render automatically populates RENDER_EXTERNAL_URL (e.g. https://my-app.onrender.com).
    This thread periodically pings the public /ping endpoint every 10 minutes (600s),
    ensuring Render's inactivity timer never expires and preventing cold starts.
    """
    global _KEEP_ALIVE_ACTIVE
    target_url = os.environ.get("RENDER_EXTERNAL_URL") or os.environ.get("KEEP_ALIVE_URL")
    if not target_url:
        log.info("No RENDER_EXTERNAL_URL or KEEP_ALIVE_URL found. Keep-alive daemon not started.")
        return

    ping_endpoint = target_url.rstrip("/") + "/ping"
    interval = int(os.environ.get("KEEP_ALIVE_INTERVAL", "600"))

    def _loop():
        global _KEEP_ALIVE_ACTIVE
        _KEEP_ALIVE_ACTIVE = True
        log.info("Keep-alive daemon started! Pinging %s every %d seconds.", ping_endpoint, interval)
        time.sleep(30)  # Wait for startup to complete
        while True:
            try:
                r = requests.get(ping_endpoint, timeout=20)
                log.info("Keep-alive heartbeat ping to %s -> status %d", ping_endpoint, r.status_code)
            except Exception as e:
                log.warning("Keep-alive heartbeat failed: %s", e)
            time.sleep(interval)

    t = threading.Thread(target=_loop, name="KeepAliveWorker", daemon=True)
    t.start()

# Initialize keep-alive daemon
_start_keep_alive_daemon()

# ─────────────────────────────────────────────────────────────────────────────
#  Anti-Blocking YouTube yt-dlp Configuration
# ─────────────────────────────────────────────────────────────────────────────
_COOKIES_TMP_FILE = None

def _sanitize_and_save_cookies(raw_text: str) -> str | None:
    """Sanitize cookies: normalize whitespace to literal tabs, filter malformed lines, and ensure Netscape header."""
    global _COOKIES_TMP_FILE
    try:
        lines = raw_text.splitlines()
        clean_lines = []
        for l in lines:
            line_str = l.strip()
            if not line_str:
                continue
            if line_str.startswith("#"):
                clean_lines.append(line_str)
                continue
            # Netscape cookie format has 7 columns separated by tabs or whitespace
            parts = re.split(r"\s+", line_str)
            if len(parts) >= 6:
                # Ensure literal tabs: domain, flag, path, secure, expiration, name, value
                clean_lines.append("\t".join(parts))

        sanitized = "\n".join(clean_lines).strip()
        if not sanitized.startswith("# Netscape HTTP Cookie File"):
            sanitized = "# Netscape HTTP Cookie File\n# Generated by Spotify Ingestion\n" + sanitized

        tf = tempfile.NamedTemporaryFile(delete=False, suffix="_yt_cookies.txt", mode="w", encoding="utf-8")
        tf.write(sanitized + "\n")
        tf.flush()
        tf.close()
        _COOKIES_TMP_FILE = tf.name
        log.info("Saved sanitized cookies to: %s (%d bytes, %d valid cookie entries)", _COOKIES_TMP_FILE, len(sanitized), len(clean_lines))
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
    """Ensure a modern JavaScript runtime (Node.js or QuickJS) is available for yt-dlp EJS challenges."""
    global _JS_RUNTIME_PATH
    if _JS_RUNTIME_PATH and (os.path.exists(_JS_RUNTIME_PATH) or shutil.which(_JS_RUNTIME_PATH)):
        return _JS_RUNTIME_PATH

    # 1. Check existing system binaries - Prioritize Node.js
    for name in ["node", "nodejs"]:
        p = shutil.which(name)
        if p:
            _JS_RUNTIME_PATH = p
            return p

    # 2. Check common Linux locations for Node.js
    for p in ["/usr/bin/node", "/usr/local/bin/node", "/usr/bin/nodejs", "/tmp/bin/node"]:
        if os.path.exists(p) and os.access(p, os.X_OK):
            if "/tmp/bin" not in os.environ.get("PATH", ""):
                os.environ["PATH"] = f"/tmp/bin:{os.environ.get('PATH', '')}"
            _JS_RUNTIME_PATH = p
            return p

    # 3. Check for existing qjs
    p = shutil.which("qjs") or ("/tmp/bin/qjs" if os.path.exists("/tmp/bin/qjs") else None)
    if p and os.path.exists(p) and os.access(p, os.X_OK):
        _JS_RUNTIME_PATH = p
        return p

    # 4. Auto-provision QuickJS static Linux binary with wrapper that strips '--script'
    if os.name != "nt":
        target_dir = "/tmp/bin"
        qjs_real = os.path.join(target_dir, "qjs_bin")
        qjs_wrapper = os.path.join(target_dir, "qjs")
        if os.path.exists(qjs_wrapper) and os.access(qjs_wrapper, os.X_OK):
            if target_dir not in os.environ.get("PATH", ""):
                os.environ["PATH"] = f"{target_dir}:{os.environ.get('PATH', '')}"
            _JS_RUNTIME_PATH = qjs_wrapper
            return qjs_wrapper

        try:
            log.info("Downloading standalone QuickJS static Linux binary for yt-dlp challenge solving...")
            os.makedirs(target_dir, exist_ok=True)
            qjs_url = "https://github.com/quickjs-ng/quickjs/releases/download/v0.16.2/qjs-linux-x86_64"
            resp = requests.get(qjs_url, timeout=45)
            if resp.status_code == 200 and len(resp.content) > 1000000:
                with open(qjs_real, "wb") as f:
                    f.write(resp.content)
                os.chmod(qjs_real, 0o755)

                # Write shell wrapper to strip '--script' flag which yt-dlp passes but qjs rejects
                with open(qjs_wrapper, "w") as f:
                    f.write("#!/bin/sh\n")
                    f.write('ARGS=""\n')
                    f.write('for a in "$@"; do\n')
                    f.write('  if [ "$a" != "--script" ]; then\n')
                    f.write('    ARGS="$ARGS \\"$a\\""\n')
                    f.write('  fi\n')
                    f.write('done\n')
                    f.write(f'eval exec {qjs_real} $ARGS\n')
                os.chmod(qjs_wrapper, 0o755)

                if target_dir not in os.environ.get("PATH", ""):
                    os.environ["PATH"] = f"{target_dir}:{os.environ.get('PATH', '')}"
                log.info("QuickJS wrapper installed successfully at: %s", qjs_wrapper)
                _JS_RUNTIME_PATH = qjs_wrapper
                return qjs_wrapper
        except Exception as e:
            log.warning("Failed to auto-install QuickJS runtime: %s", e)

    return None


def _get_ydl_opts(base_opts: dict) -> dict:
    """
    Return hardened yt-dlp options configured to prevent datacenter IP blocks.
    Uses authenticated cookies with JS challenge solving, or VisionOS/Android fallback.
    """
    opts = base_opts.copy()

    # Enable automated EJS challenge solver
    opts.setdefault("remote_components", {"ejs:github"})

    # Configure JS runtime if available (node, quickjs, etc.)
    js_bin = _ensure_js_runtime()
    if js_bin:
        runtime_name = "node" if "node" in os.path.basename(js_bin).lower() else "quickjs"
        opts["js_runtimes"] = {runtime_name: {"path": js_bin}}
        log.info("yt-dlp using %s JS runtime at: %s", runtime_name, js_bin)
    else:
        log.warning("No JS runtime (node/quickjs) available for yt-dlp!")

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
    opts.setdefault("socket_timeout", 20)
    opts.setdefault("retries", 2)

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
        safe_input = input_path
        temp_created = False
        try:
            basename = os.path.basename(input_path)
            if any(ch in basename for ch in ("'", '"', '&', '#', '$')):
                dirname = os.path.dirname(input_path)
                ext = os.path.splitext(input_path)[1]
                safe_input = os.path.join(dirname, f"ffmpeg_in_{int(time.time()*1000)}{ext}")
                shutil.copy2(input_path, safe_input)
                temp_created = True

            cmd = [
                "ffmpeg", "-y", "-i", safe_input,
                "-vn",
                "-threads", "0",
                "-c:a", "aac",
                "-b:a", bitrate,
                "-ar", "44100",
                "-movflags", "+faststart",
                output_path
            ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if res.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
                log.info("Audio transcoded via ffmpeg -> %s (%d KB)", output_path, os.path.getsize(output_path) // 1024)
                return True
            else:
                err_text = res.stderr.decode('utf-8', errors='ignore')[-200:] if res.stderr else "unknown"
                log.warning("ffmpeg CLI returned %d: %s", res.returncode, err_text)
        except Exception as e:
            log.warning("ffmpeg CLI transcoding failed, falling back to pydub: %s", e)
        finally:
            if temp_created and os.path.exists(safe_input):
                try:
                    os.remove(safe_input)
                except Exception:
                    pass

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
#  YouTube Downloader & Search
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
    Download audio via yt-dlp with multi-strategy fallbacks and transcode to 256k AAC M4A.
    Strategy 1: Android client (bypasses YouTube SABR streaming & "The page needs to be reloaded").
    Strategy 2: Authenticated cookies (sanitized, with EJS JS runtime).
    Strategy 3: iOS / TV embedded clients.
    Returns (transcoded_m4a_path, duration_ms, error_message).
    """
    out_tpl = os.path.join(output_dir, "%(id)s.%(ext)s")
    base_ydl = {
        "format": "m4a/bestaudio/best",
        "outtmpl": out_tpl,
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "windowsfilenames": True,
        "restrictfilenames": True,
        "socket_timeout": 20,
        "retries": 2,
        "buffersize": 64 * 1024,
        "http_chunk_size": 1024 * 1024,
    }

    strategies = []
    cookie_file = _get_cookie_file_path()
    if cookie_file:
        strat_auth = _get_ydl_opts(base_ydl.copy())
        strategies.append(("Authenticated Cookie Mode (EJS)", strat_auth))

    strategies.append(("Android Client (SABR-Bypass)", {
        **base_ydl,
        "extractor_args": {"youtube": {"player_client": ["android"]}}
    }))

    strategies.append(("iOS / TV Fallback", {
        **base_ydl,
        "extractor_args": {"youtube": {"player_client": ["ios", "tv_embedded"]}}
    }))

    class CapturedLogger:
        def __init__(self):
            self.lines = []
        def debug(self, msg):
            if any(k in msg for k in ["[jsc", "challenge", "solver", "EJS", "error", "warn", "client", "format", "bot", "Sign in", "deno", "node"]):
                self.lines.append(f"[debug] {msg}")
        def warning(self, msg):
            self.lines.append(f"[warn] {msg}")
        def error(self, msg):
            self.lines.append(f"[err] {msg}")

    last_err = None
    diag_logs = []
    for name, opts in strategies:
        cl = CapturedLogger()
        opts["logger"] = cl
        opts["verbose"] = True
        opts["quiet"] = False
        try:
            log.info("Attempting YouTube audio download via [%s] from: %s", name, yt_url)
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(yt_url, download=True)
                duration_sec = info.get("duration") or 0
                duration_ms = int(float(duration_sec) * 1000) if duration_sec else 0

            # Locate downloaded file (look for .m4a first)
            m4a_files = list(Path(output_dir).glob("*.m4a"))
            all_files = [f for f in Path(output_dir).iterdir() if f.is_file()]
            downloaded = m4a_files or all_files

            if not downloaded:
                log.warning("[%s] produced no files in output dir.", name)
                continue

            source_file = str(downloaded[0])
            log.info("[%s] produced file: %s (%d KB)", name, source_file, os.path.getsize(source_file) // 1024)

            transcoded_m4a = os.path.join(output_dir, "transcoded_yt_audio.m4a")
            if _transcode_audio_to_m4a(source_file, transcoded_m4a, bitrate="256k"):
                dur = _get_audio_duration_ms(transcoded_m4a) or duration_ms
                return transcoded_m4a, dur, None
            elif source_file.endswith(".m4a"):
                dur = _get_audio_duration_ms(source_file) or duration_ms
                return source_file, dur, None

        except Exception as e:
            last_err = str(e)
            tail = " | ".join(cl.lines[-6:])
            diag_logs.append(f"[{name}: {last_err} (logs: {tail})]")
            log.warning("Strategy [%s] failed for %s: %s (logs: %s)", name, yt_url, e, tail)

    combined_err = " ; ".join(diag_logs) if diag_logs else (last_err or "All strategies failed")
    return None, 0, combined_err


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
    source: str = "youtube",
    quality: str = "256k_aac_high",
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
    cookie_path = _get_cookie_file_path()
    cookie_present = bool(cookie_path)
    cookie_has_login = False
    cookie_has_sid = False
    cookie_size = 0
    if cookie_path and os.path.exists(cookie_path):
        cookie_size = os.path.getsize(cookie_path)
        try:
            with open(cookie_path, "r", errors="ignore") as f:
                content = f.read()
            cookie_has_login = "LOGIN_INFO" in content
            cookie_has_sid = "\tSID\t" in content or " SID " in content
        except Exception:
            pass

    js_bin = _ensure_js_runtime()
    cur_dir = os.path.dirname(__file__)
    dir_files = os.listdir(cur_dir) if os.path.exists(cur_dir) else []

    return jsonify({
        "status": "online",
        "version": "1.4.0",
        "engine": "YouTube High-Speed Ingestion Engine",
        "youtube_available": True,
        "youtube_cookies_loaded": cookie_present,
        "cookie_path": cookie_path,
        "cookie_size": cookie_size,
        "cookie_has_sid": cookie_has_sid,
        "cookie_has_login": cookie_has_login,
        "env_youtube_cookies_len": len(os.environ.get("YOUTUBE_COOKIES", "")),
        "env_youtube_cookies_b64_len": len(os.environ.get("YOUTUBE_COOKIES_BASE64", "")),
        "ffmpeg_available": bool(shutil.which("ffmpeg")),
        "node_available": bool(shutil.which("node")),
        "js_runtime_available": bool(js_bin),
        "js_runtime_path": js_bin,
        "keep_alive_active": _KEEP_ALIVE_ACTIVE,
        "keep_alive_target": os.environ.get("RENDER_EXTERNAL_URL") or os.environ.get("KEEP_ALIVE_URL") or "none",
        "dir_files": dir_files,
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
    ydl_opts = {
        "format": "m4a/bestaudio/best",
        "extractor_args": {"youtube": {"player_client": ["android", "ios"]}},
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
    }
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
    High-Speed YouTube Ingestion Pipeline:
    1. Parse request (title, artist, video_id, thumbnail_url, playlist_id).
    2. Resolve YouTube video URL and High-Res thumbnail if needed.
    3. Check Deduplication in Firestore.
    4. Download audio via yt-dlp & transcode to 256k AAC M4A via FFmpeg.
    5. Concurrently upload audio + cover art to Cloudinary.
    6. Save track in Firestore & link to playlist.
    """
    data = request.get_json(force=True)
    title = (data.get("title") or "").strip()
    artist = (data.get("artist") or "").strip()
    playlist_id = (data.get("playlist_id") or "").strip()
    video_id = (data.get("video_id") or "").strip()
    thumbnail_url = (data.get("thumbnail_url") or data.get("cover_url") or "").strip()
    bypass_dedup = data.get("bypass_dedup") is True

    if not title and not video_id:
        return jsonify({"error": "title or video_id is required"}), 400

    log.info(
        "Ingest request: title='%s', artist='%s', video_id='%s', bypass_dedup=%s",
        title, artist, video_id or "none", bypass_dedup
    )

    try:
        # 1. Resolve YouTube video and thumbnail
        found_vid = video_id
        yt_url = f"https://www.youtube.com/watch?v={video_id}" if video_id else None
        yt_thumb = thumbnail_url

        if not yt_url:
            yt_url, yt_thumb, found_vid = _search_youtube(title, artist)
            if not yt_url:
                return jsonify({
                    "error": f"Track '{title} - {artist}' could not be found on YouTube."
                }), 404

        # Prefer high-resolution YouTube Music thumbnail if available
        best_cover = thumbnail_url or yt_thumb
        if not best_cover or "hqdefault" in best_cover or "mqdefault" in best_cover:
            ytm_thumb = _fetch_ytmusic_thumbnail(title, artist)
            if ytm_thumb:
                best_cover = ytm_thumb

        # 2. Deduplication check across video_id and title/artist
        if not bypass_dedup:
            existing_id = _find_existing_track(title, artist, video_id=found_vid)
            if existing_id:
                log.info("Dedup hit for '%s - %s' (vid=%s) -> track %s", title, artist, found_vid, existing_id)
                if playlist_id:
                    _link_to_playlist(playlist_id, existing_id)
                return jsonify({
                    "status": "duplicate",
                    "track_id": existing_id,
                    "message": f"Song already exists (id={existing_id}). Linked to playlist."
                })

        # 3. Download & Transcode via YouTube
        with tempfile.TemporaryDirectory() as tmpdir:
            log.info("Downloading audio via YouTube for '%s - %s' (%s)...", title, artist, yt_url)
            m4a_path, duration_ms, err_msg = _download_via_youtube(yt_url, tmpdir)
            if not m4a_path or not os.path.exists(m4a_path):
                details = f" ({err_msg})" if err_msg else ""
                return jsonify({
                    "error": f"Failed to download audio for '{title} - {artist}' via YouTube{details}."
                }), 500

            log.info("Audio downloaded & transcoded to M4A ✓ (%d ms)", duration_ms)

            # 4. Upload Audio and Artwork to Cloudinary concurrently
            audio_pid = _sanitize_public_id(f"audio/{artist}/{title}")
            log.info("Uploading audio (%d KB) and cover concurrently to Cloudinary...", os.path.getsize(m4a_path) // 1024)

            from concurrent.futures import ThreadPoolExecutor

            def _upload_audio_task():
                return cloudinary.uploader.upload(
                    m4a_path,
                    resource_type="video",
                    public_id=audio_pid,
                    overwrite=True,
                    format="m4a",
                )

            def _upload_cover_task():
                return _upload_square_cover(best_cover, title, artist)

            with ThreadPoolExecutor(max_workers=2) as executor:
                audio_future = executor.submit(_upload_audio_task)
                cover_future = executor.submit(_upload_cover_task)
                audio_res = audio_future.result()
                cover_url, cover_pid = cover_future.result()

            audio_url = audio_res["secure_url"]

        # 5. Save to Firestore
        track_meta = {
            "title": title,
            "artist": artist,
            "album": "",
            "duration_ms": duration_ms,
            "video_id": found_vid or "",
        }
        track_id = _create_firestore_track(
            meta=track_meta,
            secure_url=audio_url,
            audio_public_id=audio_pid,
            cover_url=cover_url,
            cover_public_id=cover_pid,
            source="youtube",
            quality="256k_aac_high",
            video_id=found_vid or "",
        )

        # 6. Link to Playlist
        if playlist_id:
            _link_to_playlist(playlist_id, track_id)

        return jsonify({
            "status": "created",
            "track_id": track_id,
            "secure_url": audio_url,
            "cover_url": cover_url,
            "engine": "youtube",
            "fallback_used": False,
            "message": "Track successfully ingested via YouTube ⚡",
            "metadata": track_meta,
        })

    except Exception as exc:
        log.exception("Ingestion failed: %s", exc)
        return jsonify({"error": str(exc)}), 500
    finally:
        gc.collect()


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
    app.run(host="0.0.0.0", port=port, debug=False, threaded=True)
