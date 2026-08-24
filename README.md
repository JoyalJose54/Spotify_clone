# 🎵 Spotify Clone — Flutter + Firebase + Cloudinary

A pixel-perfect Spotify clone with **real audio streaming** from Cloudinary,
**live Firestore data**, and full just_audio playback.

> **⭐ Portfolio Project** — Built with Flutter (Android/iOS), Firebase (Auth + Firestore), Cloudinary (audio CDN), and a Python Flask ingestion backend.

---

## ⚡ Quick Start — Configuration

> **Credentials are not included in this repo.** Copy the example files below and fill in your own keys before running.

### 1. Firebase (Android)
```bash
cp google-services.json.example android/app/google-services.json
# Then fill in your real Firebase project values
```

### 2. Firebase Admin SDK (Python backend)
```bash
cp database/firebase-key.json.example database/firebase-key.json
# Paste your Firebase service account JSON content
```

### 3. Python backend environment
```bash
cp cloud_functions/.env.example cloud_functions/.env
# Fill in: CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET, SHAZAM_KEYS
```

### 4. YouTube cookies (optional, for age-restricted content)
```bash
cp assets/cookies/yt_cookies.txt.example assets/cookies/yt_cookies.txt
# Export cookies from your browser using a cookies.txt extension
```

### 5. Install & run
```bash
flutter pub get
flutter run
```

### 6. Run the Python ingestion backend
```bash
cd cloud_functions
pip install -r requirements.txt
python main.py
```

---

## Architecture at a glance

```
Cloudinary CDN          Firestore                Flutter
─────────────           ─────────                ──────────────────────────────
audio.m4a  ──secure_url──▶ tracks/{id}  ──stream──▶ PlayerProvider (just_audio)
cover.jpg  ──imageUrl────▶             ──stream──▶ LibraryScreen (StreamBuilder)
                          playlists/{id}──stream──▶ HomeScreen  (StreamBuilder)
                          users/{uid}   ──stream──▶ LikedSongs  (StreamBuilder)
```

### How it works
1. **Registry (Firestore `tracks`)** – each document has `title`, `artist`,
   `secure_url` (Cloudinary), `imageUrl`, etc.  
2. **Streaming (Cloudinary → just_audio)** – the app passes `secure_url`
   directly to `AudioPlayer.setUrl()`. Cloudinary streams in chunks; nothing
   is downloaded to the device.  
3. **Live UI (StreamBuilder)** – every screen subscribes to Firestore snapshots.
   Add a song via your Python script → Library screen updates instantly.  
4. **Playlists** – a `playlists` document stores `trackIds: [...]`. The app
   resolves those IDs against the loaded tracks map. No files are copied.

---

## 1 · Firebase setup

### 1-a Create project
1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. **Add project** → name it `spotify-clone`
3. Enable **Google Analytics** (optional)

### 1-b Register apps
| Platform | Identifier |
|----------|-----------|
| Android  | `com.example.spotify_clone` |
| iOS      | `com.example.spotifyClone`  |

Download:
- `google-services.json` → `android/app/`
- `GoogleService-Info.plist` → `ios/Runner/`

Then run:
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```
This generates `lib/firebase_options.dart` automatically.

### 1-c Enable services
In Firebase Console:
- **Authentication** → Sign-in method → **Email/Password** → Enable
- **Firestore Database** → Create in **production mode**
- **Storage** → Get started

### 1-d Firestore security rules
```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Public read for music catalog
    match /tracks/{doc}    { allow read: if true; allow write: if false; }
    match /albums/{doc}    { allow read: if true; allow write: if false; }
    match /artists/{doc}   { allow read: if true; allow write: if false; }
    match /playlists/{doc} { allow read: if true;
                             allow write: if request.auth != null; }

    // Per-user private data
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

---

## 2 · Cloudinary setup

1. Sign up at [cloudinary.com](https://cloudinary.com) (free tier = 25 GB)
2. Create an **Upload Preset** (unsigned, for your Python uploader)
3. Upload audio files → copy the `secure_url`
4. Upload cover images → copy the `secure_url`

---

## 3 · Firestore `tracks` collection schema

Each document in `/tracks/{auto-id}`:

```json
{
  "title"      : "Love Me Do",
  "artist"     : "The Beatles",
  "album"      : "Please Please Me",
  "albumId"    : "alb_please_please_me",
  "artistId"   : "artist_beatles",
  "secure_url" : "https://res.cloudinary.com/YOUR_CLOUD/video/upload/v1234/songs/love-me-do.m4a",
  "imageUrl"   : "https://res.cloudinary.com/YOUR_CLOUD/image/upload/v1234/covers/please-please-me.jpg",
  "duration_ms": 142000,
  "trackNumber": 1,
  "isExplicit" : false
}
```

> **Field aliases the app accepts** (so any Python uploader works):
> - Audio: `secure_url` · `audioUrl` · `audio_url` · `url`
> - Image: `imageUrl` · `thumbnail_url` · `thumbnail` · `coverUrl`
> - Duration: `duration_ms` (int ms) · `durationMs` · `duration` (float seconds)

---

## 4 · Firestore `playlists` collection schema

```json
{
  "name"        : "Chill Vibes",
  "description" : "Easy listening for any time",
  "imageUrl"    : "https://res.cloudinary.com/.../covers/chill.jpg",
  "owner"       : "Spotify",
  "trackIds"    : ["track_id_1", "track_id_2", "track_id_3"],
  "likes"       : 12400,
  "isSpotifyOwned": true
}
```

No audio files are touched. The app resolves `trackIds` against the in-memory
`tracks` map at runtime.

---

## 5 · Install & run

```bash
# 1. Clone & install
git clone <your-repo>
cd spotify_clone
flutter pub get

# 2. Add Firebase config files (see section 1-b above)
# android/app/google-services.json
# ios/Runner/GoogleService-Info.plist

# 3. Run
flutter run
```

### Android minimum SDK
The `android/app/build.gradle` already sets `minSdk = 21` (Android 5.0) which
is required by `just_audio`.

### iOS background audio
`ios/Runner/Info.plist` already contains the `UIBackgroundModes → audio` key
so Cloudinary streaming continues when the app is backgrounded.

---

## 6 · Project structure

```
lib/
├── main.dart                         ← Firebase init + AudioSession + providers
├── theme/app_theme.dart              ← Spotify colour tokens + typography
├── models/models.dart                ← Song · Playlist · Artist · LibraryItem
│                                        Song.fromFirestore() handles all field aliases
├── providers/app_provider.dart       ← PlayerProvider (just_audio wrapper)
│                                        AuthProvider · NavigationProvider
├── services/firebase_service.dart    ← All Firestore stream/fetch/write methods
└── screens/
    ├── splash_screen.dart            ← Floating animated album arts
    ├── main_screen.dart              ← Shell + MiniPlayer (real just_audio streams)
    ├── auth/auth_screens.dart        ← Email → Password → Name → Choose Artists
    ├── home/home_screen.dart         ← StreamBuilder: recently played · playlists
    ├── search/search_screen.dart     ← Live Firestore search · genre grid
    ├── library/
    │   └── library_screen.dart       ← StreamBuilder on `tracks` collection
    │                                    AllTracksPlaylistScreen (auto-updates)
    ├── album/album_screen.dart       ← Dynamic palette · Firestore track list
    └── player/now_playing_screen.dart← just_audio streams · seek · skip · like
```

---

## 7 · Key data flows

### Play a song
```
User taps track
  → PlayerProvider.playSong(song)
  → AudioPlayer.setUrl(song.streamUrl)   ← Cloudinary secure_url
  → Cloudinary streams chunks to device
  → NowPlayingScreen subscribes to positionDataStream
  → Slider updates in real time
```

### Library auto-update
```
Python script adds doc to `tracks` collection
  → Firestore snapshot fires
  → LibraryScreen StreamBuilder rebuilds
  → User sees new song immediately (no refresh)
```

### Liked songs
```
User taps ♥ in NowPlayingScreen
  → FirebaseService.likeSong(trackId)
  → Writes to users/{uid}.likedSongs[]
  → streamLikedSongs() snapshot fires
  → Liked Songs row updates count
```

---

## 8 · Adding songs (Python script integration)

Your upload script should write to Firestore like this:

```python
import cloudinary.uploader
from google.cloud import firestore

# 1. Upload to Cloudinary
result = cloudinary.uploader.upload(
    "path/to/song.m4a",
    resource_type="video",
    folder="songs",
)

# 2. Write to Firestore `tracks`
db = firestore.Client()
db.collection("tracks").add({
    "title"      : "Song Title",
    "artist"     : "Artist Name",
    "album"      : "Album Name",
    "secure_url" : result["secure_url"],   # ← Cloudinary URL
    "imageUrl"   : cover_url,
    "duration_ms": int(result.get("duration", 0) * 1000),
    "trackNumber": 1,
    "isExplicit" : False,
})
# Flutter library screen updates automatically ✅
```

---

## 9 · Dependencies

| Package | Purpose |
|---------|---------|
| `just_audio` | Cloudinary URL → audio streaming |
| `audio_session` | Handle phone calls, BT headsets, interruptions |
| `rxdart` | `combineLatest3` for position + buffer + duration stream |
| `firebase_core` | Firebase initialisation |
| `firebase_auth` | Email/password sign-up & login |
| `cloud_firestore` | Live `tracks` + `playlists` + `users` streams |
| `firebase_storage` | (Optional) direct file access |
| `palette_generator` | Dynamic background colour from album art |
| `flutter_animate` | Declarative entry/stagger animations |
| `cached_network_image` | Efficient Cloudinary image loading |
| `google_fonts` | Nunito typeface |
| `provider` | State management |

---

## 10 · Troubleshooting

| Problem | Fix |
|---------|-----|
| `MissingPluginException` on audio | Run `flutter clean && flutter pub get` |
| Songs not loading | Check `secure_url` field in Firestore doc; must be HTTPS |
| Library screen empty | Verify Firestore rules allow `read: if true` on `tracks` |
| Firebase `no-app` crash | Ensure `google-services.json` is in `android/app/` |
| iOS audio stops in background | `Info.plist` already has `UIBackgroundModes: audio` |
| Cloudinary 401 error | Set delivery type to **public** in Cloudinary asset settings |
