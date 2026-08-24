import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Backend base URL – Python backend running on laptop (cloud_functions/main.py)
// ─────────────────────────────────────────────────────────────────────────────
const String _kBackendBase = String.fromEnvironment('BACKEND_BASE_URL', defaultValue: 'http://10.0.2.2:8080');

class IngestionResult {
  final bool   success;
  final bool   isDuplicate;
  final String trackId;
  final String secureUrl;
  final String coverUrl;
  final String message;
  final String? errorMessage;

  const IngestionResult({
    required this.success,
    this.isDuplicate  = false,
    this.trackId      = '',
    this.secureUrl    = '',
    this.coverUrl     = '',
    this.message      = '',
    this.errorMessage,
  });

  factory IngestionResult.error(String msg) =>
      IngestionResult(success: false, errorMessage: msg, message: msg);
}

enum IngestionStep {
  checkingDuplicate,
  fetchingMetadata,
  searchingYouTube,
  downloadingAudio,
  fingerprinting,
  uploadingCover,
  uploadingAudio,
  savingToLibrary,
}

extension IngestionStepLabel on IngestionStep {
  String get label {
    switch (this) {
      case IngestionStep.checkingDuplicate:  return 'Checking library…';
      case IngestionStep.fetchingMetadata:   return 'Fetching metadata…';
      case IngestionStep.searchingYouTube:   return 'Finding on YouTube…';
      case IngestionStep.downloadingAudio:   return 'Downloading audio…';
      case IngestionStep.fingerprinting:     return 'Identifying track…';
      case IngestionStep.uploadingCover:     return 'Uploading artwork…';
      case IngestionStep.uploadingAudio:     return 'Uploading audio…';
      case IngestionStep.savingToLibrary:    return 'Saving to library…';
    }
  }
}

class CsvEntry {
  final String title;
  final String artist;
  final String playlistName;
  const CsvEntry({required this.title, required this.artist, this.playlistName = ''});
}

enum EntryStatus { pending, processing, done, failed, duplicate }

class CsvEntryState {
  final CsvEntry entry;
  EntryStatus    status;
  String         message;
  String?        trackId;

  CsvEntryState({required this.entry})
      : status  = EntryStatus.pending,
        message = '';
}

class IngestionService {
  static final _db = FirebaseFirestore.instance;

  static const _shazamKeys = [
    String.fromEnvironment('SHAZAM_KEY', defaultValue: "YOUR_SHAZAM_API_KEY"),
  ];

  // ── Backend URL (reads from SharedPreferences so user can override) ──────
  static Future<String> _getBase() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('backend_url') ?? _kBackendBase;
  }

  static Future<String> getActiveBackendUrl() => _getBase();

  static Future<void> updateBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', url);
  }

  static Future<bool> isBackendOnline() async {
    try {
      final base = await _getBase();
      final resp = await http
          .get(Uri.parse('$base/ping'))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Main ingestion pipeline ──────────────────────────────────────────────
  static Future<IngestionResult> ingestSong({
    required String title,
    required String artist,
    String? playlistId,
    String? videoId,
    String? thumbnailUrl,
    bool bypassDedup = false,
    void Function(IngestionStep step)? onProgress,
  }) async {
    try {
      onProgress?.call(IngestionStep.checkingDuplicate);
      final base = await _getBase();

      final body = <String, dynamic>{
        'title':  title,
        'artist': artist,
        if (playlistId != null && playlistId.isNotEmpty) 'playlist_id': playlistId,
        if (videoId    != null && videoId.isNotEmpty)    'video_id':    videoId,
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) 'thumbnail_url': thumbnailUrl,
        'bypass_dedup': bypassDedup,
      };

      final resp = await http
          .post(
            Uri.parse('$base/ingest'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 5));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        final isDup = data['duplicate'] == true;
        return IngestionResult(
          success:     true,
          isDuplicate: isDup,
          trackId:     data['track_id']   as String? ?? '',
          secureUrl:   data['secure_url'] as String? ?? '',
          coverUrl:    data['cover_url']  as String? ?? '',
          message:     isDup ? 'Already in library' : 'Added successfully!',
        );
      } else {
        return IngestionResult.error(data['error'] as String? ?? 'Backend error ${resp.statusCode}');
      }
    } on SocketException {
      return IngestionResult.error(
        'Cannot reach backend.\n\nMake sure the Python backend is running:\n  cd cloud_functions\n  python main.py',
      );
    } catch (e) {
      return IngestionResult.error('Ingestion failed: $e');
    }
  }

  // ── Preview – calls /preview endpoint which uses yt-dlp ─────────────────
  static Future<ap.Source?> getPreviewSource(String videoId, {String? title, String? artist}) async {
    // 1. Try iTunes 30-sec preview first (fast, no backend needed)
    if (title != null) {
      try {
        final cleanTitle = title
            .split('|').first
            .replaceAll(RegExp(r'\(.*?\)'), '')
            .replaceAll(RegExp(r'\[.*?\]'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        for (final q in [cleanTitle, if (artist != null) '$cleanTitle $artist']) {
          final resp = await http
              .get(Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(q)}&limit=3&media=music'))
              .timeout(const Duration(seconds: 6));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            for (final track in (data['results'] as List? ?? [])) {
              final url = track['previewUrl'] as String?;
              if (url != null && url.isNotEmpty) return ap.UrlSource(url);
            }
          }
        }
      } catch (_) {}
    }

    // 2. Fallback – ask backend for a yt-dlp stream URL
    try {
      final base = await _getBase();
      final resp = await http
          .get(Uri.parse('$base/preview?video_id=$videoId'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final url = (jsonDecode(resp.body) as Map)['url'] as String?;
        if (url != null && url.isNotEmpty) return ap.UrlSource(url);
      }
    } catch (_) {}

    return null;
  }

  // ── YouTube search (still via backend /search endpoint) ─────────────────
  static Future<List<YouTubeSearchResult>> searchYouTube(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final base = await _getBase();
      final resp = await http
          .get(Uri.parse('$base/search?q=${Uri.encodeComponent(query)}'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['results'] as List? ?? [];
        return list.map((e) => YouTubeSearchResult.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Delete a track ───────────────────────────────────────────────────────
  static Future<bool> deleteTrack(String trackId) async {
    try {
      final base = await _getBase();
      final resp = await http
          .post(
            Uri.parse('$base/delete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'track_id': trackId}),
          )
          .timeout(const Duration(seconds: 30));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Duplicate check (direct Firestore, still fast) ───────────────────────
  static Future<String?> checkDuplicate({required String title, required String artist, String? videoId}) async {
    try {
      if (videoId != null && videoId.isNotEmpty) {
        final snap = await _db
            .collection('tracks')
            .where('video_id', isEqualTo: videoId)
            .limit(1)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        if (snap.docs.isNotEmpty) return snap.docs.first.id;
      }
      final titleLc  = _normalize(title);
      final artistLc = _normalize(artist);
      final snap2 = await _db
          .collection('tracks')
          .where('title_lc',  isEqualTo: titleLc)
          .where('artist_lc', isEqualTo: artistLc)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (snap2.docs.isNotEmpty) return snap2.docs.first.id;
      return null;
    } catch (_) { return null; }
  }

  static String _normalize(String s) {
    s = s.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'[^\w\s]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  // ── CSV parsing ──────────────────────────────────────────────────────────
  static List<CsvEntry> parseCsv(String csvContent) {
    final lines = const LineSplitter().convert(csvContent.trim());
    if (lines.isEmpty) return [];
    final header = lines.first.toLowerCase();
    final cols = header.split(',').map((c) => c.trim().replaceAll('"', '')).toList();
    int titleIdx  = cols.indexWhere((c) => c.contains('title') || c.contains('song'));
    int artistIdx = cols.indexWhere((c) => c.contains('artist'));
    if (titleIdx  == -1) titleIdx  = 0;
    if (artistIdx == -1) artistIdx = 1;

    final entries = <CsvEntry>[];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final parts  = _splitCsvLine(line);
      if (parts.length <= titleIdx) continue;
      final title  = parts[titleIdx].trim().replaceAll('"', '');
      final artist = artistIdx < parts.length ? parts[artistIdx].trim().replaceAll('"', '') : '';
      if (title.isNotEmpty) entries.add(CsvEntry(title: title, artist: artist));
    }
    return entries;
  }

  static List<String> _splitCsvLine(String line) {
    final result  = <String>[];
    final current = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') { inQuotes = !inQuotes; }
      else if (ch == ',' && !inQuotes) { result.add(current.toString()); current.clear(); }
      else { current.write(ch); }
    }
    result.add(current.toString());
    return result;
  }

  static Future<List<({String id, String name})>> fetchUserPlaylists() =>
      FirebaseService.fetchUserPlaylists();
}

// ─────────────────────────────────────────────────────────────────────────────
//  YouTubeSearchResult
// ─────────────────────────────────────────────────────────────────────────────
class YouTubeSearchResult {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final int    durationSec;

  const YouTubeSearchResult({
    required this.videoId, required this.title, required this.artist,
    required this.thumbnailUrl, required this.durationSec,
  });

  factory YouTubeSearchResult.fromJson(Map<String, dynamic> j) => YouTubeSearchResult(
        videoId:      j['video_id']      ?? '',
        title:        j['title']         ?? '',
        artist:       j['artist']        ?? '',
        thumbnailUrl: j['thumbnail_url'] ?? '',
        durationSec:  (j['duration_sec'] as num?)?.toInt() ?? 0,
      );

  String get formattedDuration {
    final m = durationSec ~/ 60;
    final s = durationSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
