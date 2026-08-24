import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase
cred = credentials.Certificate("firebase-key.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

def clean_tracks():
    print("Connecting to 'tracks' collection in Firestore...")
    tracks_ref = db.collection('tracks')
    docs = list(tracks_ref.stream())
    
    if not docs:
        print("No documents found in 'tracks' collection.")
        return
        
    print(f"Found {len(docs)} tracks. Checking for mood details...")
    updated_count = 0
    
    for doc in docs:
        d = doc.to_dict()
        updates = {}
        
        # Check and delete mood-related fields
        for field in ['mood', 'energyLevel', 'vibeDesc', 'valence', 'sitbackReady', 'lastAnalyzed']:
            if field in d:
                updates[field] = firestore.DELETE_FIELD
                
        if updates:
            doc.reference.update(updates)
            title = d.get('title', 'Unknown Title')
            artist = d.get('artist', 'Unknown Artist')
            print(f"Updated track '{title}' by '{artist}' (ID: {doc.id}): Removed fields {list(updates.keys())}")
            updated_count += 1
            
    print(f"\nMigration complete. Cleaned {updated_count} track documents.")

if __name__ == "__main__":
    clean_tracks()
