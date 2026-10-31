import 'dart:async';
import 'dart:io';

import 'package:timbrebox_sources/timbrebox_sources.dart';

import 'media_extraction_error.dart';

abstract interface class MediaStreamProbe {
  Future<Map<String, Object?>> select(List<Map<String, Object?>> candidates);
  void cancel();
  void dispose();
}

/// Validate actual bytes, after access checks, through the same egress rules as
/// playback. Higher nominal quality does not prove a CDN grants guest access.
final class GuardedMediaStreamProbe implements MediaStreamProbe {
  GuardedMediaStreamProbe({
    this.policy = const EgressPolicy(),
    this.totalBudget = const Duration(seconds: 10),
    this.attemptBudget = const Duration(seconds: 2),
  }) : assert(totalBudget > Duration.zero),
       assert(attemptBudget > Duration.zero);
  final EgressPolicy policy;
  final Duration totalBudget;
  final Duration attemptBudget;
  HttpClient? _client;
  var _epoch = 0;
  var _disposed = false;

  HttpClient get _http {
    if (_disposed) _cancelled();
    final existing = _client;
    if (existing != null) return existing;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    policy.attach(client);
    return _client = client;
  }

  Never _cancelled() => throw const MediaExtractionException(
    'extractor_cancelled',
    'Media verification was cancelled.',
  );
  void _check(int epoch) {
    if (_disposed || epoch != _epoch) _cancelled();
  }

  @override
  Future<Map<String, Object?>> select(
    List<Map<String, Object?>> candidates,
  ) async {
    final epoch = _epoch;
    final unique = <String, Map<String, Object?>>{};
    for (final candidate in candidates) {
      unique.putIfAbsent('${candidate['url']}', () => candidate);
    }
    final all = unique.values.toList();
    final audio = all.where((m) => m['audioOnlyPlayback'] != true).toList();
    final video = all.where((m) => m['audioOnlyPlayback'] == true).toList();
    // Keep audio first, including the low-bandwidth guest fallback. A video
    // container is only attempted after that ladder, never ahead of it.
    final attempts = [
      ...audio.take(5),
      if (audio.length > 5) audio.last,
      if (video.isNotEmpty) video.first,
    ];
    final clock = Stopwatch()..start();
    var started = 0;
    var denied = 0;
    try {
      for (var index = 0; index < attempts.length; index++) {
        _check(epoch);
        final remaining = totalBudget - clock.elapsed;
        if (remaining <= Duration.zero) break;
        // Slow nominal-best requests must not consume the entire budget before
        // the low-bandwidth audio fallback is tried. Fast ladders keep quality.
        final fallbackIndex = audio.isEmpty ? -1 : attempts.indexOf(audio.last);
        if (fallbackIndex > index && remaining <= attemptBudget * 2) {
          attempts.insert(index, attempts.removeAt(fallbackIndex));
        }
        final candidate = attempts[index];
        final attempt = _ProbeAttempt();
        started++;
        try {
          final limit = remaining < attemptBudget ? remaining : attemptBudget;
          final verified = await _read(
            candidate,
            epoch,
            attempt,
          ).timeout(limit);
          _check(epoch);
          if (verified != null) return verified;
          if (attempt.status == 401 || attempt.status == 403) denied++;
        } on TimeoutException {
          _client?.close(force: true);
          _client = null;
        } on MediaExtractionException {
          rethrow;
        } catch (_) {
          _check(epoch); // No URL, headers or response bodies in errors.
        }
      }
      if (denied > 0 && denied == started) {
        throw const MediaExtractionException(
          'media_access_denied',
          'The platform refused the anonymous media requests.',
        );
      }
      throw const MediaExtractionException(
        'media_unavailable',
        'No verified anonymous audio stream is currently readable.',
      );
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  }

  Future<Map<String, Object?>?> _read(
    Map<String, Object?> media,
    int epoch,
    _ProbeAttempt attempt,
  ) async {
    final initial = Uri.tryParse('${media['url'] ?? ''}');
    if (initial == null || initial.userInfo.isNotEmpty) return null;
    Uri uri = initial;
    final headers = Map<String, String>.from(
      media['headers'] as Map? ?? const {},
    );
    final client = _http;
    HttpClientRequest? request;
    try {
      for (var hop = 0; hop <= 3; hop++) {
        _check(epoch);
        if (uri.userInfo.isNotEmpty) return null;
        await policy.vet(uri);
        request = await client.getUrl(uri);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
        final response = await request.close();
        attempt.status = response.statusCode;
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || hop == 3) return null;
          final next = uri.resolve(location);
          if (next.scheme != uri.scheme ||
              next.host != uri.host ||
              next.port != uri.port) {
            headers.removeWhere(
              (name, _) => !{
                'user-agent',
                'accept',
                'accept-language',
              }.contains(name.toLowerCase()),
            );
          }
          request.abort();
          uri = next;
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          return null;
        }
        final prefix = <int>[];
        await for (final chunk in response) {
          _check(epoch);
          prefix.addAll(chunk.take(1024 - prefix.length));
          if (prefix.length >= 1024) break;
        }
        if (!_audioContainer(prefix)) return null;
        final range =
            response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
        final total = int.tryParse(
          RegExp(r'^bytes 0-\d+/(\d+)$').firstMatch(range)?.group(1) ?? '',
        );
        return {
          ...media,
          'url': uri.toString(),
          'headers': headers,
          if (response.statusCode == 206 &&
              total != null &&
              total > 0 &&
              total < (1 << 40)) ...{
            'boundedRanges': true,
            'contentLength': total,
          },
        };
      }
      return null;
    } finally {
      request?.abort();
    }
  }

  static bool _audioContainer(List<int> bytes) {
    bool at(int offset, List<int> signature) =>
        bytes.length >= offset + signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[offset + i] == signature[i],
        ).every((v) => v);
    return at(4, [0x66, 0x74, 0x79, 0x70]) || // ISO BMFF / MP4
        at(0, [0x1a, 0x45, 0xdf, 0xa3]) || // WebM
        at(0, [0x49, 0x44, 0x33]) ||
        at(0, [0x4f, 0x67, 0x67, 0x53]) ||
        at(0, [0x66, 0x4c, 0x61, 0x43]) ||
        bytes.length > 1 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
  }

  @override
  void cancel() {
    _epoch++;
    _client?.close(force: true);
    _client = null;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }
}

final class _ProbeAttempt {
  int? status;
}
