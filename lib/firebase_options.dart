// lib/firebase_options.dart
// 
// ─────────────────────────────────────────────────────────────────────────────
// SETUP INSTRUCTIONS
// ─────────────────────────────────────────────────────────────────────────────
// 1. Create a Firebase project at https://console.firebase.google.com
//
// 2. Register your Android app (package: com.example.spotify_clone)
//    and iOS app (bundle ID: com.example.spotifyClone)
//
// 3. Download:
//    • google-services.json → android/app/
//    • GoogleService-Info.plist → ios/Runner/
//
// 4. Run: flutterfire configure
//    This auto-generates this file with your real credentials.
//
// 5. Enable in Firebase Console:
//    • Authentication → Email/Password
//    • Firestore Database
//    • Storage
//
// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE COLLECTIONS STRUCTURE
// ─────────────────────────────────────────────────────────────────────────────
//
// /songs/{songId}
//   title: string
//   artist: string
//   artistId: string
//   album: string
//   albumId: string
//   imageUrl: string         ← Firebase Storage URL
//   audioUrl: string         ← Firebase Storage URL
//   durationMs: number
//   isExplicit: bool
//   trackNumber: number
//   searchTerms: string[]    ← lowercase tokens for search
//
// /albums/{albumId}
//   title: string
//   artist: string
//   artistId: string
//   imageUrl: string
//   year: number
//   type: 'album'|'single'|'ep'
//   featured: bool
//   releaseDate: timestamp
//
// /artists/{artistId}
//   name: string
//   imageUrl: string
//   followers: number
//   genres: string[]
//
// /playlists/{playlistId}
//   name: string
//   description: string
//   imageUrl: string
//   owner: string
//   likes: number
//   isEditorPick: bool
//   songIds: string[]
//
// /users/{uid}
//   name: string
//   email: string
//   createdAt: timestamp
//   followedArtists: string[]
//   likedSongs: string[]
//   /recentlyPlayed/{songId}
//     ...song fields
//     playedAt: timestamp
//   /library/{itemId}
//     name, imageUrl, owner, addedAt

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SECURITY RULES (paste in Firebase Console)
// ─────────────────────────────────────────────────────────────────────────────
//
// rules_version = '2';
// service cloud.firestore {
//   match /databases/{database}/documents {
//     // Public read for songs, albums, artists, playlists
//     match /songs/{doc}   { allow read: if true; allow write: if false; }
//     match /albums/{doc}  { allow read: if true; allow write: if false; }
//     match /artists/{doc} { allow read: if true; allow write: if false; }
//     match /playlists/{doc} { allow read: if true; allow write: if false; }
//
//     // User-private data
//     match /users/{uid}/{document=**} {
//       allow read, write: if request.auth != null && request.auth.uid == uid;
//     }
//   }
// }

// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE STORAGE RULES (paste in Firebase Console)
// ─────────────────────────────────────────────────────────────────────────────
//
// rules_version = '2';
// service firebase.storage {
//   match /b/{bucket}/o {
//     match /songs/{allPaths=**} {
//       allow read: if request.auth != null;
//     }
//     match /images/{allPaths=**} {
//       allow read: if true;
//     }
//   }
// }

// ─────────────────────────────────────────────────────────────────────────────
// UPLOADING SONGS TO FIREBASE STORAGE
// ─────────────────────────────────────────────────────────────────────────────
//
// Folder structure in Storage:
//   songs/
//     {songId}.mp3
//   images/
//     albums/
//       {albumId}.jpg
//     artists/
//       {artistId}.jpg
//
// After uploading, copy the download URL and save it in the corresponding
// Firestore document's audioUrl / imageUrl field.
