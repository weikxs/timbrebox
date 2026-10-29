import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:timbrebox_core/timbrebox_core.dart';

import 'catalog_track.dart';
import 'bounded_cache.dart';
import 'catalog_source.dart';
import 'source_config.dart';
import 'source_strings.dart';
import 'net/pooled_http.dart';

part 'bilibili_catalog_source.dart';
part 'page_video_catalog_source.dart';

/// A short-lived, process-local cookie jar. It never reads browser state and
/// is discarded with the source adapter.
final class MemoryCookieJar {
  final Map<String, String> _values = <String, String>{};

  String get header =>
      _values.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  void capture(HttpHeaders headers) {
    for (final value in headers[HttpHeaders.setCookieHeader] ?? const []) {
      final pair = value.split(';').first.split('=');
      if (pair.length == 2 && pair.first.isNotEmpty) {
        _values[pair.first] = pair.sublist(1).join('=').trim();
      }
    }
  }

  /// Injects a cookie the source obtained out of band (e.g. Bilibili's buvid
  /// from finger/spi), since the WAF blocks the first request before any
  /// Set-Cookie is returned.
  void set(String name, String value) => _values[name] = value;

  bool contains(String name) => _values.containsKey(name);

  void clear() => _values.clear();
}

typedef JsonPoster =
    Future<String> Function(
      Uri uri,
      String body,
      CancellationToken cancellation,
    );

typedef SourceReader =
    Future<String> Function(
      Uri uri,
      String? body,
      Map<String, String> headers,
      CancellationToken cancellation,
    );

/// Small HTTP boundary shared by the compiled-in adapters. One long-lived
/// client per adapter keeps connections alive across requests.
final class SourceHttpClient {
  SourceHttpClient({
    HttpClient Function()? clientFactory,
    SourceHttpPolicy? policy,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _policy = policy ?? BuiltInSourceConfig.http,
       _reader = null;

  SourceHttpClient.withReader(SourceReader reader, {SourceHttpPolicy? policy})
    : _clientFactory = HttpClient.new,
      _policy = policy ?? BuiltInSourceConfig.http,
      _reader = reader;

  final HttpClient Function() _clientFactory;
  final SourceHttpPolicy _policy;
  final SourceReader? _reader;
  late final HttpClient _client = _clientFactory()
    ..idleTimeout = pooledIdleTimeout;

  Future<String> get(
    Uri uri,
    CancellationToken cancellation, {
    Map<String, String> headers = const <String, String>{},
    MemoryCookieJar? cookies,
    int? maxResponseBytes,
  }) => _send(
    uri,
    cancellation,
    headers: headers,
    cookies: cookies,
    maxResponseBytes: maxResponseBytes,
  );

  Future<String> post(
    Uri uri,
    String body,
    CancellationToken cancellation, {
    Map<String, String> headers = const <String, String>{},
    MemoryCookieJar? cookies,
    int? maxResponseBytes,
  }) => _send(
    uri,
    cancellation,
    body: body,
    headers: headers,
    cookies: cookies,
    maxResponseBytes: maxResponseBytes,
  );

  Future<String> _send(
    Uri uri,
    CancellationToken cancellation, {
    String? body,
    required Map<String, String> headers,
    MemoryCookieJar? cookies,
    int? maxResponseBytes,
  }) async {
    if (_reader != null) {
      return _reader(uri, body, headers, cancellation);
    }
    try {
      return await _exchange(
        uri,
        cancellation,
        body: body,
        headers: headers,
        cookies: cookies,
        maxResponseBytes: maxResponseBytes,
      );
    } on TimeoutException {
      throw SourceException(
        SourceStrings.t('source.errTimeout'),
        retryable: true,
      );
    } on SocketException {
      throw SourceException(
        SourceStrings.t('source.errNetwork'),
        retryable: true,
      );
    }
  }

  Future<String> _exchange(
    Uri uri,
    CancellationToken cancellation, {
    String? body,
    required Map<String, String> headers,
    MemoryCookieJar? cookies,
    int? maxResponseBytes,
  }) async {
    HttpClientRequest? request;
    try {
      request = body == null
          ? await _client.getUrl(uri)
          : await _client.postUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/html',
      );
      request.headers.set(HttpHeaders.userAgentHeader, _policy.userAgent);
      headers.forEach(request.headers.set);
      if (cookies != null && cookies.header.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookies.header);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await responseWithin(request, _policy.timeout);
      cookies?.capture(response.headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SourceException(
          SourceStrings.t(
            'source.errUnavailable',
          ).replaceFirst('{code}', '${response.statusCode}'),
          retryable: response.statusCode >= 500,
          code: response.statusCode == 412
              ? 'source_access_restricted'
              : 'source_http_error',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        cancellation.throwIfCancelled();
        bytes.add(chunk);
        if (bytes.length > (maxResponseBytes ?? _policy.maxResponseBytes)) {
          throw SourceException(
            SourceStrings.t('source.errTooLarge'),
            retryable: true,
          );
        }
      }
      return utf8.decode(bytes.takeBytes());
    } catch (_) {
      // A failed exchange must not leave its pooled connection half-read.
      request?.abort();
      rethrow;
    }
  }
}

Duration? _duration(String value) {
  final parts = value.split(':').map(int.tryParse).toList();
  if (parts.any((part) => part == null) || parts.isEmpty) return null;
  var seconds = 0;
  for (final part in parts) {
    seconds = seconds * 60 + part!;
  }
  return Duration(seconds: seconds);
}

String _stripHtml(String value) => value.replaceAll(RegExp('<[^>]+>'), '');

DateTime? _expiry(Uri uri) {
  final raw = uri.queryParameters['expire'] ?? uri.queryParameters['expires'];
  final seconds = int.tryParse(raw ?? '');
  return seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

Iterable<Map<String, dynamic>> _jsonObjects(String text, String marker) sync* {
  var start = 0;
  while (true) {
    final markerAt = text.indexOf(marker, start);
    if (markerAt < 0) return;
    final objectStart = text.indexOf('{', markerAt + marker.length);
    if (objectStart < 0) return;
    final objectEnd = _balancedEnd(text, objectStart);
    if (objectEnd < 0) return;
    final raw = text.substring(objectStart, objectEnd + 1);
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) yield value;
    } on FormatException {
      // Ignore malformed fragments and continue searching the page.
    }
    start = objectEnd + 1;
  }
}

Object? _mapValue(Object? value, String key) =>
    value is Map ? value[key] : null;

const _quote = 0x22; // "
const _backslash = 0x5c; // \
const _openBrace = 0x7b; // {
const _closeBrace = 0x7d; // }

/// The index of the `}` closing the object that opens at [start], or -1.
/// Compares code units: indexing a String allocates a one-char String per
/// character, which adds up over a page of up to a megabyte.
int _balancedEnd(String text, int start) {
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var index = start; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (unit == _backslash) {
        escaped = true;
      } else if (unit == _quote) {
        quoted = false;
      }
      continue;
    }
    if (unit == _quote) {
      quoted = true;
    } else if (unit == _openBrace) {
      depth++;
    } else if (unit == _closeBrace && --depth == 0) {
      return index;
    }
  }
  return -1;
}
