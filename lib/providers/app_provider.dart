import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/caching_audio_source.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PlayerProvider
//
//  Key design: uses ConcatenatingAudioSource so ExoPlayer's native layer
//  handles track-to-track transitions. This works even when the Flutter Dart
//  isolate is suspended (screen locked, app minimised) because the native
//  media engine drives playback autonomously.
// ─────────────────────────────────────────────────────────────────────────────
class PlayerProvider extends ChangeNotifier {
  AudioPlayer? _player;
  ConcatenatingAudioSource? _playlist;

  Song?       _currentSong;
  List<Song>  _queue            = [];
  int         _queueIndex       = 0;
  String?     _errorMsg;
  bool        _isLoading        = false;
  String?     _currentPlaylistName;

  bool        get isPlaying          => _player?.playing ?? false;
  Song?       get currentSong        => _currentSong;
  List<Song>  get queue              => _queue;
  int         get queueIndex         => _queueIndex;
  String?     get errorMsg           => _errorMsg;
  bool        get isLoading          => _isLoading;
  bool        get hasCurrentSong     => _currentSong != null;
  AudioPlayer? get audioPlayer       => _player;
  String?     get currentPlaylistName => _currentPlaylistName;

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<PositionData>? get positionDataStream => _player == null
      ? null
      : Rx.combineLatest3<Duration, Duration, Duration, PositionData>(
          _player!.positionStream,
          _player!.bufferedPositionStream,
          _player!.durationStream.map((d) => d ?? Duration.zero),
          (pos, buf, dur) => PositionData(pos, buf, dur),
        );

  Stream<PlayerState>? get playerStateStream => _player?.playerStateStream;
  Stream<bool>?        get playingStream     => _player?.playingStream;
  Stream<Duration?>?   get durationStream    => _player?.durationStream;
  Stream<Duration>?    get positionStream    => _player?.positionStream;

  // ── Init ───────────────────────────────────────────────────────────────────

  PlayerProvider() {
    _initTempDir();
    _initPlayer();
  }

  Directory? _tempDir;
  String? _prefetchTriggeredSongId;

  Future<void> _initTempDir() async {
    try {
      _tempDir = await getTemporaryDirectory();
    } catch (e) {
      debugPrint('[Player] Error getting temp directory: $e');
    }
  }

  Future<void> _initPlayer() async {
    try {
      _player = AudioPlayer(
        audioLoadConfiguration: AudioLoadConfiguration(
          androidLoadControl: AndroidLoadControl(
            minBufferDuration: const Duration(seconds: 60),
            maxBufferDuration: const Duration(seconds: 90),
            bufferForPlaybackDuration: const Duration(seconds: 2),
            bufferForPlaybackAfterRebufferDuration: const Duration(seconds: 5),
          ),
          darwinLoadControl: DarwinLoadControl(
            automaticallyWaitsToMinimizeStalling: true,
            preferredForwardBufferDuration: const Duration(seconds: 90),
          ),
        ),
      );

      // Track the playlist sequence to restore state when app is reopened/resumed.
      _player!.sequenceStream.listen((sequence) {
        if (sequence == null || sequence.isEmpty) return;

        if (_queue.isEmpty) {
          final reconstructedQueue = <Song>[];
          for (var source in sequence) {
            final tag = source.tag;
            if (tag is MediaItem) {
              String streamUrl = '';
              if (source is UriAudioSource) {
                streamUrl = source.uri.toString();
              }
              reconstructedQueue.add(Song(
                id: tag.id,
                title: tag.title,
                artist: tag.artist ?? '',
                album: tag.album ?? '',
                imageUrl: tag.artUri?.toString() ?? '',
                streamUrl: streamUrl,
                durationMs: tag.duration?.inMilliseconds ?? 0,
              ));
            }
          }
          _queue = reconstructedQueue;
        }

        final index = _player!.currentIndex;
        if (index != null && _queue.isNotEmpty) {
          final clamped = index.clamp(0, _queue.length - 1);
          if (_queueIndex != clamped || _currentSong != _queue[clamped]) {
            _queueIndex  = clamped;
            _currentSong = _queue[clamped];
            _isLoading   = false;
          }
        }
        notifyListeners();
      });

      // Track when ExoPlayer advances to the next item in the native queue.
      // This fires even in the background (native callback → Dart stream).
      _player!.currentIndexStream.listen((index) {
        if (index == null || _queue.isEmpty) return;
        final clamped = index.clamp(0, _queue.length - 1);
        if (_queueIndex != clamped || _currentSong != _queue[clamped]) {
          _queueIndex  = clamped;
          _currentSong = _queue[clamped];
          _isLoading   = false;
          _prefetchTriggeredSongId = null;
          notifyListeners();
          _writeBackDuration(); // update Firestore if duration was unknown
        }
      });

      // Surface playback errors to the UI
      _player!.playbackEventStream.listen((_) {}, onError: (e, st) {
        debugPrint('[Player] Playback event error: $e');
        _errorMsg  = 'Playback error.';
        _isLoading = false;
        notifyListeners();
      });

      // Monitor playback position to trigger prefetch
      _player!.positionStream.listen((position) {
        _checkAndTriggerPrefetch(position);
      });

    } catch (e) {
      debugPrint('[Player] Init error: $e');
    }
    notifyListeners();
  }

  // ── Core playback API ──────────────────────────────────────────────────────

  /// Play [song], optionally within a [playlist].
  /// Builds a ConcatenatingAudioSource from the whole playlist so ExoPlayer
  /// can advance tracks natively without Dart being awake.
  Future<void> playSong(Song song, {List<Song>? playlist, String? playlistName}) async {
    if (_player == null) return;

    if (_tempDir == null) {
      try {
        _tempDir = await getTemporaryDirectory();
      } catch (e) {
        debugPrint('[Player] Temp directory error: $e');
      }
    }

    _prefetchTriggeredSongId = null;
    _errorMsg  = null;
    _isLoading = true;
    _currentSong = song;

    if (playlistName != null) {
      _currentPlaylistName = playlistName;
    } else if (playlist == null || playlist.isEmpty) {
      _currentPlaylistName = null;
    }

    final songs = (playlist != null && playlist.isNotEmpty) ? playlist : [song];
    _queue = songs;

    _queueIndex = songs.indexWhere((s) => s.id == song.id);
    if (_queueIndex < 0) _queueIndex = 0;

    notifyListeners();

    try {
      debugPrint('[Player] Building ConcatenatingAudioSource...');
      final sources = songs.asMap().entries.map((e) {
        final i = e.key;
        final s = e.value;
        return _songToSource(s, i);
      }).toList();
      _playlist = ConcatenatingAudioSource(children: sources);

      debugPrint('[Player] Calling setAudioSource (non-blocking)...');
      _player!.setAudioSource(
        _playlist!,
        initialIndex: _queueIndex,
        initialPosition: Duration.zero,
      ).catchError((e) {
        debugPrint('[Player] setAudioSource background error: $e');
        return null;
      });
      
      debugPrint('[Player] Calling play()...');
      _player!.play();

      // Track play count (fire-and-forget — non-critical)
      FirebaseService.incrementPlayCount(song.id).catchError((_) {});

      _isLoading = false;
      notifyListeners();
    } catch (e, st) {
      debugPrint('[Player] playSong error: $e\n$st');
      _errorMsg  = 'Could not load music.';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Convert a Song to an AudioSource.
  AudioSource _songToSource(Song song, int index) {
    final url = song.streamUrl.isNotEmpty ? song.streamUrl : 'https://example.com/empty.mp3';

    if (kIsWeb) {
      return AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(
          id: song.id.isNotEmpty ? song.id : song.title.hashCode.toString(),
          album: song.album.isNotEmpty ? song.album : song.artist,
          title: song.title,
          artist: song.artist,
          artUri: song.imageUrl.isNotEmpty ? Uri.parse(song.imageUrl) : null,
        ),
      );
    }

    final tempDir = _tempDir ?? Directory.systemTemp;
    final cacheFile = File('${tempDir.path}/song_cache_${song.id}.mp3');

    return CachingStreamAudioSource(
      song: song,
      url: url,
      cacheFile: cacheFile,
    );
  }

  /// Write back the resolved duration to Firestore when it was missing.
  void _writeBackDuration() {
    if (_currentSong == null || _player == null) return;
    final dur = _player!.duration;
    if (dur == null) return;
    final song = _currentSong!;
    if (song.durationMs == 0 || (song.durationMs - dur.inMilliseconds).abs() > 2000) {
      FirebaseFirestore.instance
          .collection('tracks')
          .doc(song.id)
          .update({'duration_ms': dur.inMilliseconds})
          .catchError((_) {});
    }
  }

  void togglePlayPause() {
    if (_player == null) return;
    _player!.playing ? _player!.pause() : _player!.play();
  }

  void seekTo(Duration position) => _player?.seek(position);

  Future<void> skipNext() async {
    if (_player == null || _queue.isEmpty) return;
    if (_isShuffled && _queue.length > 1) {
      int next = _queueIndex;
      while (next == _queueIndex) {
        next = DateTime.now().millisecond % _queue.length;
      }
      await _player!.seek(Duration.zero, index: next);
    } else {
      await _player!.seekToNext();
    }
  }

  Future<void> skipPrevious() async {
    if (_player == null || _queue.isEmpty) return;
    await _player!.seekToPrevious();
  }

  // ── Shuffle & Repeat ───────────────────────────────────────────────────────

  bool _isShuffled = false;
  bool _isRepeat   = false;
  bool get isShuffled => _isShuffled;
  bool get isRepeat   => _isRepeat;

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    _player?.setShuffleModeEnabled(_isShuffled);
    notifyListeners();
  }

  void toggleRepeat() {
    _isRepeat = !_isRepeat;
    _player?.setLoopMode(_isRepeat ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  void _checkAndTriggerPrefetch(Duration position) {
    if (_player == null || _queue.isEmpty) return;

    final duration = _player!.duration;
    if (duration == null || duration == Duration.zero) return;

    final nextIndex = _queueIndex + 1;
    if (nextIndex >= _queue.length) return;

    final nextSong = _queue[nextIndex];
    if (_prefetchTriggeredSongId == nextSong.id) return;

    final remaining = duration - position;
    if (remaining <= const Duration(seconds: 30)) {
      _prefetchTriggeredSongId = nextSong.id;
      _prefetchSong(nextSong);
    }
  }

  Future<void> _prefetchSong(Song song) async {
    final url = song.streamUrl;
    if (url.isEmpty) return;

    try {
      final tempDir = _tempDir ?? await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/song_cache_${song.id}.mp3');

      if (await cacheFile.exists()) {
        final len = await cacheFile.length();
        if (len > 1024 * 1024) {
          debugPrint('[Prefetch] Song ${song.title} is already cached ($len bytes). Skipping prefetch.');
          return;
        }
      }

      debugPrint('[Prefetch] Triggering background prefetch of first 1.5MB for song: ${song.title}');
      final tmpFile = File('${tempDir.path}/song_cache_${song.id}.mp3.tmp');

      final request = http.Request('GET', Uri.parse(url));
      request.headers['Range'] = 'bytes=0-1572863';

      final response = await http.Client().send(request);
      if (response.statusCode == 200 || response.statusCode == 206) {
        final sink = tmpFile.openWrite();
        await response.stream.pipe(sink);
        await sink.close();

        if (await tmpFile.exists()) {
          await tmpFile.rename(cacheFile.path);
          debugPrint('[Prefetch] Prefetch completed successfully for: ${song.title}');
        }
      } else {
        debugPrint('[Prefetch] Failed prefetch request for ${song.title}: status ${response.statusCode}');
      }
    } catch (e, st) {
      debugPrint('[Prefetch] Error prefetching ${song.title}: $e\n$st');
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  const PositionData(this.position, this.bufferedPosition, this.duration);

  double get progress => duration.inMilliseconds > 0
      ? position.inMilliseconds / duration.inMilliseconds
      : 0.0;

  String get positionFormatted  => _fmt(position);
  String get durationFormatted  => _fmt(duration);
  String get remainingFormatted => _fmt(duration - position);

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AuthProvider
// ─────────────────────────────────────────────────────────────────────────────
class AuthProvider extends ChangeNotifier {
  bool   _isLoggedIn = false;
  String _userName   = '';

  bool   get isLoggedIn => _isLoggedIn;
  String get userName   => _userName;

  AuthProvider() { _loadUser(); }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('is_registered') ?? false;
    _userName   = prefs.getString('user_name') ?? '';
    notifyListeners();
  }

  void setUserName(String name) async {
    _userName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    final user = FirebaseService.currentUser;
    if (user != null && !user.isAnonymous) FirebaseService.updateUserName(name);
    notifyListeners();
  }

  Future<void> login(String email, String name) async {
    _isLoggedIn = true;
    _userName   = name;
    try {
      await FirebaseService.loginWithEmail(email: email, password: 'password123');
    } catch (e) {
      debugPrint('[Auth] Login error: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_registered', true);
    await prefs.setString('user_name', name);
    notifyListeners();
  }

  Future<void> loginAsGuest() async {
    _isLoggedIn = true;
    try {
      await FirebaseService.signInAnonymously();
    } catch (e) {
      debugPrint('[Auth] Guest login error: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_registered', true);
    notifyListeners();
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _userName   = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_registered', false);
    await prefs.remove('user_name');
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NavigationProvider
// ─────────────────────────────────────────────────────────────────────────────
class NavigationProvider extends ChangeNotifier {
  int  _currentIndex     = 0;
  bool _isPlayerExpanded = false;

  int  get currentIndex     => _currentIndex;
  bool get isPlayerExpanded => _isPlayerExpanded;

  void setIndex(int i)          { _currentIndex     = i;     notifyListeners(); }
  void togglePlayer(bool value) { _isPlayerExpanded = value; notifyListeners(); }
}
