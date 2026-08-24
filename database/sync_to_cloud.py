import os
import cloudinary
import cloudinary.uploader
import firebase_admin
from firebase_admin import credentials, firestore

# 1. Cloudinary Credentials
cloudinary.config(
  cloud_name = os.environ.get("CLOUDINARY_CLOUD_NAME", "YOUR_CLOUDINARY_CLOUD_NAME"),
  api_key = os.environ.get("CLOUDINARY_API_KEY", "YOUR_CLOUDINARY_API_KEY"),
  api_secret = os.environ.get("CLOUDINARY_API_SECRET", "YOUR_CLOUDINARY_API_SECRET"),
  secure = True
)


# 2. Firebase Initialization
cred = credentials.Certificate("firebase-key.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

def start_sync():           
    # Path to your music folder
    music_folder = "music_to_upload"
    
    if not os.path.exists(music_folder):
        print(f"Error: {music_folder} directory not found!")
        return

    print("--- Starting Sync: Local -> Cloudinary -> Firestore ---")

    for filename in os.listdir(music_folder):
        # Filter for audio files
        if filename.lower().endswith(('.mp3', '.wav', '.m4a')):
            file_path = os.path.join(music_folder, filename)
            
            # Use filename (minus extension) as the track title
            track_title = os.path.splitext(filename)[0]

            print(f"Uploading: {track_title}...")

            try:
                # Upload to Cloudinary using your new 'ml_spotify' preset
                upload_result = cloudinary.uploader.upload(
                    file_path, 
                    resource_type = "video", # Audio files are treated as 'video' in Cloudinary
                    upload_preset = "ml_spotify",
                    folder = "my_music_app/all_songs"
                )

                # Get the secure streaming URL
                stream_url = upload_result.get("secure_url")

                # Create document in Firestore 'tracks' collection
                doc_ref = db.collection("tracks").document()
                doc_ref.set({
                    "id": doc_ref.id,
                    "title": track_title,
                    "artist": "Unknown Artist", # We'll let users edit this later
                    "url": stream_url,
                    "timestamp": firestore.SERVER_TIMESTAMP
                })

                print(f"✅ Success: {track_title}")

            except Exception as e:
                print(f"❌ Failed {filename}: {e}")

    print("--- Sync Complete! ---")

if __name__ == "__main__":
    start_sync()