import base64, requests, io, firebase_admin
from pydub import AudioSegment
from firebase_admin import credentials, firestore
import time

# --- 1. Setup ---
if not firebase_admin._apps:
    cred = credentials.Certificate("firebase-key.json")
    firebase_admin.initialize_app(cred)
db = firestore.client()

import os

SHAZAM_KEY = os.environ.get("SHAZAM_KEY", "YOUR_SHAZAM_API_KEY")


def identify_track(audio_url):
    try:
        # Standard 20s timeout for regional downloads
        response = requests.get(audio_url, timeout=20)
        audio = AudioSegment.from_file(io.BytesIO(response.content))
        
        # Slicing at 60s to capture the core melody/vocals
        snippet = audio[60000 : 64000]
        snippet = snippet.set_frame_rate(44100).set_channels(1).set_sample_width(2)
        
        b64_audio = base64.b64encode(snippet.raw_data).decode('utf-8')

        res = requests.post(
            "https://shazam.p.rapidapi.com/songs/v2/detect",
            data=b64_audio,
            headers={
                "content-type": "text/plain",
                "x-rapidapi-key": SHAZAM_KEY,
                "x-rapidapi-host": "shazam.p.rapidapi.com"
            }
        )
        if res.status_code == 200:
            data = res.json()
            if 'track' in data:
                return {
                    "title": data['track']['title'],
                    "artist": data['track']['subtitle'],
                    "cover": data['track'].get('images', {}).get('coverarthq')
                }
    except Exception as e:
        print(f"   [!] System Error: {e}")
    return None

# --- 2. Full Sweep Logic ---
tracks_ref = db.collection('tracks')
all_tracks = list(tracks_ref.stream())

print(f"📡 Scanning {len(all_tracks)} total documents...")

to_fix = []
for doc in all_tracks:
    data = doc.to_dict()
    
    # Criteria: Empty fields OR flag is not True
    is_missing_artist = data.get('artist') in ["", "Unknown Artist", "unknown artist", "Unidentified", None]
    is_missing_title = data.get('title') in ["", "Unknown", "Unknown Title", None]
    is_missing_cover = data.get('image_url') in ["", "placeholder.png", None]
    is_flag_false = data.get('shazam_updated') is not True
    
    if (is_missing_artist or is_missing_title or is_missing_cover or is_flag_false) and data.get('url'):
        to_fix.append(doc)

total_to_fix = len(to_fix)
print(f"🚀 Found {total_to_fix} tracks needing update. Starting full run...")

processed_count = 0
for doc in to_fix:
    processed_count += 1
    track_data = doc.to_dict()
    print(f"🔄 [{processed_count}/{total_to_fix}] Analyzing: {track_data.get('title', 'No Title')[:40]}...")
    
    result = identify_track(track_data['url'])
    
    if result:
        doc.reference.update({
            'title': result['title'],
            'artist': result['artist'],
            'image_url': result['cover'],
            'shazam_updated': True
        })
        print(f"   ✅ Success: {result['title']}")
    else:
        # Mark as updated so we don't scan it again, but note it was not found
        doc.reference.update({'shazam_updated': True, 'metadata_status': 'not_found'})
        print("   ❌ Shazam could not identify.")
    
    # Sleep to respect RapidAPI rate limits
    time.sleep(0.5)

print(f"\n✨ Clean-up complete! {processed_count} tracks were processed.")