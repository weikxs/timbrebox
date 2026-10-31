import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'media_extraction_error.dart';

abstract interface class YouTubeKeywordSearch {
  Future<Map<String, Object?>> search(String query, int page);
  void cancel();
  void dispose();
}

/// The client owns all dependency HTTP and official continuation objects.
abstract interface class YouTubeKeywordClient {
  Future<List<Map<String, Object?>>> search(String query, int page);
  void close();
}

/// Original pure-Dart keyword path. Search metadata is NOT an access grant.
final class DartYouTubeKeywordSearch implements YouTubeKeywordSearch {
  DartYouTubeKeywordSearch({
    YouTubeKeywordClient Function()? createClient,
    this.timeout = const Duration(seconds: 20),
  }) : _createClient = createClient ?? _LibraryKeywordClient.new;
  final YouTubeKeywordClient Function() _createClient;
  final Duration timeout;
  YouTubeKeywordClient? _client;
  Completer<void>? _cancellation;
  bool _disposed = false;

  @override
  Future<Map<String, Object?>> search(String query, int page) async {
    if (_disposed) {
      throw const MediaExtractionException(
        'extractor_disposed',
        'YouTube search is closed.',
      );
    }
    if (query.trim().isEmpty ||
        query.length > 200 ||
        query.contains(RegExp(r'[\x00-\x1f]')) ||
        page < 1 ||
        page > 5) {
      throw const MediaExtractionException(
        'invalid_media_request',
        'Invalid YouTube search request.',
      );
    }
    if (_client != null) {
      throw const MediaExtractionException(
        'extractor_busy',
        'YouTube search is busy.',
      );
    }
    final client = _createClient();
    final cancellation = Completer<void>();
    _client = client;
    _cancellation = cancellation;
    try {
      final entries = await Future.any<List<Map<String, Object?>>>([
        client.search(query.trim(), page),
        cancellation.future.then(
          (_) => throw const MediaExtractionException(
            'extractor_cancelled',
            'YouTube search was cancelled.',
          ),
        ),
      ]).timeout(timeout);
      return {
        'entries': entries.take(50).toList(growable: false),
        'isEnd': entries.isEmpty || page == 5,
      };
    } on TimeoutException {
      throw const MediaExtractionException(
        'extractor_timeout',
        'YouTube keyword search timed out.',
      );
    } on MediaExtractionException {
      rethrow;
    } catch (_) {
      throw const MediaExtractionException(
        'extractor_failed',
        'YouTube keyword search failed.',
      );
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  @override
  void cancel() {
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

final class _LibraryKeywordClient implements YouTubeKeywordClient {
  final _youtube = yt.YoutubeExplode();
  bool _closed = false;
  @override
  Future<List<Map<String, Object?>>> search(String query, int page) async {
    yt.VideoSearchList? result = await _youtube.search.search(query);
    final videos = <yt.Video>[];
    final seen = <String>{};
    final start = (page - 1) * 10;
    for (var batch = 0; batch < 5 && result != null; batch++) {
      if (_closed) {
        throw const MediaExtractionException(
          'extractor_cancelled',
          'YouTube search was cancelled.',
        );
      }
      for (final video in result.take(50)) {
        if (seen.add(video.id.value)) videos.add(video);
        if (videos.length >= start + 10) break;
      }
      if (videos.length >= start + 10) break;
      result = await result.nextPage();
    }
    if (_closed) {
      throw const MediaExtractionException(
        'extractor_cancelled',
        'YouTube search was cancelled.',
      );
    }
    return [
      for (final video in videos.skip(start).take(10))
        {
          'id': video.id.value,
          'webpage_url': video.url,
          'title': video.title,
          'uploader': video.author,
          'duration': video.duration?.inMilliseconds == null
              ? null
              : video.duration!.inMilliseconds / 1000,
          'thumbnail': video.thumbnails.mediumResUrl,
          'is_live': video.isLive,
        },
    ];
  }

  @override
  void close() {
    if (!_closed) {
      _closed = true;
      _youtube.close();
    }
  }
}
