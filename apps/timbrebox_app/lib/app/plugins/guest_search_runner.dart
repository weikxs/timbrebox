import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'media_extraction_error.dart';
import 'platform_media_reference.dart';

abstract interface class GuestSearchRunner {
  Future<Map<String, Object?>> search(String platform, String query, int page);
  void cancel();
  void dispose();
}

/// Fixed metadata-only RPC. No browser, executable, script or cookie API.
final class NativeGuestSearchRunner implements GuestSearchRunner {
  NativeGuestSearchRunner({
    MethodChannel? channel,
    bool? enabled,
    DateTime Function()? clock,
  }) : _channel = channel ?? const MethodChannel('timbrebox/guest_search'),
       _enabled =
           enabled ??
           (kDebugMode &&
               !kIsWeb &&
               defaultTargetPlatform == TargetPlatform.macOS &&
               const bool.fromEnvironment('TIMBREBOX_GUEST_SEARCH_TEST')),
       _clock = clock ?? DateTime.now;

  final MethodChannel _channel;
  final bool _enabled;
  final DateTime Function() _clock;
  final _random = Random.secure();
  String? _active;
  bool _disposed = false;
  int _generation = 0;
  String? _key;
  DateTime? _created;
  final _entries = <Map<String, Object?>>[];
  final _pageBounds = <int, ({int start, int end})>{};
  bool _ended = false;
  static const _pageSize = 10;

  @override
  Future<Map<String, Object?>> search(
    String platform,
    String query,
    int page,
  ) async {
    if (!_enabled) {
      throw const MediaExtractionException(
        'platform_search_unavailable',
        'Official guest search is not enabled in this build.',
      );
    }
    if (_disposed) {
      throw const MediaExtractionException(
        'extractor_disposed',
        'Guest search is closed.',
      );
    }
    if (_active != null) {
      throw const MediaExtractionException(
        'extractor_busy',
        'Guest search is busy.',
      );
    }
    if (!{'tiktok', 'douyin'}.contains(platform) ||
        query.trim().isEmpty ||
        query.length > 200 ||
        query.contains(RegExp(r'[\x00-\x1f]')) ||
        page < 1 ||
        page > 5) {
      throw const MediaExtractionException(
        'invalid_media_request',
        'Invalid guest search request.',
      );
    }
    query = query.trim();
    final key = '$platform:$query';
    if (_key != key ||
        _created == null ||
        _clock().difference(_created!) >= const Duration(minutes: 2)) {
      _clear();
      _key = key;
      _created = _clock();
    }
    final saved = _pageBounds[page];
    final start =
        saved?.start ?? _pageBounds[page - 1]?.end ?? (page - 1) * _pageSize;
    // A verified partial cached page is still a page. Do not hide its rows
    // behind another browser session merely to fill ten slots.
    if (saved == null && !_ended && _entries.length <= start) {
      final id = List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final generation = _generation;
      _active = id;
      try {
        final response = await _channel
            .invokeMapMethod<String, Object?>('search', {
              'jobId': id,
              'platform': platform,
              'query': query,
              // One bounded metadata snapshot avoids keeping an idle browser
              // or reopening fresh anonymous sessions for every ten rows.
              'wanted': 50 - _entries.length,
              'seenIds': _entries
                  .map((item) => item['id'])
                  .toList(growable: false),
            })
            .timeout(const Duration(seconds: 22));
        if (_generation != generation || _disposed) {
          throw const MediaExtractionException(
            'extractor_cancelled',
            'Guest search was cancelled.',
          );
        }
        if (response == null ||
            response['data'] is! List ||
            response['isEnd'] is! bool) {
          _invalid();
        }
        final data = response['data'] as List;
        if (data.length > 50) _invalid();
        final fresh = <Map<String, Object?>>[];
        final seen = _entries.map((entry) => entry['id']).toSet();
        for (final entry in data) {
          if (entry is! Map) _invalid();
          final raw = _entry(platform, entry);
          if (seen.add(raw['id'])) fresh.add(raw);
        }
        if (_entries.length + fresh.length > 50) _invalid();
        _entries.addAll(fresh);
        _ended = response['isEnd'] as bool;
        if (!_ended && _entries.length <= start) {
          throw const MediaExtractionException(
            'guest_search_incomplete',
            'Official search did not return the requested page.',
          );
        }
      } on PlatformException catch (error) {
        const allowed = {
          'guest_search_busy',
          'guest_search_cancelled',
          'guest_search_unavailable',
          'guest_search_access_required',
          'guest_search_timeout',
          'guest_search_network_error',
          'search_access_required',
          'search_request_mismatch',
          'invalid_search_response',
          'search_limit_reached',
        };
        throw MediaExtractionException(
          allowed.contains(error.code) ? error.code : 'guest_search_failed',
          'Official guest search failed or requires user verification.',
        );
      } on MissingPluginException {
        throw const MediaExtractionException(
          'guest_search_unavailable',
          'Official guest search is unavailable on this platform.',
        );
      } on TimeoutException {
        unawaited(_cancelNative(id));
        throw const MediaExtractionException(
          'guest_search_timeout',
          'Official guest search timed out.',
        );
      } finally {
        if (_active == id) _active = null;
      }
    }
    final end = saved?.end ?? min(start + _pageSize, _entries.length);
    _pageBounds[page] = (start: start, end: end);
    return {
      'entries': _entries
          .skip(start)
          .take(max(0, end - start))
          .toList(growable: false),
      'isEnd': page == 5 || (_ended && end >= _entries.length),
    };
  }

  Map<String, Object?> _entry(String platform, Map item) {
    final address = item['url'];
    final title = item['title'];
    final artist = item['artist'];
    final duration = item['duration'];
    if (address is! String ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 2000 ||
        artist is! String ||
        artist.length > 1000 ||
        duration is! num ||
        !duration.isFinite ||
        duration <= 0 ||
        item['access'] != 'unverified' ||
        item['contentKind'] != 'video_audio') {
      _invalid();
    }
    final reference = PlatformMediaReference.parse(platform, address);
    if (reference.id == null || reference.id != item['id']) _invalid();
    return {
      'id': reference.id,
      'webpage_url': reference.url.toString(),
      'title': title,
      'artist': artist,
      'duration': duration,
    };
  }

  Never _invalid() => throw const MediaExtractionException(
    'invalid_search_response',
    'Invalid official search metadata.',
  );

  Future<void> _cancelNative(String id) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'jobId': id});
    } catch (_) {
      /* Already closed or unavailable. */
    }
  }

  void _clear() {
    _entries.clear();
    _pageBounds.clear();
    _key = null;
    _created = null;
    _ended = false;
  }

  @override
  void cancel() {
    _generation++;
    final active = _active;
    _active = null;
    // Invocation cleanup also calls cancel after success. Keep only the bounded
    // metadata snapshot then, so a new visitor page cannot reorder page 2.
    if (active != null) {
      _clear();
      unawaited(_cancelNative(active));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    _clear();
  }
}
