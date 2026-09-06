import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase
cred = credentials.Certificate("firebase-key.json")
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)
db = firestore.client()

FIELDS_TO_REMOVE = [
    'mood',
    'energyLevel',
    'vibeDesc',
    'sitbackReady',
    'lastAnalyzed',
    'subGenres',
    'genre',
    'shazam_updated',
    'metadata_status',
    'album_mbid',
    'valence',
]

def clean_unnecessary_tags():
    print("Connecting to Firestore 'tracks' collection...")
    tracks_ref = db.collection('tracks')
    docs = list(tracks_ref.stream())
    
    print(f"Loaded {len(docs)} track documents. Cleaning requested fields: {FIELDS_TO_REMOVE}\n")
    
    batch = db.batch()
    batch_count = 0
    updated_tracks = 0
    field_counts = {f: 0 for f in FIELDS_TO_REMOVE}

    for doc in docs:
        d = doc.to_dict()
        updates = {}
        
        for field in FIELDS_TO_REMOVE:
            if field in d:
                updates[field] = firestore.DELETE_FIELD
                field_counts[field] += 1
                
        if updates:
            batch.update(doc.reference, updates)
            batch_count += 1
            updated_tracks += 1
            
            # Commit every 400 updates (Firestore max is 500 per batch)
            if batch_count >= 400:
                batch.commit()
                print(f"  [Batch] Committed {batch_count} updates...")
                batch = db.batch()
                batch_count = 0

    if batch_count > 0:
        batch.commit()
        print(f"  [Batch] Committed final {batch_count} updates...")

    print("\n--- CLEANUP COMPLETE ---")
    print(f"Total tracks modified: {updated_tracks}/{len(docs)}")
    print("\nFields removed summary:")
    for field, count in field_counts.items():
        print(f"  - {field:<18}: removed from {count} tracks")

if __name__ == "__main__":
    clean_unnecessary_tags()
