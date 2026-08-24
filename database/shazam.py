import base64, requests, io, firebase_admin
from pydub import AudioSegment
from firebase_admin import credentials, firestore
import time

# --- Setup ---
if not firebase_admin._apps:
    cred = credentials.Certificate("firebase-key.json")
    firebase_admin.initialize_app(cred)
db = firestore.client()

import os

SHAZAM_KEY = os.environ.get("SHAZAM_KEY", "YOUR_SHAZAM_API_KEY")


def identify_track(audio_url):
    try:
        response = requests.get(audio_url, timeout=25)
        audio = AudioSegment.from_file(io.BytesIO(response.content))
        
        # Test 60 seconds in
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
        print(f"   [!] Audio Processing Error: {e}")
    return None

def force_clean_remaining():
    tracks_ref = db.collection('tracks')
    print("📡 Loading tracks...")
    
    # We fetch all docs to check the flag locally
    all_docs = list(tracks_ref.stream())
    to_process = []

    for doc in all_docs:
        data = doc.to_dict()
        
        # SKIP LOGIC: 
        # 1. Skip if 'shazam_updated' is True
        # 2. Skip if the 'url' field is missing
        if data.get('shazam_updated') == True:
            continue
        
        if not data.get('url'):
            continue
            
        to_process.append(doc)

    print(f"📊 Total in Database: {len(all_docs)}")
    print(f"🚀 Songs left to fix: {len(to_process)}")

    count = 0
    for doc in to_process:
        count += 1
        data = doc.to_dict()
        print(f"🔄 [{count}/{len(to_process)}] Identifying: {data.get('title', 'Unknown')[:30]}...")

        result = identify_track(data['url'])
        
        if result:
            doc.reference.update({
                'title': result['title'],
                'artist': result['artist'],
                'image_url': result['cover'],
                'shazam_updated': True  # THE FLAG: prevents re-processing
            })
            print(f"   ✅ Fixed & Tagged: {result['title']}")
        else:
            # We still tag it as True so we don't keep wasting quota on 
            # songs Shazam simply doesn't know.
            doc.reference.update({
                'shazam_updated': True,
                'metadata_status': 'not_found' 
            })
            print("   ❌ No match (Tagged to skip in future)")
        
        time.sleep(0.5)

    print("\n✨ All remaining songs processed!")

force_clean_remaining()