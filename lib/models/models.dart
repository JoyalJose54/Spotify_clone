import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Song  –  mirrors the Firestore `tracks` collection document.
//
//  Firestore field       →  Dart field
//  ───────────────────────────────────────────────────────
//  title                 →  title
//  artist                →  artist
//  secure_url            →  streamUrl   ← Cloudinary CDN audio URL
//  imageUrl / thumbnail  →  imageUrl    ← cover art
//  album                 →  album
//  albumId               →  albumId
//  artistId              →  artistId
//  duration_ms           →  durationMs
//  trackNumber           →  trackNumber
//  isExplicit            →  isExplicit
// ─────────────────────────────────────────────────────────────────────────────
class Song {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String album;
  final String albumId;
  final String imageUrl;  // cover art
  final String streamUrl; // Cloudinary secure_url → fed to just_audio
  final int    durationMs;
  final bool   isExplicit;
  final int    trackNumber;
  final String videoId;
  final DateTime? createdAt;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId    = '',
    this.album       = '',
    this.albumId     = '',
    this.imageUrl    = '',
    required this.streamUrl,
    this.durationMs  = 0,
    this.isExplicit  = false,
    this.trackNumber = 1,
    this.videoId     = '',
    this.createdAt,
  });

  // ── Firestore deserialization ──────────────────────────────────────────────
  // Tolerates multiple field-name conventions from different upload scripts.
  factory Song.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    // Audio URL: prefer secure_url (Cloudinary), fall back to legacy names
    final streamUrl =
        _str(d, 'secure_url')  ??
        _str(d, 'audioUrl')    ??
        _str(d, 'audio_url')   ??
        _str(d, 'url')         ?? '';

    // Cover image
    final imageUrl =
        _str(d, 'imageUrl')      ??
        _str(d, 'image_url')     ??
        _str(d, 'thumbnail_url') ??
        _str(d, 'thumbnail')     ??
        _str(d, 'coverUrl')      ?? '';

    // Duration: duration_ms (int ms) OR duration (float seconds)
    int durationMs = 0;
    if (d['duration_ms'] != null) {
      durationMs = (d['duration_ms'] as num).toInt();
    } else if (d['durationMs'] != null) durationMs = (d['durationMs'] as num).toInt();
    else if (d['duration']   != null) durationMs = ((d['duration'] as num) * 1000).toInt();

    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();

    return Song(
      id          : doc.id,
      title       : (_str(d, 'title')  ?? 'Unknown Title').trim(),
      artist      : (_str(d, 'artist') ?? 'Unknown Artist').trim(),
      artistId    : _str(d, 'artistId')    ?? '',
      album       : _str(d, 'album')       ?? '',
      albumId     : _str(d, 'albumId')     ?? '',
      imageUrl    : imageUrl,
      streamUrl   : streamUrl,
      durationMs  : durationMs,
      isExplicit  : d['isExplicit'] as bool? ?? false,
      trackNumber : (d['trackNumber'] as num?)?.toInt() ?? 1,
      videoId     : _str(d, 'video_id')    ?? _str(d, 'videoId') ?? '',
      createdAt   : createdAt,
    );
  }

  static String? _str(Map<String, dynamic> d, String key) {
    final v = d[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  // ── copyWith for patching durationMs after just_audio reports it ───────────
  Song copyWith({int? durationMs, String? streamUrl, String? videoId}) => Song(
    id: id, title: title, artist: artist,
    artistId: artistId, album: album, albumId: albumId,
    imageUrl: imageUrl,
    streamUrl   : streamUrl   ?? this.streamUrl,
    durationMs  : durationMs  ?? this.durationMs,
    isExplicit  : isExplicit, trackNumber: trackNumber,
    videoId     : videoId     ?? this.videoId,
    createdAt   : createdAt,
  );

  String get durationFormatted => _fmtMs(durationMs);
  static String fmtDuration(Duration d) => _fmtMs(d.inMilliseconds);

  static String _fmtMs(int ms) {
    if (ms <= 0) return '0:00';
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'Song($title – $artist)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Playlist  –  mirrors `playlists` Firestore collection.
// Holds a list of track IDs; tracks are resolved in the service layer.
// ─────────────────────────────────────────────────────────────────────────────
class Playlist {
  final String       id;
  final String       name;
  final String       description;
  final String       imageUrl;
  final String       owner;
  final int          likes;
  final List<String> trackIds;  // doc IDs from `tracks` collection
  final List<Song>   tracks;    // resolved songs (in-memory)
  final bool         isSpotifyOwned;
  final DateTime?    createdAt;

  const Playlist({
    required this.id,
    required this.name,
    this.description    = '',
    this.imageUrl       = '',
    this.owner          = 'You',
    this.likes          = 0,
    this.trackIds       = const [],
    this.tracks         = const [],
    this.isSpotifyOwned = false,
    this.createdAt,
  });

  factory Playlist.fromFirestore(
    DocumentSnapshot doc, {
    List<Song> resolvedTracks = const [],
  }) {
    final d = doc.data() as Map<String, dynamic>;
    return Playlist(
      id          : doc.id,
      name        : d['name']        as String? ?? 'Untitled Playlist',
      description : d['description'] as String? ?? '',
      imageUrl    : d['imageUrl']    as String? ?? '',
      owner       : d['owner']       as String? ?? 'You',
      likes       : (d['likes'] as num?)?.toInt() ?? 0,
      trackIds    : {...List<String>.from(d['trackIds'] ?? []), ...List<String>.from(d['track_ids'] ?? []), ...List<String>.from(d['songIds'] ?? [])}.toList(),
      tracks      : resolvedTracks,
      isSpotifyOwned: d['isSpotifyOwned'] as bool? ?? false,
      createdAt   : (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Playlist withTracks(List<Song> resolved) => Playlist(
    id: id, name: name, description: description, imageUrl: imageUrl,
    owner: owner, likes: likes, trackIds: trackIds, tracks: resolved,
    isSpotifyOwned: isSpotifyOwned, createdAt: createdAt,
  );

  String get durationFormatted {
    final ms = tracks.fold<int>(0, (s, t) => s + t.durationMs);
    final h  = ms ~/ 3600000;
    final m  = (ms % 3600000) ~/ 60000;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  int get trackCount => tracks.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Artist  (onboarding + search)
// ─────────────────────────────────────────────────────────────────────────────
class Artist {
  final String       id;
  final String       name;
  final String       imageUrl;
  final int          followers;
  final List<String> genres;

  const Artist({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.followers = 0,
    this.genres    = const [],
  });

  factory Artist.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Artist(
      id        : doc.id,
      name      : d['name']     as String? ?? '',
      imageUrl  : d['imageUrl'] as String? ?? '',
      followers : (d['followers'] as num?)?.toInt() ?? 0,
      genres    : List<String>.from(d['genres'] ?? []),
    );
  }

  static List<Artist> get sampleArtists => [
    const Artist(id: 'a1',  name: 'Billie Eilish', imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb4f2c7ec0f7f04059987b9a28', followers: 73000000),
    const Artist(id: 'a2',  name: 'Kanye West',    imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb867008a971fae0f4d913f63b', followers: 22000000),
    const Artist(id: 'a3',  name: 'Ariana Grande', imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb40b277b5cdd0b0e010f47cf2', followers: 85000000),
    const Artist(id: 'a4',  name: 'Lana Del Rey',  imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb271fc7c01be27cf3823dc9f6', followers: 27000000),
    const Artist(id: 'a5',  name: 'BTS',           imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb9478c37b4c62d13b80e4e760', followers: 44000000),
    const Artist(id: 'a6',  name: 'Drake',         imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb4293385d324db8558179afd9', followers: 68000000),
    const Artist(id: 'a7',  name: 'Harry Styles',  imageUrl: 'https://i.scdn.co/image/ab6761610000e5eba0d0e2bad6eb2fc8d4a74a7e', followers: 40000000),
    const Artist(id: 'a8',  name: 'One Direction', imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb1d0d6dfaa5ede7ff59fb3c0e', followers: 16000000),
    const Artist(id: 'a9',  name: 'Rihanna',       imageUrl: 'https://i.scdn.co/image/ab67616100005174e47b3c6f26d83d4e12282f64', followers: 43000000),
    const Artist(id: 'a10', name: 'Ed Sheeran',    imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb3bcef85e105dfc42399ef0ba', followers: 87000000),
    const Artist(id: 'a11', name: 'The Weeknd',    imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb214f3cf1cbe7139c1e26ffbb', followers: 73000000),
    const Artist(id: 'a12', name: 'Dua Lipa',      imageUrl: 'https://i.scdn.co/image/ab6761610000e5eb1178e33cf3ac6a0a4ded1ab4', followers: 56000000),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// LibraryItem  (sidebar row in library screen)
// ─────────────────────────────────────────────────────────────────────────────
enum LibraryItemType { allTracks, playlist, artist, album, podcast, song }

class LibraryItem {
  final String          id;
  final String          name;
  final String          subtitle;
  final String          imageUrl;
  final LibraryItemType type;
  final bool            isPinned;
  final Playlist?       playlist;

  const LibraryItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.imageUrl,
    required this.type,
    this.isPinned = false,
    this.playlist,
  });
}
