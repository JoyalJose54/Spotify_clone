import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/models.dart';

class CachingStreamAudioSource extends StreamAudioSource {
  final Song song;
  final String url;
  final File cacheFile;
  int? _totalLength;

  CachingStreamAudioSource({
    required this.song,
    required this.url,
    required this.cacheFile,
  }) : super(
          tag: MediaItem(
            id: song.id.isNotEmpty ? song.id : song.title.hashCode.toString(),
            album: song.album.isNotEmpty ? song.album : song.artist,
            title: song.title,
            artist: song.artist,
            artUri: song.imageUrl.isNotEmpty ? Uri.parse(song.imageUrl) : null,
          ),
        );

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;

    _totalLength ??= await _fetchTotalLength(url);

    final total = _totalLength ?? (song.durationMs > 0 ? (song.durationMs * 128 ~/ 8) : 8000000);
    final resolvedEnd = end ?? total;
    final contentLength = resolvedEnd - start;

    debugPrint('[CachingStreamAudioSource] Requesting range: $start - $resolvedEnd, contentLength: $contentLength, total: $total');

    return StreamAudioResponse(
      sourceLength: total,
      contentLength: contentLength,
      offset: start,
      stream: _createByteStream(start, resolvedEnd),
      contentType: 'audio/mpeg',
    );
  }

  Future<int?> _fetchTotalLength(String url) async {
    if (url.isEmpty) return null;
    try {
      final response = await http.head(Uri.parse(url));
      if (response.statusCode == 200 || response.statusCode == 206) {
        final lenStr = response.headers['content-length'];
        if (lenStr != null) {
          final len = int.tryParse(lenStr);
          if (len != null) return len;
        }
      }
    } catch (e) {
      debugPrint('[CachingStreamAudioSource] HEAD request failed: $e');
    }

    // Fallback: GET with Range 0-0 to retrieve content-range header
    try {
      final response = await http.get(Uri.parse(url), headers: {'Range': 'bytes=0-0'});
      final contentRange = response.headers['content-range'];
      if (contentRange != null) {
        // Formatted as: "bytes 0-0/1234567"
        final parts = contentRange.split('/');
        if (parts.length == 2) {
          final len = int.tryParse(parts[1].trim());
          if (len != null) return len;
        }
      }
    } catch (e) {
      debugPrint('[CachingStreamAudioSource] Content-Range GET failed: $e');
    }
    return null;
  }

  Stream<List<int>> _createByteStream(int start, int end) async* {
    final fileLength = cacheFile.existsSync() ? cacheFile.lengthSync() : 0;

    // 1. Read from local cache if start lies within the cached range
    if (start < fileLength) {
      final bytesToRead = min(end, fileLength) - start;
      if (bytesToRead > 0) {
        debugPrint('[CachingStreamAudioSource] Reading $bytesToRead bytes from local cache ($start to ${start + bytesToRead})');
        final fileStream = cacheFile.openRead(start, start + bytesToRead);
        await for (final chunk in fileStream) {
          yield chunk;
        }
      }
    }

    // 2. Fetch the remaining portion from the network if necessary
    final networkStart = max(start, fileLength);
    if (networkStart < end) {
      debugPrint('[CachingStreamAudioSource] Streaming $networkStart to $end from network ($url)');
      final uri = Uri.parse(url);
      final request = http.Request('GET', uri);
      request.headers['Range'] = 'bytes=$networkStart-${end - 1}';

      try {
        final response = await http.Client().send(request);
        if (response.statusCode == 200 || response.statusCode == 206) {
          IOSink? fileSink;
          // Only append to the cache file if we are sequentially adding to it
          if (networkStart == fileLength) {
            try {
              fileSink = cacheFile.openWrite(mode: FileMode.append);
            } catch (e) {
              debugPrint('[CachingStreamAudioSource] Failed to open cache file for writing: $e');
            }
          }

          try {
            await for (final chunk in response.stream) {
              if (fileSink != null) {
                try {
                  fileSink.add(chunk);
                } catch (e) {
                  debugPrint('[CachingStreamAudioSource] Error writing chunk to cache file: $e');
                  try {
                    await fileSink.close();
                  } catch (_) {}
                  fileSink = null; // Disconnect sink but keep streaming to player
                }
              }
              yield chunk;
            }
          } finally {
            if (fileSink != null) {
              try {
                await fileSink.close();
              } catch (_) {}
            }
          }
        } else {
          throw Exception('Failed network stream status: ${response.statusCode}');
        }
      } catch (e, st) {
        debugPrint('[CachingStreamAudioSource] Error streaming network data: $e\n$st');
        rethrow;
      }
    }
  }
}
