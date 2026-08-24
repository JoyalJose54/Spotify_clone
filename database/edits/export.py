import csv
import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firestore
if not firebase_admin._apps:
    cred = credentials.Certificate("firebase-key.json")
    firebase_admin.initialize_app(cred)
db = firestore.client()

def export_tracks_to_csv():
    tracks_ref = db.collection('tracks')
    docs = tracks_ref.stream()
    
    filename = "firestore_tracks.csv"
    
    with open(filename, mode='w', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        
        # Header layout matching your exact Firestore fields
        writer.writerow(['id', 'title', 'artist', 'image_url', 'url', 'shazam_updated'])
        
        count = 0
        for doc in docs:
            data = doc.to_dict()
            writer.writerow([
                doc.id,                               # Keep the document identifier safe
                data.get('title', ''),
                data.get('artist', ''),
                data.get('image_url', ''),
                data.get('url', ''),
                data.get('shazam_updated', False)
            ])
            count += 1
            
    print(f"✅ Successfully exported {count} tracks to '{filename}'!")

export_tracks_to_csv()