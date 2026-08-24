<div align="center">

<img src="assets/images/logo.webp" alt="Spotify Clone Logo" width="120" />

# 🎵 Spotify Clone

### A pixel-perfect music streaming app built with Flutter & Firebase

<br/>

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Cloudinary](https://img.shields.io/badge/Cloudinary-CDN-3448C5?style=for-the-badge&logo=cloudinary&logoColor=white)](https://cloudinary.com)
[![Python](https://img.shields.io/badge/Python-Flask-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://flask.palletsprojects.com)

[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey?style=for-the-badge&logo=android&logoColor=white)](https://flutter.dev)
[![PRs Welcome](https://img.shields.io/badge/PRs-Welcome-brightgreen?style=for-the-badge)](https://github.com/JoyalJose54/Spotify_clone/pulls)

<br/>

> Real audio streaming · Live Firestore database · AI-powered song identification

<br/>

[Features](#-features) • [Architecture](#-architecture) • [Quick Start](#-quick-start) • [Tech Stack](#-tech-stack) • [Screenshots](#-project-structure)

</div>

---

## ✨ Features

<table>
<tr>
<td width="50%">

### 🎧 Music Playback
- Full audio streaming via **Cloudinary CDN**
- Background playback with lock screen controls
- Seek, skip, shuffle & repeat
- Real-time progress bar with buffering indicator
- Mini player that persists across all screens

</td>
<td width="50%">

### 🔥 Live Data
- **Real-time Firestore** streams — no refresh needed
- Add a song via Python → app updates instantly
- Liked songs sync across devices
- Recently played history per user

</td>
</tr>
<tr>
<td width="50%">

### 🤖 Smart Ingestion Backend
- **yt-dlp** downloads audio from YouTube
- **Shazam API** fingerprints & corrects metadata
- **Smart deduplication** — fuzzy title matching + alias keys
- Auto-uploads to Cloudinary (audio + square cover art)

</td>
<td width="50%">

### 🎨 Polished UI
- Pixel-perfect Spotify-inspired design
- Dynamic **color palette** extracted from album art
- Animated splash screen with floating album arts
- Custom Spotify fonts & icon set

</td>
</tr>
</table>

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App                              │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐   │
│  │  HomeScreen │  │ SearchScreen│  │  NowPlayingScreen    │   │
│  │  (playlists)│  │ (YT + local)│  │  (just_audio stream) │   │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬───────────┘   │
│         │                │                     │               │
│  ┌──────▼────────────────▼─────────────────────▼───────────┐  │
│  │              Provider Layer (State Management)           │  │
│  │   PlayerProvider · AuthProvider · NavigationProvider    │  │
│  └──────────────────────────┬──────────────────────────────┘  │
└─────────────────────────────│───────────────────────────────────┘
                              │
           ┌──────────────────┼──────────────────┐
           │                  │                  │
    ┌──────▼──────┐   ┌───────▼──────┐   ┌──────▼──────┐
    │  Firestore  │   │  Cloudinary  │   │  Firebase   │
    │  (metadata) │   │  (audio CDN) │   │    Auth     │
    └─────────────┘   └──────────────┘   └─────────────┘
                              │
           ┌──────────────────┘
    ┌──────▼──────────────────────────────────────────┐
    │           Python Flask Backend                  │
    │  yt-dlp → Shazam ID → Cloudinary → Firestore   │
    └─────────────────────────────────────────────────┘
```

---

## ⚡ Quick Start

> **Credentials are not included in this repo.** Copy the example files below and fill in your own keys.

### Prerequisites

```bash
flutter --version   # Flutter 3.x+
python3 --version   # Python 3.10+
```

### 1️⃣ Clone the repository

```bash
git clone https://github.com/JoyalJose54/Spotify_clone.git
cd Spotify_clone
flutter pub get
```

### 2️⃣ Configure Firebase (Android)

```bash
# Copy the example and fill in your Firebase project values
cp google-services.json.example android/app/google-services.json
```

<details>
<summary>📋 How to get google-services.json</summary>

1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. Create a project → Add Android app (package: `com.example.spotify_clone`)
3. Download `google-services.json` and place it in `android/app/`
4. Enable **Authentication** (Email/Password), **Firestore**, and **Storage**

</details>

### 3️⃣ Configure Firebase Admin SDK (Python backend)

```bash
cp database/firebase-key.json.example database/firebase-key.json
# Paste your Firebase service account JSON content
```

### 4️⃣ Configure the Python backend

```bash
cp cloud_functions/.env.example cloud_functions/.env
```

Then edit `cloud_functions/.env`:

```env
CLOUDINARY_CLOUD_NAME=your_cloud_name
CLOUDINARY_API_KEY=your_api_key
CLOUDINARY_API_SECRET=your_api_secret
SHAZAM_KEYS=your_rapidapi_shazam_key
FIREBASE_CREDENTIALS_JSON=../database/firebase-key.json
```

### 5️⃣ Run the app

```bash
# Terminal 1 — Start the ingestion backend
cd cloud_functions
pip install -r requirements.txt
python main.py

# Terminal 2 — Run the Flutter app
flutter run
```

---

## 🛠 Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Mobile App** | Flutter 3 + Dart | Cross-platform UI (Android & iOS) |
| **State Management** | Provider | PlayerProvider, AuthProvider |
| **Audio** | just_audio + audio_session | Streaming, background playback, headset control |
| **Database** | Firebase Firestore | Live music catalog & user data |
| **Auth** | Firebase Authentication | Email/password sign-up & login |
| **Storage** | Cloudinary CDN | Audio files (M4A) & cover art (JPG) |
| **Backend** | Python + Flask | Ingestion API server |
| **Downloader** | yt-dlp | YouTube audio download |
| **Fingerprinting** | Shazam API (RapidAPI) | Track identification & metadata correction |
| **Image** | palette_generator | Dynamic background colour from album art |

---

## 🗂 Firestore Schema

<details>
<summary>📀 <strong>tracks</strong> collection</summary>

```json
{
  "title":          "Blinding Lights",
  "artist":         "The Weeknd",
  "album":          "After Hours",
  "secure_url":     "https://res.cloudinary.com/.../audio/the-weeknd/blinding-lights.m4a",
  "imageUrl":       "https://res.cloudinary.com/.../covers/after-hours.jpg",
  "duration_ms":    200040,
  "trackNumber":    1,
  "isExplicit":     false,
  "title_lc":       "blinding lights",
  "artist_lc":      "the weeknd",
  "alias_keys":     ["blinding lights||the weeknd"],
  "video_id":       "4NRXx6U8ABQ",
  "addedAt":        "2024-01-15T10:30:00Z"
}
```

</details>

<details>
<summary>📋 <strong>playlists</strong> collection</summary>

```json
{
  "name":           "Chill Vibes",
  "description":    "Easy listening for any time",
  "imageUrl":       "https://res.cloudinary.com/.../covers/chill.jpg",
  "owner":          "JoyalJose",
  "trackIds":       ["trackId1", "trackId2", "trackId3"],
  "likes":          1240,
  "isSpotifyOwned": false
}
```

</details>

<details>
<summary>👤 <strong>users</strong> collection</summary>

```json
{
  "name":             "Joyal Jose",
  "email":            "user@example.com",
  "createdAt":        "2024-01-01T00:00:00Z",
  "likedSongs":       ["trackId1", "trackId2"],
  "followedArtists":  ["artistId1"]
}
```

</details>

---

## 📁 Project Structure

```
Spotify_clone/
├── lib/
│   ├── main.dart                          # App entry, Firebase init
│   ├── theme/
│   │   ├── app_theme.dart                 # Spotify colour tokens & typography
│   │   └── spotify_fonts.dart             # Custom font definitions
│   ├── models/
│   │   └── models.dart                    # Song · Playlist · Artist · LibraryItem
│   ├── providers/
│   │   ├── app_provider.dart              # PlayerProvider · AuthProvider
│   │   └── ingestion_provider.dart        # Ingestion state management
│   ├── services/
│   │   ├── firebase_service.dart          # All Firestore queries & writes
│   │   └── ingestion_service.dart         # Backend API client
│   ├── screens/
│   │   ├── splash_screen.dart             # Animated splash with floating art
│   │   ├── main_screen.dart               # Shell + persistent MiniPlayer
│   │   ├── home/home_screen.dart          # Recently played · Playlists
│   │   ├── search/search_screen.dart      # Firestore search + YouTube
│   │   ├── library/library_screen.dart    # Full track library (live stream)
│   │   ├── player/now_playing_screen.dart # Full-screen player
│   │   └── auth/auth_screens.dart         # Login · Signup flow
│   └── widgets/
│       ├── mini_player.dart               # Persistent bottom player
│       ├── track_list_tile.dart           # Reusable track row
│       └── playlist_collage.dart          # 2×2 image collage widget
│
├── cloud_functions/
│   ├── main.py                            # Flask ingestion server
│   ├── requirements.txt                   # Python dependencies
│   └── .env.example                       # → copy to .env and fill in
│
├── database/
│   ├── firebase-key.json.example          # → copy to firebase-key.json
│   ├── download_playlist.py               # Bulk playlist downloader
│   └── sync_to_cloud.py                   # Local → Firestore sync tool
│
└── assets/
    ├── animations/splash.json             # Lottie splash animation
    ├── cookies/yt_cookies.txt.example     # → copy for YT cookie auth
    ├── fonts/                             # Spotify Mix UI font family
    └── images/                            # App icons & player controls
```

---

## 🔒 Security

All credentials are **excluded from this repository** via `.gitignore`. The following files are required locally but never committed:

| File | Purpose | Template |
|------|---------|----------|
| `android/app/google-services.json` | Firebase Android config | `google-services.json.example` |
| `database/firebase-key.json` | Firebase Admin SDK key | `database/firebase-key.json.example` |
| `cloud_functions/.env` | Backend API credentials | `cloud_functions/.env.example` |
| `assets/cookies/yt_cookies.txt` | YouTube session cookies | `assets/cookies/yt_cookies.txt.example` |

---

## 🛠 Troubleshooting

| Problem | Fix |
|---------|-----|
| `MissingPluginException` on audio | `flutter clean && flutter pub get` |
| Library screen empty | Check Firestore rules allow `read: if true` on `tracks` |
| Firebase `no-app` crash | Ensure `google-services.json` is in `android/app/` |
| Backend connection refused | Start `python main.py` in `cloud_functions/` |
| Cloudinary 401 error | Set delivery type to **public** in Cloudinary settings |
| Songs not streaming | Verify `secure_url` field starts with `https://` in Firestore |
| iOS audio stops in background | `Info.plist` already has `UIBackgroundModes: audio` ✅ |

---

## 🤝 Contributing

Contributions, issues and feature requests are welcome!

1. **Fork** the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'feat: add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a **Pull Request**

---

<div align="center">

Made by [Joyal Jose](https://github.com/JoyalJose54)

⭐ **Star this repo if you found it useful!**

</div>
