import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'ingestion_service.dart';
import 'package:rxdart/rxdart.dart';


// ─────────────────────────────────────────────────────────────────────────────
//  FirebaseService
//
//  Key collections:
//    tracks    – every song; secure_url = Cloudinary CDN audio URL
//    playlists – list of trackIds + metadata
//    users     – per-user liked songs, recently played, library
// ─────────────────────────────────────────────────────────────────────────────
class FirebaseService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static List<Song> _cachedAllTracks = [];
  static DateTime? _lastFetchTime;

  static User? get currentUser => _auth.currentUser;

  // ══════════════════════════════════════════════════════════════════════════
  //  TRACKS  (Cloudinary-backed)
  // ══════════════════════════════════════════════════════════════════════════

  // ── Shared tracks broadcast (single Firestore connection for entire app) ────
  // BehaviorSubject replays the last value to every new subscriber, so widgets
  // that attach after the first snapshot still get data immediately.
  static final BehaviorSubject<List<Song>> _tracksSubject =
      BehaviorSubject<List<Song>>();
  static StreamSubscription<List<Song>>? _tracksSubscription;

  /// Shared, app-wide live stream of all tracks (ordered by title).
  /// Lazily starts one Firestore snapshot listener the first time it is called;
  /// all subsequent callers share the same WebSocket channel via the subject.
  /// Live stream of all tracks in the database.
  /// Uses a single shared Firestore listener — the first subscriber starts it,
  /// all subsequent callers share the same WebSocket channel via the subject.
  static Stream<List<Song>> streamAllTracks() {
    _tracksSubscription ??= _db
          .collection('tracks')
          .snapshots()
          .map((snap) {
            final songs = <Song>[];
            for (final doc in snap.docs) {
              try {
                songs.add(Song.fromFirestore(doc));
              } catch (e) {
                debugPrint('Error parsing track ${doc.id}: $e');
              }
            }
            songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
            _cachedAllTracks = songs;
            _lastFetchTime = DateTime.now();
            return songs;
          })
          .listen(
            _tracksSubject.add,
            onError: (err) {
              debugPrint('Error in streamAllTracks: $err');
              _tracksSubject.addError(err);
            },
          );
    return _tracksSubject.stream;
  }

  /// Alias kept for backward compatibility — delegates to streamAllTracks().
  static Stream<List<Song>> streamAllSongs() => streamAllTracks();


  /// One-shot fetch of all tracks (used when a stream isn't needed).
  static Future<List<Song>> fetchAllTracks() async {
    // 1. Prefer active subject values if available
    if (_tracksSubject.hasValue && _tracksSubject.value.isNotEmpty) {
      _cachedAllTracks = _tracksSubject.value;
      _lastFetchTime = DateTime.now();
      return _cachedAllTracks;
    }

    // 2. Return cached if still fresh (< 5 minutes)
    if (_cachedAllTracks.isNotEmpty && _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < const Duration(minutes: 5)) {
      return _cachedAllTracks;
    }

    // 3. Fetch from Firestore without forcing orderBy so tracks without title are not dropped
    try {
      final snap = await _db.collection('tracks').get();
      final List<Song> songs = [];
      for (final doc in snap.docs) {
        try {
          songs.add(Song.fromFirestore(doc));
        } catch (e) {
          debugPrint('Error parsing track in fetchAllTracks ${doc.id}: $e');
        }
      }
      songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (songs.isNotEmpty) {
        _cachedAllTracks = songs;
        _lastFetchTime = DateTime.now();
        if (!_tracksSubject.hasValue || _tracksSubject.value.isEmpty) {
          _tracksSubject.add(songs);
        }
      }
      return _cachedAllTracks;
    } catch (e) {
      debugPrint('fetchAllTracks error: $e');
      return _cachedAllTracks;
    }
  }


  /// One-shot fetch of tracks for a specific album.
  static Future<List<Song>> fetchTracksByAlbum(String albumId) async {
    try {
      final snap = await _db
          .collection('tracks')
          .where('albumId', isEqualTo: albumId)
          .orderBy('trackNumber')
          .get();
      return snap.docs.map(Song.fromFirestore).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Song>> searchTracks(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final all = await fetchAllTracks();
    final tracksToSearch = _cachedAllTracks.isNotEmpty ? _cachedAllTracks : all;
    if (tracksToSearch.isEmpty) return [];

    final terms = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final results = tracksToSearch.where((s) {
      final title = s.title.toLowerCase();
      final artist = s.artist.toLowerCase();
      final album = s.album.toLowerCase();
      final combined = '$title $artist $album';

      // 1. Direct query match on title, artist, or album
      if (title.contains(cleanQuery) ||
          artist.contains(cleanQuery) ||
          album.contains(cleanQuery)) {
        return true;
      }

      // 2. Multi-word search (e.g. "artist song_title" or "yellow coldplay")
      if (terms.isNotEmpty && terms.every((t) => combined.contains(t))) {
        return true;
      }

      return false;
    }).toList();

    results.sort((a, b) {
      final aTitle = a.title.toLowerCase();
      final bTitle = b.title.toLowerCase();
      final aArtist = a.artist.toLowerCase();
      final bArtist = b.artist.toLowerCase();

      int scoreA = 0;
      if (aTitle == cleanQuery) {
        scoreA += 120;
      } else if (aTitle.startsWith(cleanQuery)) {
        scoreA += 70;
      } else if (aTitle.contains(cleanQuery)) {
        scoreA += 40;
      }

      if (aArtist == cleanQuery) {
        scoreA += 90;
      } else if (aArtist.startsWith(cleanQuery)) {
        scoreA += 50;
      } else if (aArtist.contains(cleanQuery)) {
        scoreA += 30;
      }

      for (final t in terms) {
        if (aTitle.contains(t)) scoreA += 15;
        if (aArtist.contains(t)) scoreA += 10;
        if (a.album.toLowerCase().contains(t)) scoreA += 5;
      }

      int scoreB = 0;
      if (bTitle == cleanQuery) {
        scoreB += 120;
      } else if (bTitle.startsWith(cleanQuery)) {
        scoreB += 70;
      } else if (bTitle.contains(cleanQuery)) {
        scoreB += 40;
      }

      if (bArtist == cleanQuery) {
        scoreB += 90;
      } else if (bArtist.startsWith(cleanQuery)) {
        scoreB += 50;
      } else if (bArtist.contains(cleanQuery)) {
        scoreB += 30;
      }

      for (final t in terms) {
        if (bTitle.contains(t)) scoreB += 15;
        if (bArtist.contains(t)) scoreB += 10;
        if (b.album.toLowerCase().contains(t)) scoreB += 5;
      }

      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Higher score first
      }
      return aTitle.compareTo(bTitle);
    });

    return results;
  }

  /// Stream a subset of tracks matching an artist.
  static Stream<List<Song>> streamTracksByArtist(String artistName) {
    return _db
        .collection('tracks')
        .where('artist', isEqualTo: artistName)
        .snapshots()
        .map((s) => s.docs.map(Song.fromFirestore).toList());
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PLAYLISTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Live stream of all playlists with their tracks resolved.
  /// Uses the shared tracks subject — does NOT open a second tracks connection.
  static Stream<List<Playlist>> streamPlaylists() {
    return Rx.combineLatest2(
      _db.collection('playlists').orderBy('name').snapshots(),
      streamAllTracks(), // ← reuses the single shared tracks subscription
      (QuerySnapshot pSnap, List<Song> allTracks) {
        final trackMap = {for (final t in allTracks) t.id: t};
        return pSnap.docs.map((doc) {
          final pl = Playlist.fromFirestore(doc);
          final resolved = pl.trackIds
              .map((id) => trackMap[id])
              .whereType<Song>()
              .toList();
          return pl.withTracks(resolved);
        }).toList();
      },
    );
  }

  /// Fetch a single playlist with its tracks resolved.
  static Future<Playlist?> fetchPlaylist(String playlistId) async {
    try {
      final doc = await _db.collection('playlists').doc(playlistId).get();
      if (!doc.exists) return null;
      final pl        = Playlist.fromFirestore(doc);
      final allTracks = await fetchAllTracks();
      final trackMap  = {for (final t in allTracks) t.id: t};
      final resolved  = pl.trackIds.map((id) => trackMap[id]).whereType<Song>().toList();
      return pl.withTracks(resolved);
    } catch (_) {
      return null;
    }
  }

  /// Create a new user playlist (stores trackIds, no file copying).
  static Future<String?> createPlaylist({
    required String name,
    String description = '',
    List<String> trackIds = const [],
  }) async {
    try {
      await _ensureLoggedIn();
      final uid = _auth.currentUser?.uid ?? 'local_user';

      final doc = await _db.collection('playlists').add({
        'name'          : name,
        'description'   : description,
        'owner'         : uid,
        'creator_id'    : uid,
        'trackIds'      : trackIds,
        'track_ids'     : trackIds,
        'songIds'       : trackIds,
        'likes'         : 0,
        'isSpotifyOwned': false,
        'createdAt'     : FieldValue.serverTimestamp(),
      });
      print('[FirebaseService] Playlist created: ${doc.id}');
      return doc.id;
    } catch (e) {
      print('[FirebaseService] createPlaylist ERROR: $e');
      rethrow; 
    }
  }

  static Future<void> deletePlaylist(String playlistId) async {
    try {
      await _ensureLoggedIn();
      await _db.collection('playlists').doc(playlistId).delete();
      print('[FirebaseService] Playlist deleted: $playlistId');
    } catch (e) {
      print('[FirebaseService] deletePlaylist ERROR: $e');
      rethrow;
    }
  }

  static Future<void> renamePlaylist(String playlistId, String newName) async {
    try {
      await _ensureLoggedIn();
      await _db.collection('playlists').doc(playlistId).update({
        'name': newName,
      });
      print('[FirebaseService] Playlist renamed: $playlistId to $newName');
    } catch (e) {
      print('[FirebaseService] renamePlaylist ERROR: $e');
      rethrow;
    }
  }

  /// Add a track to an existing playlist.
  static Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    await _ensureLoggedIn();
    await _db.collection('playlists').doc(playlistId).update({
      'trackIds': FieldValue.arrayUnion([trackId]),
      'track_ids': FieldValue.arrayUnion([trackId]),
      'songIds': FieldValue.arrayUnion([trackId]),
    });
  }

  /// Add multiple tracks to a playlist.
  static Future<void> addTracksToPlaylist(String playlistId, List<String> trackIds) async {
    if (trackIds.isEmpty) return;
    await _ensureLoggedIn();
    await _db.collection('playlists').doc(playlistId).update({
      'trackIds': FieldValue.arrayUnion(trackIds),
      'track_ids': FieldValue.arrayUnion(trackIds),
      'songIds': FieldValue.arrayUnion(trackIds),
    });
  }

  /// Remove multiple tracks from a playlist.
  static Future<void> removeTracksFromPlaylist(String playlistId, List<String> trackIds) async {
    if (trackIds.isEmpty) return;
    await _ensureLoggedIn();
    await _db.collection('playlists').doc(playlistId).update({
      'trackIds': FieldValue.arrayRemove(trackIds),
      'track_ids': FieldValue.arrayRemove(trackIds),
      'songIds': FieldValue.arrayRemove(trackIds),
    });
  }

  /// Fetch a lightweight list of user-created playlists (id + name only).
  /// Used by the ingestion playlist picker to avoid fetching full track data.
  static Future<List<({String id, String name})>> fetchUserPlaylists() async {
    try {
      final snap = await _db
          .collection('playlists')
          .orderBy('name')
          .get();
      return snap.docs.map((d) => (
        id:   d.id,
        name: (d.data()['name'] as String?) ?? 'Untitled',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Remove a track from a playlist.
  static Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    await _ensureLoggedIn();
    await _db.collection('playlists').doc(playlistId).update({
      'trackIds': FieldValue.arrayRemove([trackId]),
      'track_ids': FieldValue.arrayRemove([trackId]),
      'songIds': FieldValue.arrayRemove([trackId]),
    });
  }

  /// Delete a track entirely from the database and remove references in all playlists.
  /// Full deletion: Audio file, metadata, and all playlist references.
  /// Firestore document is deleted immediately, while Cloudinary and playlist references
  /// are cleaned up asynchronously in the background to ensure a highly responsive user experience.
  static Future<void> deleteTrack(String trackId) async {
    _lastFetchTime = null; // Invalidate cache

    // Delete track metadata from Firestore immediately (critical path for optimistic UI updates)
    await _db.collection('tracks').doc(trackId).delete();

    // Clean up references and Cloudinary media asynchronously in the background
    _cleanupTrackReferencesAndMedia(trackId);
  }

  static void _cleanupTrackReferencesAndMedia(String trackId) async {
    try {
      // Attempt backend cleanup (Cloudinary), with a timeout so it doesn't run indefinitely
      await IngestionService.deleteTrack(trackId).timeout(const Duration(seconds: 15));
    } catch (e) {
      print('[FirebaseService] Background backend delete error: $e');
    }

    try {
      // Remove references of this song from all playlists
      final playlistsSnap = await _db.collection('playlists').get();
      final batch = _db.batch();
      bool modifiedAny = false;
      for (final doc in playlistsSnap.docs) {
        final data = doc.data();
        final trackIds = List<String>.from(data['trackIds'] ?? []);
        final trackIdsUnderscore = List<String>.from(data['track_ids'] ?? []);
        final songIds = List<String>.from(data['songIds'] ?? []);

        bool modified = false;
        if (trackIds.contains(trackId)) {
          trackIds.remove(trackId);
          modified = true;
        }
        if (trackIdsUnderscore.contains(trackId)) {
          trackIdsUnderscore.remove(trackId);
          modified = true;
        }
        if (songIds.contains(trackId)) {
          songIds.remove(trackId);
          modified = true;
        }

        if (modified) {
          batch.update(doc.reference, {
            'trackIds': trackIds,
            'track_ids': trackIdsUnderscore,
            'songIds': songIds,
          });
          modifiedAny = true;
        }
      }
      if (modifiedAny) {
        await batch.commit();
      }
    } catch (e) {
      print('[FirebaseService] Background playlist cleanup error: $e');
    }
  }

  /// Reorder tracks in a playlist by saving the entire new ordered list.
  static Future<void> reorderPlaylistTracks(String playlistId, List<String> newTrackIds) async {
    await _ensureLoggedIn();
    await _db.collection('playlists').doc(playlistId).update({
      'trackIds': newTrackIds,
      'track_ids': newTrackIds,
      'songIds': newTrackIds,
    });
  }

  /// Update playlist name and description together.
  static Future<void> updatePlaylistDetails(String playlistId, {required String name, String description = ''}) async {
    await _ensureLoggedIn();
    await _db.collection('playlists').doc(playlistId).update({
      'name': name,
      'description': description,
    });
  }


  /// Live stream of tracks for a specific playlist.
  /// Uses combineLatest2 with the shared tracks subject — no extra Firestore
  /// connection is opened; it reacts to both playlist edits and track changes.
  static Stream<List<Song>> streamPlaylistSongs(String playlistId) {
    return Rx.combineLatest2(
      _db.collection('playlists').doc(playlistId).snapshots(),
      streamAllTracks(), // shared broadcast — zero new Firestore connections
      (DocumentSnapshot pSnap, List<Song> allTracks) {
        if (!pSnap.exists) return <Song>[];
        final pl = Playlist.fromFirestore(pSnap);
        if (pl.trackIds.isEmpty) return <Song>[];
        final trackMap = {for (final t in allTracks) t.id: t};
        return pl.trackIds
            .map((id) => trackMap[id])
            .whereType<Song>()
            .toList();
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PLAY COUNT TRACKING
  // ══════════════════════════════════════════════════════════════════════════

  /// Increment the play count for a track (fire-and-forget, safe to ignore errors).
  static Future<void> incrementPlayCount(String trackId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || trackId.isEmpty) return;
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('playCounts')
          .doc(trackId)
          .set({
        'trackId'      : trackId,
        'count'        : FieldValue.increment(1),
        'lastPlayedAt' : FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {/* silent – non-critical */}
  }

  /// Stream the top N most-played tracks for the current user.
  /// Falls back to an empty list if there is no play history.
  static Stream<List<({Song song, int count})>> streamTopTracks({int limit = 10}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return Rx.combineLatest2(
      _db
          .collection('users')
          .doc(uid)
          .collection('playCounts')
          .orderBy('count', descending: true)
          .limit(limit)
          .snapshots(),
      streamAllTracks(),
      (QuerySnapshot countSnap, List<Song> allTracks) {
        final trackMap = {for (final t in allTracks) t.id: t};
        final result = <({Song song, int count})>[];
        for (final doc in countSnap.docs) {
          final data  = doc.data() as Map<String, dynamic>;
          final count = (data['count'] as num?)?.toInt() ?? 0;
          final song  = trackMap[doc.id];
          if (song != null) result.add((song: song, count: count));
        }
        return result;
      },
    );
  }

  /// Stream the top N artists derived from play count data.
  /// Groups play counts by artist name and sums them.
  static Stream<List<({String artist, int totalPlays, List<Song> songs, String imageUrl})>> streamTopArtists({int limit = 5}) {
    return streamTopTracks(limit: 50).map((entries) {
      // Group by artist
      final Map<String, ({int plays, List<Song> songs})> grouped = {};
      for (final e in entries) {
        final name = e.song.artist;
        if (name.isEmpty || name == 'Unknown Artist') continue;
        if (grouped.containsKey(name)) {
          final existing = grouped[name]!;
          grouped[name] = (
            plays: existing.plays + e.count,
            songs: [...existing.songs, e.song],
          );
        } else {
          grouped[name] = (plays: e.count, songs: [e.song]);
        }
      }

      // Sort by total plays descending
      final sorted = grouped.entries.toList()
        ..sort((a, b) => b.value.plays.compareTo(a.value.plays));

      return sorted.take(limit).map((entry) {
        final songs = entry.value.songs;
        final imageUrl = songs.isNotEmpty ? songs.first.imageUrl : '';
        return (
          artist    : entry.key,
          totalPlays: entry.value.plays,
          songs     : songs,
          imageUrl  : imageUrl,
        );
      }).toList();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  USER LIBRARY
  // ══════════════════════════════════════════════════════════════════════════

  /// Stream the user's custom playlist order.
  static Stream<List<String>> streamPlaylistOrder() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return [];
      return List<String>.from(snap.data()?['playlistOrder'] ?? []);
    });
  }

  /// Save the user's custom playlist order.
  static Future<void> savePlaylistOrder(List<String> order) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'playlistOrder': order,
    }, SetOptions(merge: true));
  }

  /// Record a recently played track.
  static Future<void> addRecentlyPlayed(String trackId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    // Store as subcollection with timestamp so we can order by playedAt
    await _db
        .collection('users')
        .doc(uid)
        .collection('recentlyPlayed')
        .doc(trackId)
        .set({'trackId': trackId, 'playedAt': FieldValue.serverTimestamp()});
  }

  /// Remove a recently played track.
  static Future<void> removeRecentlyPlayed(String trackId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('recentlyPlayed')
        .doc(trackId)
        .delete();
  }

  /// Clear all recently played tracks.
  static Future<void> clearRecentlyPlayed() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('recentlyPlayed')
        .get();
    
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Stream the 10 most recently played tracks (resolved to Song objects).
  static Stream<List<Song>> streamRecentlyPlayed() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(uid)
        .collection('recentlyPlayed')
        .orderBy('playedAt', descending: true)
        .limit(15)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <Song>[];
      final ids       = snap.docs.map((d) => d.id).toList();
      final allTracks = await fetchAllTracks();
      final trackMap  = {for (final t in allTracks) t.id: t};
      return ids.map((id) => trackMap[id]).whereType<Song>().toList();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  RECENT SEARCHES
  // ══════════════════════════════════════════════════════════════════════════

  /// Record a searched track into the user's search history.
  static Future<void> addRecentSearch(String trackId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('recentSearches')
        .doc(trackId)
        .set({'trackId': trackId, 'searchedAt': FieldValue.serverTimestamp()});
  }

  /// Remove a searched track from history.
  static Future<void> removeRecentSearch(String trackId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('recentSearches')
        .doc(trackId)
        .delete();
  }

  /// Clear all search history.
  static Future<void> clearRecentSearches() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('recentSearches')
        .get();

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Stream user's recent searches (resolved to Song objects).
  static Stream<List<Song>> streamRecentSearches() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(uid)
        .collection('recentSearches')
        .orderBy('searchedAt', descending: true)
        .limit(20)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <Song>[];
      final ids       = snap.docs.map((d) => d.id).toList();
      final allTracks = await fetchAllTracks();
      final trackMap  = {for (final t in allTracks) t.id: t};
      return ids.map((id) => trackMap[id]).whereType<Song>().toList();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  AUTH
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> updateUserName(String name) async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.updateDisplayName(name);
      await _db.collection('users').doc(user.uid).update({'name': name});
    }
  }

  static Future<UserCredential?> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    await cred.user?.updateDisplayName(name);
    await _db.collection('users').doc(cred.user!.uid).set({
      'name'            : name,
      'email'           : email,
      'likedSongs'      : [],
      'followedArtists' : [],
      'createdAt'       : FieldValue.serverTimestamp(),
    });
    return cred;
  }

  static Future<UserCredential?> loginWithEmail({
    required String email,
    required String password,
  }) => _auth.signInWithEmailAndPassword(email: email, password: password);

  static Future<void> signOut() => _auth.signOut();

  static Future<void> saveFollowedArtists(List<String> artistIds) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid)
        .set({'followedArtists': artistIds}, SetOptions(merge: true));
  }

  /// Ensures a Firebase user exists if auth is available and configured,
  /// but never throws or blocks operations if anonymous auth fails (e.g. invalid API key or offline).
  static Future<void> _ensureLoggedIn() async {
    if (_auth.currentUser == null) {
      try {
        await signInAnonymously();
      } catch (e) {
        debugPrint('[FirebaseService] Optional anonymous sign-in skipped/failed: $e');
      }
    }
  }

  static Future<UserCredential?> signInAnonymously() async {
    try {
      print('[FirebaseService] Signing in anonymously...');
      final cred = await _auth.signInAnonymously();
      print('[FirebaseService] Signed in: ${cred.user?.uid}');
      return cred;
    } catch (e) {
      print('[FirebaseService] signInAnonymously error: $e');
      return null;
    }
  }
}
