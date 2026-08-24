import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import os

cred = credentials.Certificate("firebase-key.json")
firebase_admin.initialize_app(cred)

db = firestore.client()

print("--- PLAYLIST ORDER ---")
settings = db.collection('globals').document('settings').get()
if settings.exists:
    order = settings.to_dict().get('playlistOrder', [])
    for idx, item in enumerate(order):
        print(f"{idx}: {repr(item)}")
else:
    print("No settings document found")

print("\n--- ACTUAL PLAYLIST NAMES ---")
playlists = db.collection('playlists').stream()
for pl in playlists:
    data = pl.to_dict()
    print(f"ID: {pl.id}, Name: {repr(data.get('name'))}")
