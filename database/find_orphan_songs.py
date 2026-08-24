import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase
cred = credentials.Certificate("firebase-key.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

def find_orphan_songs():
    print("Fetching playlists...")
    playlists_ref = db.collection('playlists')
    playlists = list(playlists_ref.stream())
    
    referenced_ids = set()
    for pl in playlists:
        d = pl.to_dict()
        for field in ['trackIds', 'track_ids', 'songIds']:
            ids = d.get(field, [])
            if isinstance(ids, list):
                for tid in ids:
                    if isinstance(tid, str):
                        referenced_ids.add(tid)
                        
    print(f"Gathered {len(referenced_ids)} unique track references from {len(playlists)} playlists.")
    
    print("Fetching all tracks...")
    tracks_ref = db.collection('tracks')
    tracks = list(tracks_ref.stream())
    
    orphans = []
    for doc in tracks:
        d = doc.to_dict()
        tid = doc.id
        if tid not in referenced_ids:
            title = d.get('title', 'Unknown Title')
            artist = d.get('artist', 'Unknown Artist')
            orphans.append((tid, title, artist))
            
    print(f"\nFound {len(orphans)} songs in 'tracks' collection that are not referenced in any playlist:\n")
    for i, (tid, title, artist) in enumerate(orphans, 1):
        print(f"{i}. '{title}' by '{artist}' (ID: {tid})")

if __name__ == "__main__":
    find_orphan_songs()
