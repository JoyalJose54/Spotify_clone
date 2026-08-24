import csv
import firebase_admin
from firebase_admin import credentials, firestore
from google.api_core.exceptions import NotFound

if not firebase_admin._apps:
    cred = credentials.Certificate("firebase-key.json")
    firebase_admin.initialize_app(cred)
db = firestore.client()

def import_tracks_from_csv():
    filename = "updated_tracks.csv"
    tracks_ref = db.collection('tracks')
    
    print(f"🚀 Reading edits from '{filename}'...")
    
    with open(filename, mode='r', encoding='utf-8') as file:
        reader = csv.DictReader(file)
        
        count = 0
        skipped = 0
        for row in reader:
            doc_id = row['id']
            
            try:
                # Update the exact document with your manual refinements
                tracks_ref.document(doc_id).update({
                    'title': row['title'],
                    'artist': row['artist'],
                    'image_url': row['image_url'],
                    'shazam_updated': True  # Keep locked so automated runs skip them
                })
                count += 1
                print(f"   ✏️ Updated [{count}]: {row['title']} by {row['artist']}")
            except NotFound:
                skipped += 1
                print(f"   ⚠️ Skipped: Document '{doc_id}' ({row['title']} by {row['artist']}) not found in Firestore.")

    print(f"\n✨ Complete! Successfully re-imported and corrected {count} tracks. (Skipped {skipped} missing documents)")

import_tracks_from_csv()