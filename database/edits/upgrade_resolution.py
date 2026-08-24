import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firestore
if not firebase_admin._apps:
    cred = credentials.Certificate("firebase-key.json")
    firebase_admin.initialize_app(cred)
db = firestore.client()

def upgrade_covers_to_640():
    tracks_ref = db.collection('tracks')
    print("📡 Fetching library to upgrade to Spotify-standard 640x640...")
    docs = tracks_ref.stream()
    
    count = 0
    for doc in docs:
        data = doc.to_dict()
        img_url = data.get('image_url', '')
        
        # Check if it's an Apple/Shazam CDN link that we can resize
        if img_url and "mzstatic.com" in img_url:
            # Check if it currently has a size marker like /400x400bb.jpg or /100x100bb.jpg
            # We split at the last slash to swap the dimensions safely
            if "/" in img_url:
                base_url, current_size = img_url.rsplit('/', 1)
                
                # If it's already 640x640, we don't need to touch it
                if current_size == "640x640bb.jpg":
                    continue
                    
                # Build the new 640x640 URL string
                new_url = f"{base_url}/640x640bb.jpg"
                
                doc.reference.update({
                    'image_url': new_url
                })
                count += 1
                print(f"   ⚡ Upgraded [{count}]: {data.get('title', 'Unknown')[:30]} -> 640x640")

    print(f"\n✨ Clean sweep complete! Upgraded {count} track covers to production standard.")

upgrade_covers_to_640()