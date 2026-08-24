import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ingestion_service.dart';
import '../services/firebase_service.dart';
import '../models/models.dart';

class IngestionProvider extends ChangeNotifier {
  // ── CSV Ingestion State ────────────────────────────────────────────────────
  List<CsvEntryState> csvEntries = [];
  bool csvProcessing = false;
  int csvDoneCount = 0;
  int csvSuccessCount = 0;
  int csvDupCount = 0;
  int csvFailCount = 0;
  String csvActiveTrack = '';
  List<CsvEntryState> pendingDuplicates = [];
  Map<String, String> playlistCache = {};
  List<({String id, String name})> localPlaylists = [];

  // ── YouTube Search Ingestion State ──────────────────────────────────────────
  final Set<String> ingestingVideoIds = {};
  final Map<String, double> ingestionProgress = {};
  final Map<String, bool> doneVideoIds = {};
  final Map<String, String?> libraryCheck = {};
  bool checkingLibrary = false;

  // Search tab persistent states
  String searchQuery = '';
  List<YouTubeSearchResult> searchResults = [];
  bool isSearching = false;
  String? searchError;

  void setSearchResults(String query, List<YouTubeSearchResult> results, String? error) {
    searchQuery = query;
    searchResults = results;
    searchError = error;
    isSearching = false;
    notifyListeners();
  }

  void setSearchSearching(bool searching) {
    isSearching = searching;
    searchError = null;
    notifyListeners();
  }

  // ── Set CSV Entries ────────────────────────────────────────────────────────
  void setCsvEntries(List<CsvEntryState> entries) {
    csvEntries = entries;
    csvDoneCount = 0;
    csvSuccessCount = 0;
    csvDupCount = 0;
    csvFailCount = 0;
    csvActiveTrack = '';
    pendingDuplicates.clear();
    notifyListeners();
  }

  void clearCsvState() {
    csvEntries = [];
    csvDoneCount = 0;
    csvSuccessCount = 0;
    csvDupCount = 0;
    csvFailCount = 0;
    csvActiveTrack = '';
    pendingDuplicates.clear();
    notifyListeners();
  }

  // ── Start CSV Processing ───────────────────────────────────────────────────
  Future<void> startCsvProcessing({
    required String? selectedPlaylistId,
    required List<Song> cachedTracks,
    required List<({String id, String name})> playlists,
    required void Function(String msg, {bool isError}) showSnack,
  }) async {
    if (csvEntries.isEmpty || csvProcessing) return;

    csvProcessing = true;
    csvDoneCount = 0;
    csvSuccessCount = 0;
    csvDupCount = 0;
    csvFailCount = 0;
    pendingDuplicates.clear();
    notifyListeners();

    // Populate local playlist cache
    playlistCache.clear();
    for (final pl in playlists) {
      playlistCache[pl.name.toLowerCase().trim()] = pl.id;
    }

    for (int i = 0; i < csvEntries.length; i++) {
      if (!csvProcessing) break; // Allow stopping if needed

      final row = csvEntries[i];
      row.status = EntryStatus.processing;
      csvActiveTrack = '${row.entry.title} - ${row.entry.artist}';
      notifyListeners();

      // 1. Resolve Target Playlist Name & ID dynamically
      String? targetPlaylistId;
      final rowPlaylistName = row.entry.playlistName.trim();
      if (rowPlaylistName.isNotEmpty) {
        final cacheKey = rowPlaylistName.toLowerCase();
        if (playlistCache.containsKey(cacheKey)) {
          targetPlaylistId = playlistCache[cacheKey];
        } else {
          row.message = 'Creating playlist...';
          notifyListeners();
          try {
            final newId = await FirebaseService.createPlaylist(name: rowPlaylistName);
            if (newId != null) {
              targetPlaylistId = newId;
              playlistCache[cacheKey] = newId;
              playlists.add((id: newId, name: rowPlaylistName));
            }
          } catch (e) {
            row.status = EntryStatus.failed;
            row.message = 'Failed to create playlist: $e';
            csvFailCount++;
            csvDoneCount = i + 1;
            notifyListeners();
            continue;
          }
        }
      } else {
        targetPlaylistId = selectedPlaylistId;
      }

      if (targetPlaylistId == null || targetPlaylistId.isEmpty) {
        row.status = EntryStatus.failed;
        row.message = 'No target playlist';
        csvFailCount++;
        csvDoneCount = i + 1;
        notifyListeners();
        continue;
      }

      // 2. Exact local duplicate detection (title + artist must both match)
      final potentialDup = _findExactDuplicate(row.entry.title, row.entry.artist, cachedTracks);
      if (potentialDup != null) {
        row.status = EntryStatus.duplicate;
        row.message = 'Already in library (Linked)';
        row.trackId = potentialDup.id;
        csvDoneCount = i + 1;
        csvDupCount++;
        notifyListeners();
        try {
          await FirebaseService.addTrackToPlaylist(targetPlaylistId, potentialDup.id);
        } catch (_) {}
        continue;
      }

      // 3. Client-side exact duplicate pre-check
      try {
        final existingId = await IngestionService.checkDuplicate(
          title: row.entry.title,
          artist: row.entry.artist,
        );

        if (existingId != null) {
          row.status = EntryStatus.duplicate;
          row.message = 'Already in library (Linked)';
          row.trackId = existingId;
          csvDoneCount = i + 1;
          csvDupCount++;
          notifyListeners();
          try {
            await FirebaseService.addTrackToPlaylist(targetPlaylistId, existingId);
          } catch (_) {}
          continue;
        }
      } catch (_) {}

      // 4. Ingest New Song via Backend
      try {
        final result = await IngestionService.ingestSong(
          title: row.entry.title,
          artist: row.entry.artist,
          playlistId: targetPlaylistId,
        );

        if (result.success) {
          row.status = result.isDuplicate ? EntryStatus.duplicate : EntryStatus.done;
          row.message = result.message;
          row.trackId = result.trackId;
          if (result.isDuplicate) {
            csvDupCount++;
          } else {
            csvSuccessCount++;
          }
        } else {
          row.status = EntryStatus.failed;
          row.message = result.errorMessage ?? 'Unknown error';
          csvFailCount++;
        }
      } catch (e) {
        row.status = EntryStatus.failed;
        row.message = e.toString();
        csvFailCount++;
      }

      csvDoneCount = i + 1;
      notifyListeners();
    }

    csvProcessing = false;
    csvActiveTrack = '';
    
    // Check if duplicates were found to prompt user dialog when screen is open
    if (csvDupCount > 0) {
      pendingDuplicates = csvEntries.where((e) => e.status == EntryStatus.duplicate).toList();
    } else {
      showSnack(
        'Processed all tracks! Successes: $csvSuccessCount, Failed: $csvFailCount',
        isError: csvFailCount > 0,
      );
    }
    notifyListeners();
  }

  // ── Process Forced Downloads ───────────────────────────────────────────────
  Future<void> startCsvForcedDownloads({
    required List<CsvEntryState> selectedDups,
    required String? selectedPlaylistId,
    required void Function(String msg, {bool isError}) showSnack,
  }) async {
    csvProcessing = true;
    pendingDuplicates.clear();
    notifyListeners();

    for (int i = 0; i < selectedDups.length; i++) {
      final row = selectedDups[i];
      row.status = EntryStatus.processing;
      row.message = 'Force downloading…';
      csvActiveTrack = '${row.entry.title} - ${row.entry.artist}';
      notifyListeners();

      // Resolve playlist ID
      String? targetPlaylistId;
      final rowPlaylistName = row.entry.playlistName.trim();
      if (rowPlaylistName.isNotEmpty) {
        targetPlaylistId = playlistCache[rowPlaylistName.toLowerCase()];
      } else {
        targetPlaylistId = selectedPlaylistId;
      }

      if (targetPlaylistId == null || targetPlaylistId.isEmpty) {
        row.status = EntryStatus.failed;
        row.message = 'No target playlist';
        csvFailCount++;
        csvDupCount--;
        notifyListeners();
        continue;
      }

      // Ingest New Song bypassing duplicate checks
      try {
        final result = await IngestionService.ingestSong(
          title: row.entry.title,
          artist: row.entry.artist,
          playlistId: targetPlaylistId,
          bypassDedup: true,
        );

        if (result.success) {
          row.status = EntryStatus.done;
          row.message = result.message;
          row.trackId = result.trackId;
          csvSuccessCount++;
          csvDupCount--;
        } else {
          row.status = EntryStatus.failed;
          row.message = result.errorMessage ?? 'Unknown error';
          csvFailCount++;
          csvDupCount--;
        }
      } catch (e) {
        row.status = EntryStatus.failed;
        row.message = e.toString();
        csvFailCount++;
        csvDupCount--;
      }
      notifyListeners();
    }

    csvProcessing = false;
    csvActiveTrack = '';
    notifyListeners();

    showSnack(
      'Forced download complete! Successes: $csvSuccessCount, Failed: $csvFailCount',
      isError: csvFailCount > 0,
    );
  }

  // ── Link Duplicate References ──────────────────────────────────────────────
  Future<void> linkDuplicateReferences({
    required List<CsvEntryState> duplicates,
    required String? selectedPlaylistId,
  }) async {
    if (selectedPlaylistId == null || selectedPlaylistId.isEmpty) return;
    for (final row in duplicates) {
      final trackId = row.trackId;
      if (trackId == null || trackId.isEmpty) continue;

      try {
        await FirebaseService.addTrackToPlaylist(selectedPlaylistId, trackId);
        row.message = 'Already in library (Linked)';
        row.status = EntryStatus.duplicate;
      } catch (e) {
        print('Error linking duplicate track $trackId: $e');
      }
    }
    notifyListeners();
  }

  // ── Clear Pending Duplicates ───────────────────────────────────────────────
  void clearPendingDuplicates() {
    pendingDuplicates.clear();
    notifyListeners();
  }

  // ── YouTube Search Ingestion ───────────────────────────────────────────────
  Future<void> runSearchIngest({
    required YouTubeSearchResult r,
    required String? selectedPlaylistId,
    required List<Song> cachedTracks,
    required void Function(String msg, {bool isError, IconData? icon}) showSnack,
    bool bypassDedup = false,
  }) async {
    // Exact duplicate precheck
    if (!bypassDedup) {
      final preCheckedId = libraryCheck[r.videoId];
      if (preCheckedId != null) {
        try {
          await FirebaseService.addTrackToPlaylist(selectedPlaylistId!, preCheckedId);
          doneVideoIds[r.videoId] = true;
          notifyListeners();
          showSnack('Song already in library — added to playlist',
              isError: true, icon: Icons.info_outline);
        } catch (e) {
          showSnack('Failed to add to playlist: $e', isError: true);
        }
        return;
      }
    }

    ingestingVideoIds.add(r.videoId);
    _simulateProgress(r.videoId);
    notifyListeners();

    try {
      final result = await IngestionService.ingestSong(
        title: r.title,
        artist: r.artist,
        playlistId: selectedPlaylistId,
        videoId: r.videoId,
        thumbnailUrl: r.thumbnailUrl,
        bypassDedup: bypassDedup,
      );

      ingestingVideoIds.remove(r.videoId);
      ingestionProgress.remove(r.videoId);

      if (result.success) {
        doneVideoIds[r.videoId] = result.isDuplicate;
        showSnack(
          result.isDuplicate ? 'Song already in library' : 'Added successfully',
          isError: result.isDuplicate,
          icon: result.isDuplicate ? Icons.info_outline : Icons.check_circle_outline,
        );
      } else {
        showSnack('Error: ${result.errorMessage}', isError: true);
      }
    } catch (e) {
      ingestingVideoIds.remove(r.videoId);
      ingestionProgress.remove(r.videoId);
      showSnack('Error: $e', isError: true);
    }
    notifyListeners();
  }

  // ── Pre-check search results against library in background ──────────────────
  Future<void> preCheckSearchResults(List<YouTubeSearchResult> results, List<Song> cachedTracks) async {
    checkingLibrary = true;
    notifyListeners();

    for (final r in results) {
      final localMatch = _findMatchingLibrarySong(r, cachedTracks);
      if (localMatch != null) {
        libraryCheck[r.videoId] = localMatch.id;
        notifyListeners();
        continue;
      }
      try {
        final existingId = await IngestionService.checkDuplicate(
          title: r.title,
          artist: r.artist,
          videoId: r.videoId,
        );
        libraryCheck[r.videoId] = existingId;
      } catch (_) {}
      notifyListeners();
    }

    checkingLibrary = false;
    notifyListeners();
  }

  // ── Search tab progress simulation ──────────────────────────────────────────
  void _simulateProgress(String videoId) {
    ingestionProgress[videoId] = 0.05;
    notifyListeners();
    Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!ingestingVideoIds.contains(videoId)) {
        timer.cancel();
        return;
      }
      final current = ingestionProgress[videoId] ?? 0.05;
      if (current < 0.92) {
        final step = (0.95 - current) * 0.08;
        ingestionProgress[videoId] = current + step;
        notifyListeners();
      } else {
        timer.cancel();
      }
    });
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = _min3(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost);
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[s2.length];
  }

  int _min3(int a, int b, int c) {
    int m = a < b ? a : b;
    return m < c ? m : c;
  }

  bool _isFuzzyDuplicate(String titleA, String titleB) {
    String cleanA = titleA.toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    String cleanB = titleB.toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleanA == cleanB) return true;
    if (cleanA.isEmpty || cleanB.isEmpty) return false;

    // 1. Levenshtein distance <= 2 (handles 1 or 2 letter typos)
    if (_levenshteinDistance(cleanA, cleanB) <= 2) {
      return true;
    }

    // 2. Word-based matching
    final wordsA = cleanA.split(' ').where((w) => w.isNotEmpty).toList();
    final wordsB = cleanB.split(' ').where((w) => w.isNotEmpty).toList();

    if (wordsA.isEmpty || wordsB.isEmpty) return false;

    // Check if first word matches (if first word length >= 4)
    if (wordsA[0].length >= 4 && wordsA[0] == wordsB[0]) {
      return true;
    }

    // Check if first 2 words match
    if (wordsA.length >= 2 && wordsB.length >= 2) {
      if (wordsA[0] == wordsB[0] && wordsA[1] == wordsB[1]) {
        return true;
      }
    }

    // Check if one title contains the other as a whole phrase (when both >= 4 chars)
    if (cleanA.length >= 4 && cleanB.length >= 4) {
      if (cleanA.contains(cleanB) || cleanB.contains(cleanA)) {
        return true;
      }
    }

    return false;
  }

  /// Returns a library song when the title matches via our smart fuzzy/relaxed logic.
  Song? _findExactDuplicate(String title, String artist, List<Song> existingSongs) {
    for (final song in existingSongs) {
      if (_isFuzzyDuplicate(title, song.title)) {
        return song;
      }
    }
    return null;
  }

  Song? _findMatchingLibrarySong(YouTubeSearchResult r, List<Song> library) {
    for (final song in library) {
      if (song.videoId.isNotEmpty && song.videoId == r.videoId) {
        return song;
      }
    }

    String cleanYtTitle = r.title.toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final cleanYtArtist = r.artist.toLowerCase()
        .replaceAll('official', '')
        .replaceAll('vevo', '')
        .replaceAll('topic', '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    for (final song in library) {
      final cleanSongTitle = song.title.toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
          
      final cleanSongArtist = song.artist.toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // Case A: Strict match (clean title and clean artist match)
      if (cleanSongTitle == cleanYtTitle && cleanSongArtist == cleanYtArtist) {
        return song;
      }

      // Case B: Relaxed title-only match (useful for YouTube video variations of same song)
      if (cleanSongTitle.length >= 4) {
        final pattern = RegExp('\\b$cleanSongTitle\\b');
        if (pattern.hasMatch(cleanYtTitle)) {
          return song;
        }
      }
    }
    return null;
  }

  Song? checkPotentialDuplicatePublic(YouTubeSearchResult r, List<Song> existingSongs) {
    return _findMatchingLibrarySong(r, existingSongs);
  }
}
