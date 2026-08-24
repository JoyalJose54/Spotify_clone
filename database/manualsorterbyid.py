import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate("firebase-key.json")
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)
db = firestore.client()

# --- EDIT THIS SECTION ---
# Put the IDs you found in Step 1 into these lists
manual_sorting = {
    "Sangeeetham!!": [
        "oY4H6rk0N08k0teUbJIM",
        "rwb5VpuclTFJrAj7nhUG","v28zjQw39JQ0QUKnNkYt"
    ],
    "⚡️⚡️": [
        ""
    ],
    "🏋️‍♀️🏋️‍♀️": [
        "qoT7GvQktAtfuCydOm4a"
    ],
    "🫶🏻🫠": [
        "esM7ltvqxHttaN2xi6TL","oY4H6rk0N08k0teUbJIM","rQJtyBDHiyHaNhZOfRRT"
    ],
    "🥹🫶🏻": [
        # ...
    ]
}
# -------------------------

def move_songs():
    unclassified_ref = db.collection('playlists').document('Unclassified')
    unclassified_data = unclassified_ref.get().to_dict()
    all_unclassified = unclassified_data.get('track_ids', [])

    for playlist_name, ids_to_move in manual_sorting.items():
        if not ids_to_move: continue
        
        # 1. Add to Target Playlist
        playlist_ref = db.collection('playlists').document(playlist_name)
        playlist_ref.update({
            "track_ids": firestore.ArrayUnion(ids_to_move),
            "total_songs": firestore.Increment(len(ids_to_move))
        })
        
        # 2. Remove from Unclassified List
        unclassified_ref.update({
            "track_ids": firestore.ArrayRemove(ids_to_move),
            "total_songs": firestore.Increment(-len(ids_to_move))
        })
        
        print(f"✅ Moved {len(ids_to_move)} songs to {playlist_name}")

    # Final check: delete Unclassified if it's empty
    updated_unclassified = unclassified_ref.get().to_dict().get('track_ids', [])
    if not updated_unclassified:
        unclassified_ref.delete()
        print("✨ All songs sorted! Unclassified playlist removed.")

if __name__ == "__main__":
    move_songs()