"""
SpotiFLAC Pure Ingestion Cloud Function
========================================
Endpoint: POST /ingest
Body:
    {
        "title":       "Blinding Lights",
        "artist":      "The Weeknd",
        "spotify_url": "https://open.spotify.com/track/...", # optional
        "playlist_id": "abc123"                              # optional
    }

Pure SpotiFLAC Architecture:
    1. Spotify Metadata: Resolved directly via official Spotify API (SpotifyMetadataClient).
    2. Audio Download: Lossless studio FLAC via SpotiFLAC (Tidal / Qobuz lossless provider).
    3. In-flight Transcoding: FLAC -> 256 kbps AAC M4A via ffmpeg (+faststart).
    4. Cloud Storage: Optimized M4A + 640x640 album artwork stored on Cloudinary.
    5. Database: Track record and playlist associations saved in Firestore.
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
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

import requests
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
log = logging.getLogger("spotiflac_backend")

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

TRACKS_COL    = "tracks"
PLAYLISTS_COL = "playlists"


# ─────────────────────────────────────────────────────────────────────────────
#  Audio Transcoder (Lossless FLAC -> 256 kbps AAC M4A)
# ─────────────────────────────────────────────────────────────────────────────
def _transcode_audio_to_m4a(input_path: str, output_path: str, bitrate: str = "256k") -> bool:
    """
    Transcode lossless studio audio (FLAC/WAV) to optimized 256 kbps AAC M4A.
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
    Search Spotify's official catalog using SpotifyMetadataClient.
    Returns (track_metadata_dict, spotify_url) or (None, None).
    """
    if not SPOTIFLAC_AVAILABLE:
        log.error("SpotiFLAC module is not available in Python environment.")
        return None, None

    sm = SpotifyMetadataClient()

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

    # Search Spotify catalog
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
#  SpotiFLAC Lossless Audio Downloader
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
            log.error("SpotiFLAC could not find or download audio from lossless providers.")
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
        log.error("SpotiFLAC download execution encountered an error: %s", e)

    return None, 0


# ─────────────────────────────────────────────────────────────────────────────
#  Cloudinary Upload Helpers
# ─────────────────────────────────────────────────────────────────────────────
def _sanitize_public_id(raw: str) -> str:
    """Turn 'artist/title' into a safe Cloudinary public_id."""
    return re.sub(r"[^a-zA-Z0-9/_-]", "_", raw)[:200]


def _upload_square_cover(image_url: str | None, title: str, artist: str) -> tuple[str, str]:
    """Upload cover artwork to Cloudinary with square crop."""
    if not image_url:
        return "", ""

    public_id = _sanitize_public_id(f"covers/{artist}/{title}")
    log.info("Uploading album cover to Cloudinary: %s", public_id)

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
#  Deduplication
# ─────────────────────────────────────────────────────────────────────────────
def _normalize(s: str) -> str:
    """Lowercase + collapse whitespace + strip punctuation for fuzzy matching."""
    s = s.lower().strip()
    s = re.sub(r"[^\w\s]", "", s)
    s = re.sub(r"\s+", " ", s)
    return s


def _find_existing_track(title: str, artist: str, spotify_id: str = "") -> str | None:
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

    title_lc  = _normalize(title)
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
) -> str:
    """Create a track document in Firestore."""
    if not db:
        log.warning("Firestore not initialized. Returning dummy doc id.")
        return f"track_{int(time.time())}"

    title  = meta.get("title", "Unknown Title")
    artist = meta.get("artist", "Unknown Artist")
    doc_ref = db.collection(TRACKS_COL).document()

    alias_keys = [f"{_normalize(title)}||{_normalize(artist)}"]

    doc_data = {
        # Core fields
        "title":           title,
        "artist":          artist,
        "album":           meta.get("album", ""),
        "secure_url":      secure_url,
        "audio_public_id": audio_public_id,
        "imageUrl":        cover_url,
        "cover_public_id": cover_public_id,
        "duration_ms":     meta.get("duration_ms", 0),
        "trackNumber":     meta.get("track_number", 1),
        "isExplicit":      meta.get("is_explicit", False),

        # SpotiFLAC Metadata fields
        "spotify_id":      meta.get("spotify_id", ""),
        "spotify_url":     meta.get("spotify_url", ""),
        "meta_source":     "spotiflac",
        "audio_quality":   "256k_aac_studio_master",

        # Deduplication fields
        "title_lc":        _normalize(title),
        "artist_lc":       _normalize(artist),
        "alias_keys":      alias_keys,

        # Timestamps
        "addedAt":         firestore.SERVER_TIMESTAMP,
    }

    doc_ref.set(doc_data)
    log.info("Firestore track created: %s (source=spotiflac)", doc_ref.id)
    return doc_ref.id


def _link_to_playlist(playlist_id: str, track_id: str) -> None:
    """Link track to a user playlist in Firestore."""
    if not db or not playlist_id:
        return
    db.collection(PLAYLISTS_COL).document(playlist_id).update({
        "trackIds": firestore.ArrayUnion([track_id])
    })
    log.info("Linked track %s → playlist %s", track_id, playlist_id)


# ─────────────────────────────────────────────────────────────────────────────
#  API Endpoints
# ─────────────────────────────────────────────────────────────────────────────
@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({
        "status": "online",
        "engine": "SpotiFLAC (Lossless Studio)",
        "spotiflac_available": SPOTIFLAC_AVAILABLE
    }), 200


@app.route("/search", methods=["GET"])
def search():
    """
    Search official Spotify catalog directly via SpotifyMetadataClient.
    """
    q = (request.args.get("q") or "").strip()
    if not q:
        return jsonify({"results": []})

    log.info("Spotify catalog search query: '%s'", q)

    if not SPOTIFLAC_AVAILABLE:
        return jsonify({"error": "SpotiFLAC module not loaded", "results": []}), 500

    try:
        sm = SpotifyMetadataClient()
        res = sm.search(q)
        tracks = res.get("tracks", []) if isinstance(res, dict) else []

        results = []
        for t in tracks:
            spotify_id = getattr(t, "id", "")
            duration_ms = getattr(t, "duration_ms", 0)
            cover_url = getattr(t, "cover_url", "") or ""
            external_url = getattr(t, "external_url", "") or f"https://open.spotify.com/track/{spotify_id}"

            results.append({
                "video_id":      spotify_id, # Compatibility with Flutter model
                "spotify_id":    spotify_id,
                "title":         getattr(t, "title", ""),
                "artist":        getattr(t, "artists", ""),
                "album":         getattr(t, "album", ""),
                "thumbnail_url": cover_url,
                "cover_url":     cover_url,
                "duration_sec":  int(duration_ms / 1000) if duration_ms else 0,
                "spotify_url":   external_url
            })

        log.info("Spotify search returned %d results for '%s'", len(results), q)
        return jsonify({"results": results})

    except Exception as exc:
        log.exception("Spotify catalog search failed: %s", exc)
        return jsonify({"error": str(exc), "results": []}), 500


@app.route("/ingest", methods=["POST"])
def ingest():
    """
    Pure SpotiFLAC Ingestion Pipeline:
    1. Deduplicate check in Firestore
    2. Resolve Spotify official track metadata & URL
    3. Download lossless studio audio via SpotiFLAC
    4. Transcode FLAC -> 256 kbps AAC M4A
    5. Upload audio & album artwork to Cloudinary
    6. Save to Firestore tracks collection
    7. Link to playlist if specified
    """
    data = request.get_json(force=True)
    title        = (data.get("title")       or "").strip()
    artist       = (data.get("artist")      or "").strip()
    playlist_id  = (data.get("playlist_id") or "").strip()
    spotify_url  = (data.get("spotify_url") or "").strip()
    bypass_dedup = data.get("bypass_dedup") == True

    if not title and not spotify_url:
        return jsonify({"error": "title or spotify_url is required"}), 400

    log.info("Ingesting with SpotiFLAC: '%s' by '%s' (spotify_url=%s, bypass_dedup=%s)", title, artist, spotify_url or "none", bypass_dedup)

    try:
        # 1. Resolve Spotify Metadata
        meta, resolved_spotify_url = _resolve_spotify_track(title, artist, spotify_url=spotify_url)
        if not meta or not resolved_spotify_url:
            return jsonify({
                "error": f"Song '{title} - {artist}' was not found in the Spotify catalog. SpotiFLAC requires a valid Spotify track."
            }), 404

        title = meta["title"]
        artist = meta["artist"]
        spotify_id = meta.get("spotify_id", "")

        # 2. Check Deduplication
        if not bypass_dedup:
            existing_id = _find_existing_track(title, artist, spotify_id=spotify_id)
            if existing_id:
                log.info("Duplicate found: %s — skipping download.", existing_id)
                if playlist_id:
                    _link_to_playlist(playlist_id, existing_id)
                return jsonify({
                    "status":   "duplicate",
                    "track_id": existing_id,
                    "message":  f"Song already exists (id={existing_id}). Linked to playlist."
                })

        # 3. SpotiFLAC Lossless Download & Transcoding
        with tempfile.TemporaryDirectory() as tmpdir:
            m4a_path, duration_ms = _download_via_spotiflac(resolved_spotify_url, tmpdir)
            if not m4a_path or not os.path.exists(m4a_path):
                return jsonify({
                    "error": f"SpotiFLAC could not find or download lossless audio for '{title} by {artist}' from streaming providers (Tidal/Qobuz)."
                }), 404

            if duration_ms:
                meta["duration_ms"] = duration_ms

            # 4. Upload Audio to Cloudinary
            audio_pid = _sanitize_public_id(f"audio/{artist}/{title}")
            log.info("Uploading audio to Cloudinary: %s (%d KB)", audio_pid, os.path.getsize(m4a_path) // 1024)
            audio_res = cloudinary.uploader.upload(
                m4a_path,
                resource_type="video",
                public_id=audio_pid,
                overwrite=True,
                format="m4a",
            )
            audio_url = audio_res["secure_url"]

        # 5. Upload Album Cover Artwork to Cloudinary
        cover_url, cover_pid = _upload_square_cover(meta.get("cover_url"), title, artist)

        # 6. Save Record in Firestore
        track_id = _create_firestore_track(
            meta=meta,
            secure_url=audio_url,
            audio_public_id=audio_pid,
            cover_url=cover_url,
            cover_public_id=cover_pid,
        )

        # 7. Link to Playlist
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
        log.exception("Pure SpotiFLAC Ingestion failed: %s", exc)
        return jsonify({"error": str(exc)}), 500


@app.route("/delete", methods=["POST"])
def delete_track():
    """
    Delete audio and artwork from Cloudinary, remove from all playlists, and delete Firestore record.
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


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
