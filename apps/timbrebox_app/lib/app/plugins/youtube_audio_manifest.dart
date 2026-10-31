import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'media_extraction_error.dart';

abstract interface class YouTubeAudioManifest {
  Future<List<Map<String, Object?>>> resolve(String videoId, num duration);
  void cancel();
  void dispose();
}

/// Narrow boundary around the pinned dependency, independently testable offline.
abstract interface class YouTubeAudioClient {
  Future<List<YouTubeAudioStream>> manifest(String videoId);
  void close();
}

final class YouTubeAudioStream {
  const YouTubeAudioStream({
    required this.videoId,
    required this.url,
    required this.container,
    required this.bitrate,
    required this.size,
  });
  final String videoId;
  final Uri url;
  final String container;
  final int bitrate;
  final int size;
}

/// Restores the original independent audio-manifest path, not its old loose
/// access policy. The caller MUST verify fresh public/full access beforehand.
final class DartYouTubeAudioManifest implements YouTubeAudioManifest {
  DartYouTubeAudioManifest({
    YouTubeAudioClient Function()? createClient,
    this.timeout = const Duration(seconds: 20),
  }) : _createClient = createClient ?? _LibraryAudioClient.new;
  final YouTubeAudioClient Function() _createClient;
  final Duration timeout;
  YouTubeAudioClient? _client;
  Completer<void>? _cancellation;
  var _epoch = 0;
  var _disposed = false;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  @override
  Future<List<Map<String, Object?>>> resolve(
    String videoId,
    num duration,
  ) async {
    if (_disposed) {
      throw const MediaExtractionException(
        'extractor_disposed',
        'Audio manifest service is closed.',
      );
    }
    if (_client != null) {
      throw const MediaExtractionException(
        'extractor_busy',
        'Audio manifest resolution is busy.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) ||
        !duration.isFinite ||
        duration <= 0) {
      throw const MediaExtractionException(
        'invalid_media_request',
        'A verified video identity and duration are required.',
      );
    }
    final epoch = _epoch;
    final client = _createClient();
    _client = client;
    final cancellation = Completer<void>();
    _cancellation = cancellation;
    try {
      final streams = await Future.any<List<YouTubeAudioStream>>([
        client.manifest(videoId),
        cancellation.future.then(
          (_) => throw const MediaExtractionException(
            'extractor_cancelled',
            'Audio manifest resolution was cancelled.',
          ),
        ),
      ]).timeout(timeout);
      _check(epoch);
      final accepted = <YouTubeAudioStream>[];
      for (final stream in streams.take(64)) {
        final uri = stream.url;
        final durationText = uri.queryParameters['dur'];
        final actualDuration = durationText == null
            ? null
            : double.tryParse(durationText);
        final tolerance = duration * .02 > 2 ? duration * .02 : 2;
        if (stream.videoId != videoId ||
            uri.scheme != 'https' ||
            uri.userInfo.isNotEmpty ||
            (uri.port != 443) ||
            !(uri.host == 'googlevideo.com' ||
                uri.host.endsWith('.googlevideo.com')) ||
            !{'mp4', 'webm'}.contains(stream.container) ||
            stream.bitrate <= 0 ||
            stream.bitrate > 320000 ||
            stream.size <= 0 ||
            stream.size >= (1 << 40) ||
            (durationText != null &&
                (actualDuration == null ||
                    !actualDuration.isFinite ||
                    actualDuration <= 0 ||
                    (actualDuration - duration).abs() > tolerance))) {
          continue;
        }
        accepted.add(stream);
      }
      accepted.sort((a, b) {
        final aAac = a.container == 'mp4', bAac = b.container == 'mp4';
        if (aAac != bAac) return aAac ? -1 : 1;
        return b.bitrate.compareTo(a.bitrate);
      });
      if (accepted.isEmpty) {
        throw const MediaExtractionException(
          'media_unavailable',
          'No matching independent full audio stream was returned.',
        );
      }
      return [
        for (final stream in accepted)
          {
            'url': stream.url.toString(),
            'headers': <String, String>{'user-agent': userAgent},
            'mimeType': stream.container == 'mp4' ? 'audio/mp4' : 'audio/webm',
            'bitrateKbps': stream.bitrate / 1000,
          },
      ];
    } on TimeoutException {
      throw const MediaExtractionException(
        'extractor_timeout',
        'Audio manifest resolution timed out.',
      );
    } on MediaExtractionException {
      rethrow;
    } catch (_) {
      _check(epoch);
      throw const MediaExtractionException(
        'extractor_failed',
        'The original audio manifest could not be resolved.',
      );
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  void _check(int epoch) {
    if (_disposed || epoch != _epoch) {
      throw const MediaExtractionException(
        'extractor_cancelled',
        'Audio manifest resolution was cancelled.',
      );
    }
  }

  @override
  void cancel() {
    _epoch++;
    final cancellation = _cancellation;
    _cancellation = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }
}

final class _LibraryAudioClient implements YouTubeAudioClient {
  final _youtube = yt.YoutubeExplode();
  @override
  Future<List<YouTubeAudioStream>> manifest(String videoId) async {
    // Access/identity were already verified by the caller. Avoid a redundant
    // watch-page read; the dependency still fetches it if decoding requires it.
    final manifest = await _youtube.videos.streamsClient.getManifest(
      videoId,
      requireWatchPage: false,
    );
    return [
      for (final audio in manifest.audioOnly)
        YouTubeAudioStream(
          videoId: audio.videoId.value,
          url: audio.url,
          container: audio.container.name,
          bitrate: audio.bitrate.bitsPerSecond,
          size: audio.size.totalBytes,
        ),
    ];
  }

  @override
  void close() => _youtube.close();
}
