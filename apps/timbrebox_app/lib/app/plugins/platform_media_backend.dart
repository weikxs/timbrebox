import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'guest_search_runner.dart';

import 'media_extractor_process.dart';
import 'platform_media_data.dart';
import 'platform_media_reference.dart';
import 'media_stream_probe.dart';
import 'youtube_audio_manifest.dart';
import 'youtube_keyword_search.dart';

abstract interface class PlatformMediaBackend {
  Future<Map<String, Object?>> call(Map<String, Object?> request);
  void cancel();
  void dispose();
}

/// Fixed RPC operations, not a subprocess/shell API for plugins.
final class DesktopPlatformMediaBackend implements PlatformMediaBackend {
  DesktopPlatformMediaBackend({
    MediaExtractionRunner? runner,
    MediaStreamProbe? probe,
    GuestSearchRunner? guestSearch,
    YouTubeAudioManifest? youtubeAudio,
    YouTubeKeywordSearch? youtubeSearch,
    // Leave one second for the fixed plugin bridge's 25s async envelope.
    this.resolutionBudget = const Duration(seconds: 24),
  }) : _runner = runner ?? PinnedMediaExtractionRunner(),
       _probe = probe ?? GuardedMediaStreamProbe(),
       _guestSearch = guestSearch ?? NativeGuestSearchRunner(),
       _youtubeAudio =
           youtubeAudio ??
           (kDebugMode &&
                   const bool.fromEnvironment(
                     'TIMBREBOX_YOUTUBE_DART_AUDIO_TEST',
                   )
               ? DartYouTubeAudioManifest()
               : null),
       _youtubeSearch =
           youtubeSearch ??
           (kDebugMode &&
                   const bool.fromEnvironment(
                     'TIMBREBOX_YOUTUBE_DART_AUDIO_TEST',
                   )
               ? DartYouTubeKeywordSearch()
               : null);
  final Duration resolutionBudget;
  final MediaExtractionRunner _runner;
  final MediaStreamProbe _probe;
  final GuestSearchRunner _guestSearch;
  final YouTubeAudioManifest? _youtubeAudio;
  final YouTubeKeywordSearch? _youtubeSearch;
  bool _disposed = false;
  bool _busy = false;
  static const pageSize = 10;
  static const _baseArguments = [
    '--ignore-config',
    '--no-plugin-dirs',
    '--no-cache-dir',
    '--no-js-runtimes',
    '--no-remote-components',
    '--skip-download',
    '--no-warnings',
    '--socket-timeout',
    '10',
    '--retries',
    '0',
    '--extractor-retries',
    '0',
    '--dump-single-json',
  ];

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    if (_busy) {
      throw const MediaExtractionException(
        'extractor_busy',
        'Media resolution is busy.',
      );
    }
    _busy = true;
    try {
      return await _dispatch(request);
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, Object?>> _dispatch(Map<String, Object?> request) async {
    if (_disposed) {
      throw const MediaExtractionException(
        'extractor_disposed',
        'Media extraction is closed.',
      );
    }
    final platform = request['platform'];
    final operation = request['operation'];
    if (platform is! String ||
        !PlatformMediaReference.platforms.contains(platform)) {
      throw const MediaExtractionException(
        'invalid_media_request',
        'The media platform is not supported.',
      );
    }
    if (operation == 'search') return _search(platform, request);
    if (operation == 'resolve') return _resolve(platform, request);
    throw const MediaExtractionException(
      'invalid_media_request',
      'This media operation is not supported.',
    );
  }

  Future<Map> _run(List<String> arguments) async {
    final text = await _runner.run([..._baseArguments, ...arguments]);
    if (_disposed) {
      throw const MediaExtractionException(
        'extractor_cancelled',
        'Media extraction was cancelled.',
      );
    }
    try {
      final value = jsonDecode(text);
      if (value is Map) return value;
    } catch (_) {
      // Do not return raw output: it can contain signed URLs or server details.
    }
    throw const MediaExtractionException(
      'extractor_invalid_data',
      'The media backend returned invalid data.',
    );
  }

  Future<Map<String, Object?>> _search(
    String platform,
    Map<String, Object?> request,
  ) async {
    final query = request['query'];
    final page = request['page'];
    if (query is! String ||
        query.trim().isEmpty ||
        query.length > 200 ||
        query.contains(RegExp(r'[\x00-\x1f]')) ||
        page is! int ||
        page < 1 ||
        page > 5) {
      throw const MediaExtractionException(
        'invalid_media_request',
        'The search query or page is invalid.',
      );
    }
    final prefix = switch (platform) {
      'youtube' => 'ytsearch',
      'bilibili' => 'bilisearch',
      _ => null,
    };
    final originalSearch = platform == 'youtube' ? _youtubeSearch : null;
    final raw = originalSearch != null
        ? await originalSearch.search(query.trim(), page)
        : prefix == null
        ? await _guestSearch.search(platform, query.trim(), page)
        : await _run([
            '--flat-playlist',
            '--playlist-start',
            '${(page - 1) * pageSize + 1}',
            '--playlist-end',
            '${page * pageSize}',
            '--',
            '$prefix${page * pageSize}:${query.trim()}',
          ]);
    final entries = raw['entries'];
    if (entries is! List) {
      throw const MediaExtractionException(
        'extractor_invalid_data',
        'The platform returned no search result list.',
      );
    }
    final items = <Map<String, Object?>>[];
    final ids = <String>{};
    var excluded = 0;
    for (final entry in entries.take(pageSize)) {
      if (entry is! Map) continue;
      if (mediaAccess(entry) == MediaAccess.excluded) {
        excluded++;
        continue;
      }
      try {
        final item = mediaItem(platform, entry);
        if (ids.add('${item['id']}:${item['part'] ?? ''}')) items.add(item);
      } on MediaExtractionException {
        // Malformed or cross-platform results must not enter the library.
      }
    }
    if (entries.isNotEmpty && items.isEmpty && excluded == 0) {
      throw const MediaExtractionException(
        'extractor_invalid_data',
        'The platform search entries could not be interpreted.',
      );
    }
    return {
      'isEnd': raw['isEnd'] is bool
          ? raw['isEnd']
          : entries.length < pageSize || page == 5,
      'data': items,
      'excludedCount': excluded,
    };
  }

  Future<Map<String, Object?>> _resolve(
    String platform,
    Map<String, Object?> request,
  ) async {
    final link = request['url'];
    final item = request['item'];
    final PlatformMediaReference reference;
    if (link is String) {
      reference = PlatformMediaReference.parse(platform, link);
    } else if (item is Map) {
      reference = PlatformMediaReference.fromItem(platform, item);
    } else {
      throw const MediaExtractionException(
        'invalid_media_request',
        'A stable media item or supported link is required.',
      );
    }
    final clock = Stopwatch()..start();
    var refreshed = false;
    while (true) {
      final raw = await _withinResolutionBudget(
        clock,
        () => _run(['--no-playlist', '--', reference.url.toString()]),
      );
      // Every refresh independently rechecks the exact identity and access;
      // never edit signatures or reuse saved entitlement/media hints.
      final summary = mediaItem(platform, raw, expected: reference);
      requireMediaAccess(raw, platform: platform);
      final originalAudio = platform == 'youtube' ? _youtubeAudio : null;
      final List<Map<String, Object?>> candidates;
      if (originalAudio == null) {
        candidates = playableMediaCandidates(
          raw,
          platform: platform,
          allowMuxedAudio: true,
        );
      } else {
        final duration = raw['duration'];
        if (duration is! num || !duration.isFinite || duration <= 0) {
          throw const MediaExtractionException(
            'content_unverified',
            'Full duration could not be verified.',
          );
        }
        candidates = await _withinResolutionBudget(
          clock,
          () => originalAudio.resolve(reference.id!, duration),
        );
      }
      try {
        final media = await _withinResolutionBudget(
          clock,
          () => _probe.select(candidates),
        );
        if (originalAudio != null && media['boundedRanges'] != true) {
          throw const MediaExtractionException(
            'media_unavailable',
            'The original audio stream did not provide a verified byte range.',
          );
        }
        return {'item': summary, 'media': media};
      } on MediaExtractionException catch (error) {
        if (!refreshed &&
            error.code == 'media_access_denied' &&
            clock.elapsed < resolutionBudget ~/ 2) {
          // A single normal official re-resolution can replace an unusable
          // transient CDN address. No retry for metadata/auth/rights refusal.
          refreshed = true;
          continue;
        }
        rethrow;
      }
    }
  }

  Future<T> _withinResolutionBudget<T>(
    Stopwatch clock,
    Future<T> Function() task,
  ) {
    Never timeout() {
      _runner.cancel();
      _probe.cancel();
      _youtubeAudio?.cancel();
      throw const MediaExtractionException(
        'extractor_timeout',
        'Media resolution timed out.',
      );
    }

    final remaining = resolutionBudget - clock.elapsed;
    if (remaining <= Duration.zero) timeout();
    return task().timeout(remaining, onTimeout: timeout);
  }

  @override
  void cancel() {
    _runner.cancel();
    _probe.cancel();
    _guestSearch.cancel();
    _youtubeAudio?.cancel();
    _youtubeSearch?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _runner.dispose();
    _probe.dispose();
    _guestSearch.dispose();
    _youtubeAudio?.dispose();
    _youtubeSearch?.dispose();
  }
}
