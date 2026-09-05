import yt_dlp
import os
import sys
import time

# ─────────────────────────────────────────────
#  CONFIGURATION — edit these as needed
# ─────────────────────────────────────────────

PLAYLIST_FILE = "playlist.txt"   # your .txt or .csv file (one song per line)
OUTPUT_FOLDER = "downloaded_songs"
AUDIO_QUALITY = "192"            # change to "128" if you want 128kbps
SKIP_ALREADY_DOWNLOADED = True   # won't re-download songs already in the folder

# ─────────────────────────────────────────────

def load_songs(filepath):
    """Read song names from a .txt or .csv file (one per line)."""
    songs = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            # skip empty lines and CSV headers like "Song,Artist"
            if not line or line.lower().startswith("song"):
                continue
            # if CSV with comma, take only the first column (song name)
            # you can customize this if your CSV has a different format
            parts = line.split(",")
            song_name = parts[0].strip().strip('"')
            if song_name:
                songs.append(song_name)
    return songs


def already_downloaded(song_name, folder):
    """Check if a file for this song already exists in the output folder."""
    if not os.path.exists(folder):
        return False
    # normalize the song name the same way yt-dlp does (rough check)
    for fname in os.listdir(folder):
        if fname.endswith(".m4a"):
            return False  # simple: just check by yt-dlp archive file
    return False


def download_song(song_name, output_folder, quality, archive_file):
    """Search YouTube for the song and download it as .m4a."""
    search_query = f"ytsearch1:{song_name} audio"

    ydl_opts = {
        # search YouTube and grab the first result
        "default_search": "ytsearch",
        "format": "bestaudio[ext=m4a]/bestaudio/best",
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "m4a",
                "preferredquality": quality,
            }
        ],
        "outtmpl": os.path.join(output_folder, "%(title)s.%(ext)s"),
        "quiet": False,
        "no_warnings": False,
        "ignoreerrors": True,           # skip a song if it fails, don't stop
        "download_archive": archive_file,  # tracks already-downloaded songs
        "noplaylist": True,
        "socket_timeout": 30,
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([search_query])


def main():
    # check playlist file exists
    if not os.path.exists(PLAYLIST_FILE):
        print(f"\n❌ Playlist file '{PLAYLIST_FILE}' not found.")
        print(f"   Make sure '{PLAYLIST_FILE}' is in the same folder as this script.\n")
        sys.exit(1)

    # create output folder
    os.makedirs(OUTPUT_FOLDER, exist_ok=True)

    # archive file to track downloads (so re-runs skip already downloaded songs)
    archive_file = os.path.join(OUTPUT_FOLDER, ".download_archive.txt")

    # load songs
    songs = load_songs(PLAYLIST_FILE)
    total = len(songs)

    if total == 0:
        print("❌ No songs found in the playlist file. Check the file format.")
        sys.exit(1)

    print(f"\n🎵 Found {total} songs in '{PLAYLIST_FILE}'")
    print(f"📁 Saving to: {os.path.abspath(OUTPUT_FOLDER)}")
    print(f"🎚️  Quality: {AUDIO_QUALITY}kbps M4A (AAC)")
    print("─" * 50)

    failed = []

    for i, song in enumerate(songs, 1):
        print(f"\n[{i}/{total}] Searching & downloading: {song}")
        try:
            download_song(song, OUTPUT_FOLDER, AUDIO_QUALITY, archive_file)
        except Exception as e:
            print(f"   ⚠️  Failed: {e}")
            failed.append(song)
        # small delay to be polite to YouTube's servers
        time.sleep(1)

    # summary
    print("\n" + "═" * 50)
    print(f"✅ Done! Downloaded to: {os.path.abspath(OUTPUT_FOLDER)}")
    if failed:
        print(f"\n⚠️  {len(failed)} song(s) failed to download:")
        for s in failed:
            print(f"   - {s}")
        # save failed songs to a file for easy retry
        failed_file = "failed_songs.txt"
        with open(failed_file, "w", encoding="utf-8") as f:
            f.write("\n".join(failed))
        print(f"\n   Failed songs saved to '{failed_file}' — you can retry them.")
    print("═" * 50)


if __name__ == "__main__":
    main()
