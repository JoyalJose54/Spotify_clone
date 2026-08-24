"""
Smart Ingestion Cloud Function
===============================
Endpoint: POST /ingest
Body:
    {
        "title":       "Blinding Lights",
        "artist":      "The Weeknd",
        "playlist_id": "abc123"          # optional – Firestore playlist doc ID
    }

Env vars required:
    CLOUDINARY_CLOUD_NAME
    CLOUDINARY_API_KEY
    CLOUDINARY_API_SECRET
    FIREBASE_CREDENTIALS_JSON   <- path to service-account JSON (or use ADC)

Workflow:
    1.  Deduplicate – query Firestore `tracks` by title+artist (case-insensitive).
    2a. If found  → just arrayUnion the track ID into the playlist.
    2b. If new    →
          Tier-1: MusicBrainz  → metadata + cover
          Tier-2: YouTube Music scrape → "Official Audio" thumbnail
          Tier-3: yt-dlp first result thumbnail (center-crop)
        Then:
          yt-dlp download as M4A → upload to Cloudinary
          Square-crop cover (Cloudinary transform or Pillow)
          Write new Firestore document
          arrayUnion track ID into playlist
"""

import os
import re
import json
import time
import tempfile
import logging
import urllib.parse
import base64
import io
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

# ─────────────────────────────────────────────────────────────────────────────
#  Bootstrap
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")
log = logging.getLogger("ingest")

app = Flask(__name__)

# Firebase
_cred_path = os.environ.get("FIREBASE_CREDENTIALS_JSON", os.path.join(os.path.dirname(os.path.abspath(__file__)), "../database/firebase-key.json"))
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

# Cloudinary
cloudinary.config(
    cloud_name=os.environ.get("CLOUDINARY_CLOUD_NAME", "YOUR_CLOUDINARY_CLOUD_NAME"),
    api_key=os.environ.get("CLOUDINARY_API_KEY", "YOUR_CLOUDINARY_API_KEY"),
    api_secret=os.environ.get("CLOUDINARY_API_SECRET", "YOUR_CLOUDINARY_API_SECRET"),
    secure=True,
)

TRACKS_COL    = "tracks"
PLAYLISTS_COL = "playlists"
MB_BASE       = "https://musicbrainz.org/ws/2"
CAA_BASE      = "https://coverartarchive.org"
MB_USER_AGENT = "SpotifyCloneIngestion/1.0 (your-email@example.com)"  # MB policy — update this with your actual email
YT_MUSIC_SEARCH = "https://music.youtube.com/search?q="
# A list of Shazam API keys to fallback if one exceeds its quota.
# Can be configured via environment variable as a comma-separated list.
SHAZAM_KEYS_ENV = os.environ.get("SHAZAM_KEYS", "")
if SHAZAM_KEYS_ENV:
    SHAZAM_KEYS = [k.strip() for k in SHAZAM_KEYS_ENV.split(",") if k.strip()]
else:
    single_key = os.environ.get("SHAZAM_KEY", "")
    SHAZAM_KEYS = [single_key] if single_key else []






# ─────────────────────────────────────────────────────────────────────────────
#  Main endpoint
# ─────────────────────────────────────────────────────────────────────────────
@app.route("/ingest", methods=["POST"])
def ingest():
    data = request.get_json(force=True)
    title       = (data.get("title")       or "").strip()
    artist      = (data.get("artist")      or "").strip()
    playlist_id = (data.get("playlist_id") or "").strip()
    video_id    = (data.get("video_id")    or "").strip()   # optional YouTube video ID
    thumbnail_url = (data.get("thumbnail_url") or data.get("cover_url") or "").strip()
    bypass_dedup = data.get("bypass_dedup") == True

    if not title or not artist:
        return jsonify({"error": "title and artist are required"}), 400

    log.info("Ingesting: %s – %s (video_id=%s, bypass_dedup=%s, thumbnail_url=%s)", artist, title, video_id or "none", bypass_dedup, thumbnail_url or "none")

    try:
        # ── Step 1: Deduplicate ──────────────────────────────────────────────
        existing_id = None
        if not bypass_dedup:
            existing_id = _find_existing_track(title, artist, video_id=video_id)

        if existing_id:
            log.info("Duplicate found: %s — skipping upload.", existing_id)
            if playlist_id:
                _link_to_playlist(playlist_id, existing_id)
            return jsonify({
                "status":   "duplicate",
                "track_id": existing_id,
                "message":  f"Song already exists (id={existing_id}). Linked to playlist."
            })

        # ── Step 2: Resolve YouTube Video URL & Thumbnail ───────────────────
        if video_id:
            yt_url      = f"https://www.youtube.com/watch?v={video_id}"
            yt_thumb_url = thumbnail_url or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
        else:
            yt_url, searched_thumb = _search_youtube(title, artist)
            yt_thumb_url = thumbnail_url or searched_thumb
        if not yt_url:
            return jsonify({"error": "Song not found on YouTube"}), 404

        # ── Step 2.5: Metadata waterfall ─────────────────────────────────────
        meta = _metadata_waterfall(title, artist, yt_thumb=yt_thumb_url)
        log.info("Metadata: %s", json.dumps(meta, ensure_ascii=False))

        # ── Step 3: Download audio via yt-dlp ────────────────────────────────
        audio_url, audio_pid, duration_ms = _download_and_upload_audio(yt_url, title, artist)
        meta["duration_ms"] = duration_ms

        # ── Step 3.5: Shazam identification ──────────────────────────────────
        # Preserve the original CSV title/artist as an alias BEFORE Shazam may rename them.
        original_title  = title
        original_artist = artist

        shazam_meta = _identify_with_shazam(audio_url)
        shazam_updated = False
        if shazam_meta:
            log.info("Shazam found: %s by %s", shazam_meta['title'], shazam_meta['artist'])
            title = shazam_meta['title']
            artist = shazam_meta['artist']
            if shazam_meta.get('cover'):
                meta["cover_url"] = shazam_meta['cover']
            meta["source"] = "shazam"
            meta["title"] = title
            meta["artist"] = artist
            shazam_updated = True

            # Double-check duplicates after Shazam re-identification
            if not bypass_dedup:
                post_shazam_dup = _find_existing_track(title, artist)
                if post_shazam_dup:
                    log.info("Post-Shazam Duplicate found: %s — clean up audio and link to playlist.", post_shazam_dup)
                    try:
                        cloudinary.uploader.destroy(audio_pid, resource_type="video")
                        log.info("Cleaned up duplicate audio file: %s", audio_pid)
                    except Exception as e:
                        log.warning("Failed to clean up duplicate Cloudinary audio: %s", e)

                    if playlist_id:
                        _link_to_playlist(playlist_id, post_shazam_dup)

                    return jsonify({
                        "status":   "duplicate",
                        "track_id": post_shazam_dup,
                        "message":  f"Song already exists after Shazam ID (id={post_shazam_dup}). Linked to playlist."
                    })
        else:
            log.info("Shazam could not identify the track. Using fallback metadata.")
            shazam_updated = True

        # ── Step 4: Upload square cover art ──────────────────────────────────
        cover_url_src = meta.get("cover_url") or yt_thumb_url
        cover_url, cover_pid = _upload_square_cover(cover_url_src, title, artist)

        # ── Step 5: Write Firestore document ─────────────────────────────────
        track_id = _create_firestore_track(
            title=title,
            artist=artist,
            meta=meta,
            secure_url=audio_url,
            audio_public_id=audio_pid,
            cover_url=cover_url,
            cover_public_id=cover_pid,
            video_id=video_id,
            shazam_updated=shazam_updated,
            original_title=original_title,
            original_artist=original_artist,
        )

        # ── Step 6: Link to playlist ─────────────────────────────────────────
        if playlist_id:
            _link_to_playlist(playlist_id, track_id)

        return jsonify({
            "status":      "created",
            "track_id":    track_id,
            "secure_url":  audio_url,
            "cover_url":   cover_url,
            "metadata":    meta,
        })

    except Exception as exc:
        log.exception("Ingestion failed")
        return jsonify({"error": str(exc)}), 500


# ─────────────────────────────────────────────────────────────────────────────
#  Deduplication
# ─────────────────────────────────────────────────────────────────────────────
def _levenshtein_distance(s1: str, s2: str) -> int:
    if s1 == s2:
        return 0
    if len(s1) < len(s2):
        return _levenshtein_distance(s2, s1)
    if not s2:
        return len(s1)

    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row

    return previous_row[-1]


def _is_fuzzy_duplicate(title_a: str, title_b: str) -> bool:
    clean_a = re.sub(r"\(.*?\)", "", title_a.lower())
    clean_a = re.sub(r"\[.*?\]", "", clean_a)
    clean_a = re.sub(r"[^\w\s]", "", clean_a)
    clean_a = re.sub(r"\s+", " ", clean_a).strip()

    clean_b = re.sub(r"\(.*?\)", "", title_b.lower())
    clean_b = re.sub(r"\[.*?\]", "", clean_b)
    clean_b = re.sub(r"[^\w\s]", "", clean_b)
    clean_b = re.sub(r"\s+", " ", clean_b).strip()

    if clean_a == clean_b:
        return True
    if not clean_a or not clean_b:
        return False

    # 1. Levenshtein distance <= 2
    if _levenshtein_distance(clean_a, clean_b) <= 2:
        return True

    # 2. Word-based matching
    words_a = [w for w in clean_a.split(" ") if w]
    words_b = [w for w in clean_b.split(" ") if w]

    if not words_a or not words_b:
        return False

    # First word matching
    if len(words_a[0]) >= 4 and words_a[0] == words_b[0]:
        return True

    # First 2 words matching
    if len(words_a) >= 2 and len(words_b) >= 2:
        if words_a[0] == words_b[0] and words_a[1] == words_b[1]:
            return True

    # Substring matching
    if len(clean_a) >= 4 and len(clean_b) >= 4:
        if clean_b in clean_a or clean_a in clean_b:
            return True

    return False


def _find_existing_track(title: str, artist: str, video_id: str = "") -> str | None:
    """
    Multi-strategy duplicate detection:
      1. video_id exact match  (fastest – YouTube-sourced tracks only)
      2. title_lc + artist_lc shadow fields (new tracks always have these)
      3. alias_keys array field – catches Shazam-renamed tracks
      4. Raw title + artist  (case-sensitive fallback for older tracks)
      5. Full-collection fuzzy scan  (catches title spelling variations, prefixes, substrings)
    """
    title_lc  = _normalize(title)
    artist_lc = _normalize(artist)
    alias_key = f"{title_lc}||{artist_lc}"

    # ── Strategy 1: YouTube video_id ─────────────────────────────────────────
    if video_id:
        snap = (db.collection(TRACKS_COL)
                  .where("video_id", "==", video_id)
                  .limit(1)
                  .get())
        if snap:
            log.info("Dedup hit (video_id): %s", snap[0].id)
            return snap[0].id

    # ── Strategy 2: lowercase shadow fields ──────────────────────────────────
    snap = (db.collection(TRACKS_COL)
              .where("title_lc", "==", title_lc)
              .where("artist_lc", "==", artist_lc)
              .limit(1)
              .get())
    if snap:
        log.info("Dedup hit (shadow fields): %s", snap[0].id)
        return snap[0].id

    # ── Strategy 3: alias_keys array (catches Shazam-renamed tracks) ─────────
    # alias_keys stores "original_title_lc||original_artist_lc" strings.
    snap3 = (db.collection(TRACKS_COL)
               .where("alias_keys", "array_contains", alias_key)
               .limit(1)
               .get())
    if snap3:
        log.info("Dedup hit (alias_keys): %s", snap3[0].id)
        return snap3[0].id

    # ── Strategy 4: raw case-sensitive fields ─────────────────────────────────
    snap4 = (db.collection(TRACKS_COL)
               .where("title", "==", title)
               .where("artist", "==", artist)
               .limit(1)
               .get())
    if snap4:
        log.info("Dedup hit (raw fields): %s", snap4[0].id)
        return snap4[0].id

    # ── Strategy 5: full-collection fuzzy scan (legacy & variation safety net) 
    all_tracks = db.collection(TRACKS_COL).stream()
    for doc in all_tracks:
        d = doc.to_dict()
        existing_title = d.get("title", "")
        if _is_fuzzy_duplicate(title, existing_title):
            log.info("Dedup hit (fuzzy scan): %s vs %s -> %s", title, existing_title, doc.id)
            # Back-fill shadow fields so next check is fast
            doc.reference.update({"title_lc": title_lc, "artist_lc": artist_lc})
            return doc.id
        for ak in d.get("alias_keys", []):
            if "||" in ak:
                existing_alias_title = ak.split("||")[0]
                if _is_fuzzy_duplicate(title_lc, existing_alias_title):
                    log.info("Dedup hit (fuzzy alias scan): %s vs %s -> %s", title, existing_alias_title, doc.id)
                    return doc.id

    return None


def _normalize(s: str) -> str:
    """Lowercase + collapse whitespace + strip punctuation for fuzzy matching."""
    s = s.lower().strip()
    s = re.sub(r"[^\w\s]", "", s)   # remove punctuation
    s = re.sub(r"\s+", " ", s)       # collapse spaces
    return s


# ─────────────────────────────────────────────────────────────────────────────
#  Metadata Waterfall
# ─────────────────────────────────────────────────────────────────────────────
def _metadata_waterfall(title: str, artist: str, yt_thumb: str = None) -> dict:
    """
    Cleaned up metadata waterfall utilizing YouTube sources only:
      - Tier 1: exact YouTube video thumbnail passed from search/dl
      - Tier 2: lightweight HTML scrape of YouTube Music (fallback)
    """
    meta = {
        "title": title,
        "artist": artist,
        "cover_url": None,
        "album": "",
        "duration_ms": 0,
        "release_year": None,
        "genre": "",
        "source": "none"
    }

    # ── Tier 1: Use the exact YouTube video thumbnail passed into the function ──
    if yt_thumb:
        meta["cover_url"] = yt_thumb
        meta["source"] = "youtube_thumbnail"
        log.info("Tier-1 YouTube Thumbnail OK ✓")
        return meta

    # ── Tier 2: Use the lightweight YouTube Music scrape as fallback ──
    try:
        ytm_thumb = _fetch_ytmusic_thumbnail(title, artist)
        if ytm_thumb:
            meta["cover_url"] = ytm_thumb
            meta["source"] = "ytmusic"
            log.info("Tier-2 YouTube Music OK ✓")
            return meta
    except Exception as e:
        log.warning("YouTube Music scrape failed: %s", e)

    meta["source"] = "youtube_fallback"
    return meta


def _fetch_ytmusic_thumbnail(title: str, artist: str) -> str | None:
    """
    Query YouTube Music search page and extract the best thumbnail
    (prefers 'Official Audio' results).
    NOTE: This is a lightweight HTML scrape — no ytmusicapi dependency needed.
    """
    query    = f"{artist} {title} official audio"
    url      = YT_MUSIC_SEARCH + urllib.parse.quote(query)
    headers  = {
        "User-Agent": ("Mozilla/5.0 (Linux; Android 10) "
                       "AppleWebKit/537.36 Chrome/91 Safari/537.36"),
        "Accept-Language": "en-US,en;q=0.9",
    }

    resp = requests.get(url, headers=headers, timeout=10)
    if resp.status_code != 200:
        return None

    # Extract video IDs from response (yt-music embeds them as JSON)
    ids = re.findall(r'"videoId":"([A-Za-z0-9_-]{11})"', resp.text)
    if not ids:
        return None

    # Prefer the first "Official Audio" result; otherwise first result
    vid_id = ids[0]
    return f"https://i.ytimg.com/vi/{vid_id}/maxresdefault.jpg"


def _get_ydl_opts(base_opts: dict) -> dict:
    opts = base_opts.copy()
    
    # 2. Check if a local cookies.txt file exists
    if os.path.exists("cookies.txt"):
        opts["cookiefile"] = "cookies.txt"
        log.info("Using local cookies.txt for yt-dlp.")
        
    return opts


# ─────────────────────────────────────────────────────────────────────────────
#  YouTube search (yt-dlp)
# ─────────────────────────────────────────────────────────────────────────────
def _search_youtube(title: str, artist: str) -> tuple[str | None, str | None]:
    """Return (watch_url, thumbnail_url) for the best YouTube match."""
    query = f"ytsearch1:{artist} {title} official audio"
    ydl_opts = _get_ydl_opts({
        "quiet":       True,
        "no_warnings": True,
        "extract_flat": True,
    })
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(query, download=False)

    entries = info.get("entries") or []
    if not entries:
        return None, None

    entry = entries[0]
    vid_id    = entry.get("id")
    watch_url = f"https://www.youtube.com/watch?v={vid_id}" if vid_id else None
    thumb_url = (entry.get("thumbnail") or
                 f"https://i.ytimg.com/vi/{vid_id}/maxresdefault.jpg")
    return watch_url, thumb_url


# ─────────────────────────────────────────────────────────────────────────────
#  Audio download + Cloudinary upload
# ─────────────────────────────────────────────────────────────────────────────
def _download_and_upload_audio(yt_url: str, title: str, artist: str) -> tuple[str, str, int]:
    """Download audio via yt-dlp to a temp file, then upload to Cloudinary."""
    with tempfile.TemporaryDirectory() as tmpdir:
        out_tpl  = os.path.join(tmpdir, "%(title)s.%(ext)s")
        ydl_opts = _get_ydl_opts({
            "format":        "bestaudio/best",
            "outtmpl":       out_tpl,
            "quiet":         True,
            "no_warnings":   True,
            "postprocessors": [{
                "key":              "FFmpegExtractAudio",
                "preferredcodec":   "m4a",
                "preferredquality": "192",
            }],
            "noplaylist": True,
        })
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(yt_url, download=True)
            duration_sec = info.get("duration")
            try:
                duration_ms = int(float(duration_sec) * 1000) if duration_sec else 0
            except (ValueError, TypeError):
                duration_ms = 0

        # Find the downloaded file
        files = list(Path(tmpdir).glob("*.m4a"))
        if not files:
            # Fallback: look for any file in the temp directory
            files = [f for f in Path(tmpdir).iterdir() if f.is_file()]
        if not files:
            raise FileNotFoundError("yt-dlp did not produce any audio file.")

        local_path = str(files[0])
        public_id  = _sanitize_public_id(f"audio/{artist}/{title}")

        log.info("Uploading audio to Cloudinary: %s", public_id)
        result = cloudinary.uploader.upload(
            local_path,
            resource_type="video",   # Cloudinary treats audio as "video"
            public_id=public_id,
            overwrite=True,
            format="m4a",
        )
        return result["secure_url"], public_id, duration_ms


# ─────────────────────────────────────────────────────────────────────────────
#  Cover art upload (square crop via Cloudinary transformation)
# ─────────────────────────────────────────────────────────────────────────────
def _upload_square_cover(image_url: str | None, title: str, artist: str) -> str:
    """
    Upload cover art to Cloudinary.  Applies gravity=center + crop to make
    the image perfectly square (works for any aspect ratio).
    """
    if not image_url:
        return ""

    # Upgrade resolution if it's an Apple/Shazam CDN link
    if "mzstatic.com" in image_url:
        if "/" in image_url:
            base_url, _ = image_url.rsplit('/', 1)
            image_url = f"{base_url}/640x640bb.jpg"

    public_id = _sanitize_public_id(f"covers/{artist}/{title}")
    log.info("Uploading cover to Cloudinary: %s", public_id)

    result = cloudinary.uploader.upload(
        image_url,
        public_id=public_id,
        overwrite=True,
        transformation=[{
            "width":   640,
            "height":  640,
            "crop":    "fill",
            "gravity": "center",
        }],
        format="jpg",
    )
    return result["secure_url"], public_id


# ─────────────────────────────────────────────────────────────────────────────
#  Firestore write
# ─────────────────────────────────────────────────────────────────────────────
def _create_firestore_track(
    title: str,
    artist: str,
    meta: dict,
    secure_url: str,
    audio_public_id: str,
    cover_url: str,
    cover_public_id: str,
    video_id: str = "",
    shazam_updated: bool = False,
    original_title: str = "",
    original_artist: str = "",
) -> str:
    """Create a document in `tracks` and return the new doc ID."""
    doc_ref = db.collection(TRACKS_COL).document()

    # Build alias_keys: a list of "title_lc||artist_lc" strings for all known
    # name variants of this track so future dedup queries can find it even if
    # Shazam renamed it.
    alias_keys = set()
    alias_keys.add(f"{_normalize(title)}||{_normalize(artist)}")
    if original_title and original_artist:
        alias_keys.add(f"{_normalize(original_title)}||{_normalize(original_artist)}")

    genre = meta.get("genre", "")

    doc_data = {
        # Core fields (match existing Song.fromFirestore mapping)
        "title":        title,
        "artist":       artist,
        "album":        meta.get("album", ""),
        "secure_url":      secure_url,
        "audio_public_id": audio_public_id,
        "imageUrl":        cover_url,
        "cover_public_id": cover_public_id,
        "duration_ms":  meta.get("duration_ms", 0),
        "trackNumber":  1,
        "isExplicit":   False,

        # Extra enrichment
        "release_year": meta.get("release_year"),
        "genre":        genre,
        "album_mbid":   meta.get("album_mbid", ""),
        "meta_source":  meta.get("source", "unknown"),
        "shazam_updated": shazam_updated,

        # Deduplication fields
        "title_lc":     _normalize(title),    # normalized lowercase shadow field
        "artist_lc":    _normalize(artist),   # normalized lowercase shadow field
        "video_id":     video_id,             # YouTube video ID (empty for CSV)
        # alias_keys allows dedup even when Shazam renames the track
        "alias_keys":   list(alias_keys),

        # Timestamps
        "addedAt":      firestore.SERVER_TIMESTAMP,
    }

    doc_ref.set(doc_data)
    log.info("Firestore track created: %s (video_id=%s, aliases=%s)", doc_ref.id, video_id or "none", list(alias_keys))
    return doc_ref.id


# ─────────────────────────────────────────────────────────────────────────────
#  Playlist linking
# ─────────────────────────────────────────────────────────────────────────────
def _link_to_playlist(playlist_id: str, track_id: str) -> None:
    db.collection(PLAYLISTS_COL).document(playlist_id).update({
        "trackIds": firestore.ArrayUnion([track_id])
    })
    log.info("Linked track %s → playlist %s", track_id, playlist_id)


# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────
def _identify_with_shazam(audio_url: str) -> dict | None:
    try:
        response = requests.get(audio_url, timeout=20)
        audio = AudioSegment.from_file(io.BytesIO(response.content))
        
        snippet = audio[60000 : 64000]
        snippet = snippet.set_frame_rate(44100).set_channels(1).set_sample_width(2)
        
        b64_audio = base64.b64encode(snippet.raw_data).decode('utf-8')

        for i, key in enumerate(SHAZAM_KEYS):
            log.info("Attempting Shazam identification with key index %d...", i)
            try:
                res = requests.post(
                    "https://shazam.p.rapidapi.com/songs/v2/detect",
                    data=b64_audio,
                    headers={
                        "content-type": "text/plain",
                        "x-rapidapi-key": key,
                        "x-rapidapi-host": "shazam.p.rapidapi.com"
                    },
                    timeout=15
                )
                
                # Check if quota exceeded (RapidAPI returns 429 or 403 for quota issues)
                if res.status_code in (429, 403):
                    log.warning("Shazam key index %d returned status %d. Quota likely exceeded. Trying next key...", i, res.status_code)
                    continue

                if res.status_code == 200:
                    data = res.json()
                    if 'track' in data:
                        return {
                            "title": data['track']['title'],
                            "artist": data['track']['subtitle'],
                            "cover": data['track'].get('images', {}).get('coverarthq')
                        }
                    else:
                        log.info("Shazam request succeeded with key index %d, but song was not recognized.", i)
                        return None
                else:
                    log.warning("Shazam API returned status code %d with key index %d: %s", res.status_code, i, res.text)
            except Exception as inner_e:
                log.warning("Attempt with Shazam key index %d failed: %s", i, inner_e)
                continue
    except Exception as e:
        log.warning("Shazam identification failed: %s", e)
    return None


def _sanitize_public_id(raw: str) -> str:
    """Turn 'artist/title' into a safe Cloudinary public_id."""
    return re.sub(r"[^a-zA-Z0-9/_-]", "_", raw)[:200]



# ─────────────────────────────────────────────────────────────────────────────
#  Deletion
# ─────────────────────────────────────────────────────────────────────────────
@app.route("/delete", methods=["POST"])
def delete_track():
    """
    Full cleanup:
    1. Delete from Cloudinary (audio + cover)
    2. Delete from Firestore 'tracks'
    3. Remove ID from ALL 'playlists'
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

        # 1. Cloudinary Cleanup
        if audio_pid:
            log.info("Deleting audio from Cloudinary: %s", audio_pid)
            cloudinary.uploader.destroy(audio_pid, resource_type="video")
        if cover_pid:
            log.info("Deleting cover from Cloudinary: %s", cover_pid)
            cloudinary.uploader.destroy(cover_pid)

        # 2. Playlist Cleanup (Admin query - cleans up EVERY playlist)
        log.info("Cleaning up references in all playlists for track: %s", track_id)
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

        # 3. Final Firestore Track deletion
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
#  YouTube Search endpoint  (used by the Flutter Search tab)
# ─────────────────────────────────────────────────────────────────────────────
@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "online"}), 200

@app.route("/search", methods=["GET"])
def search():
    q = (request.args.get("q") or "").strip()
    print(f"DEBUG: Search request received for query: '{q}'")
    if not q:
        print("DEBUG: Empty query, returning empty results.")
        return jsonify({"results": []})

    log.info("YouTube search: %s", q)

    ydl_opts = _get_ydl_opts({
        "quiet":        True,
        "extract_flat": True,
        "no_warnings":  True,
        "skip_download": True,
    })

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            print(f"DEBUG: Extracting info for 'ytsearch10:{q}'")
            info = ydl.extract_info(f"ytsearch10:{q}", download=False)

        entries = info.get("entries") or []
        print(f"DEBUG: Found {len(entries)} entries in info.")
        results = []
        for e in entries:
            if e is None: continue
            vid = e.get("id") or ""
            if not vid:
                continue
            results.append({
                "video_id":      vid,
                "title":         e.get("title")    or "",
                "artist":        e.get("uploader") or e.get("channel") or "",
                "thumbnail_url": (
                    e.get("thumbnail")
                    or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
                ),
                "duration_sec":  int(e.get("duration") or 0),
            })

        print(f"DEBUG: Returning {len(results)} sanitized results.")
        log.info("Search returned %d results for '%s'", len(results), q)
        return jsonify({"results": results})

    except Exception as exc:
        print(f"DEBUG: Search Exception: {exc}")
        log.exception("Search failed: %s", exc)
        return jsonify({"error": str(exc), "results": []}), 500


# ─────────────────────────────────────────────────────────────────────────────
#  YouTube Preview URL endpoint (gets direct streaming URL)
# ─────────────────────────────────────────────────────────────────────────────
@app.route("/preview", methods=["GET"])
def preview():
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


# ─────────────────────────────────────────────────────────────────────────────
#  Entry point (local dev)
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
