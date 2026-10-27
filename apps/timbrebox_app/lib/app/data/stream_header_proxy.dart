import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../net/egress_policy.dart';
import '../net/pooled_http.dart';
import '../state/control_request_guard.dart';

/// Loopback proxy that makes header-gated / range-limited remote audio playable
/// by media_kit.
///
/// Two problems it solves:
///   * media_kit (ffmpeg/libmpv) can't attach arbitrary request headers
///     (Referer / Cookie / User-Agent) that some sources require — the proxy
///     injects them per hop.
///   * googlevideo (YouTube) rejects an open `bytes=0-` and any window above
///     ~2 MB with `403`; for those the proxy pulls bounded ≤1 MB windows and
///     stitches them into one continuous response ("chunked" mode).
///
/// The player only ever talks to a well-behaved local server, so playback and
/// seeking work normally. Pure Dart — identical on every platform.
final class StreamHeaderProxy {
  StreamHeaderProxy({this.policy = const EgressPolicy()});

  /// Upstream connections (including every redirect hop) may only reach
  /// public hosts: some upstream URLs come from third-party plugins.
  final EgressPolicy policy;

  HttpServer? _server;

  /// One upstream client for the proxy's lifetime, so window after window
  /// (and seek after seek) reuses keep-alive connections. The policy is
  /// attached to it, so every new connection and redirect hop is vetted.
  HttpClient? _client;
  final _entries = <String, _ProxyTarget>{};
  final _random = Random.secure();

  /// Max bytes fetched per upstream hop in chunked mode.
  static const _window = 1024 * 1024;

  /// Registers [upstream] and returns a local URL the player can open. When
  /// [chunked] is true the proxy pulls bounded windows (needed for googlevideo);
  /// otherwise it relays each request straight through with [headers] injected.
  /// Max simultaneously-published targets. Only one stream plays at a time, so a
  /// small window is plenty; older tokens are evicted to bound memory.
  static const _maxEntries = 8;

  Future<Uri> publish(
    Uri upstream,
    Map<String, String> headers, {
    bool chunked = false,
  }) async {
    final server = await _ensureStarted();
    final token = _newToken();
    _entries[token] = _ProxyTarget(upstream, headers, chunked);
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first); // insertion order = oldest first
    }
    return Uri.parse('http://127.0.0.1:${server.port}/s/$token');
  }

  /// 128 random bits as hex: another local program cannot guess a published
  /// stream's URL and pull it (with the plugin's headers) through the proxy.
  String _newToken() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  Future<HttpServer> _ensureStarted() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    return _server = server;
  }

  Future<void> _handle(HttpRequest req) async {
    final host = req.headers.value(HttpHeaders.hostHeader);
    if (!isLoopbackHost(host, _server?.port ?? -1)) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    final token = req.uri.pathSegments.isEmpty ? '' : req.uri.pathSegments.last;
    final target = _entries[token];
    if (target == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final client = _upstreamClient();
    try {
      if (target.chunked) {
        final total = _totalBytes(target.upstream);
        final range = _parseRange(
          req.headers.value(HttpHeaders.rangeHeader),
          total,
        );
        await _streamWindows(req.response, client, target, range, total);
      } else {
        await _relay(req, client, target);
      }
    } catch (_) {
      // The player aborts hops when it seeks or stops → broken pipe here.
      try {
        req.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  HttpClient _upstreamClient() {
    final existing = _client;
    if (existing != null) return existing;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = pooledIdleTimeout;
    policy.attach(client);
    return _client = client;
  }

  /// Simple mode: forward one request to upstream with headers injected and the
  /// client's own Range mirrored; pipe the response back verbatim.
  Future<void> _relay(
    HttpRequest req,
    HttpClient client,
    _ProxyTarget target,
  ) async {
    final upstream = await client.getUrl(target.upstream);
    target.headers.forEach(upstream.headers.set);
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) upstream.headers.set(HttpHeaders.rangeHeader, range);
    final upstreamResponse = await upstream.close();
    req.response.statusCode = upstreamResponse.statusCode;
    _copy(upstreamResponse, req.response, HttpHeaders.contentTypeHeader);
    _copy(upstreamResponse, req.response, HttpHeaders.contentLengthHeader);
    _copy(upstreamResponse, req.response, HttpHeaders.contentRangeHeader);
    _copy(upstreamResponse, req.response, HttpHeaders.acceptRangesHeader);
    await upstreamResponse.pipe(req.response);
  }

  void _copy(HttpClientResponse from, HttpResponse to, String name) {
    final value = from.headers.value(name);
    if (value != null) to.headers.set(name, value);
  }

  /// Chunked mode: fulfil [range] by pulling ≤[_window] byte windows from
  /// upstream and writing them to [response] as one continuous body.
  Future<void> _streamWindows(
    HttpResponse response,
    HttpClient client,
    _ProxyTarget target,
    _Range range,
    int total,
  ) async {
    // libmpv drops the connection on every seek; once it is gone, stop
    // pulling windows instead of fetching the rest of the track for nobody.
    var playerGone = false;
    unawaited(
      response.done.then<void>((_) {}, onError: (_) {}).whenComplete(() {
        playerGone = true;
      }),
    );
    var cursor = range.start;
    var wroteHeaders = false;
    while (cursor <= range.end && !playerGone) {
      final windowEnd = (cursor + _window - 1) > range.end
          ? range.end
          : cursor + _window - 1;
      final upstream = await client.getUrl(target.upstream);
      target.headers.forEach(upstream.headers.set);
      upstream.headers.set(HttpHeaders.rangeHeader, 'bytes=$cursor-$windowEnd');
      final upstreamResponse = await upstream.close();
      if (upstreamResponse.statusCode != HttpStatus.partialContent &&
          upstreamResponse.statusCode != HttpStatus.ok) {
        if (!wroteHeaders) response.statusCode = upstreamResponse.statusCode;
        await upstreamResponse.drain<void>();
        return;
      }
      if (!wroteHeaders) {
        _writeChunkedHeaders(response, upstreamResponse, range, total);
        wroteHeaders = true;
      }
      await for (final chunk in upstreamResponse) {
        if (playerGone) return; // Cancelling drops the upstream connection.
        response.add(chunk);
      }
      // Backpressure: the next window is fetched only once this one has been
      // handed to the player's socket (this throws if the player hung up).
      await response.flush();
      cursor = windowEnd + 1;
    }
  }

  void _writeChunkedHeaders(
    HttpResponse response,
    HttpClientResponse upstream,
    _Range range,
    int total,
  ) {
    response.statusCode = range.isPartial
        ? HttpStatus.partialContent
        : HttpStatus.ok;
    final contentType = upstream.headers.value(HttpHeaders.contentTypeHeader);
    if (contentType != null) {
      response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (total > 0) {
      response.headers.set(
        HttpHeaders.contentLengthHeader,
        range.end - range.start + 1,
      );
      if (range.isPartial) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-${range.end}/$total',
        );
      }
    }
  }

  int _totalBytes(Uri upstream) {
    final clen = upstream.queryParameters['clen'];
    return clen == null ? -1 : (int.tryParse(clen) ?? -1);
  }

  _Range _parseRange(String? header, int total) {
    final lastByte = total > 0 ? total - 1 : (1 << 62);
    if (header == null || !header.startsWith('bytes=')) {
      return _Range(0, lastByte, isPartial: false);
    }
    final spec = header.substring('bytes='.length).split(',').first.trim();
    final dash = spec.indexOf('-');
    if (dash < 0) return _Range(0, lastByte, isPartial: false);
    final start = int.tryParse(spec.substring(0, dash)) ?? 0;
    final endText = spec.substring(dash + 1).trim();
    final end = endText.isEmpty
        ? lastByte
        : (int.tryParse(endText) ?? lastByte);
    return _Range(start, end < start ? lastByte : end, isPartial: true);
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _client?.close(force: true);
    _client = null;
    _entries.clear();
  }
}

final class _ProxyTarget {
  const _ProxyTarget(this.upstream, this.headers, this.chunked);

  final Uri upstream;
  final Map<String, String> headers;
  final bool chunked;
}

final class _Range {
  const _Range(this.start, this.end, {required this.isPartial});

  final int start;
  final int end;
  final bool isPartial;
}
