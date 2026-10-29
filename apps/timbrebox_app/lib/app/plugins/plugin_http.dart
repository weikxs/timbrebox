import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../design/app_strings.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';

/// The single privileged capability handed to plugins: HTTP. Every plugin
/// network call flows through here, so egress policy (scheme, private-IP
/// blocking on every redirect hop, size/timeout caps) is enforced in one place.
final class PluginHttpClient {
  PluginHttpClient({
    this.maxBytes = 8 * 1024 * 1024,
    this.policy = const EgressPolicy(),
  });

  final int maxBytes;
  final EgressPolicy policy;

  /// One client per plugin, so its requests reuse keep-alive connections. The
  /// policy is attached to it, so every new connection (each redirect hop
  /// included) is still vetted.
  HttpClient? _client;

  HttpClient get _pooled => _client ??= _newClient();

  HttpClient _newClient() {
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..idleTimeout = pooledIdleTimeout;
    policy.attach(client);
    return client;
  }

  /// Drops the pooled connections; a later [send] opens a new client.
  void close() {
    _client?.close(force: true);
    _client = null;
  }

  static const _timeout = Duration(seconds: 20);
  static const _maxRedirects = 4;

  /// Performs one request described by [request] (already JSON-decoded from the
  /// sandbox) and returns `{status, headers, data}` where `data` is the body
  /// text. Throws on policy violation or transport error. Redirects are followed
  /// manually so each hop is re-validated against the egress policy (blocks
  /// redirect-to-internal SSRF).
  Future<Map<String, Object?>> send(Map<String, Object?> request) async {
    final rawUrl = (request['url'] as String?)?.trim() ?? '';
    final start = Uri.tryParse(rawUrl);
    if (start == null || !start.hasScheme) {
      throw PluginHttpException(AppStrings.t('plugin.http.invalidUrl'));
    }
    var method = ((request['method'] as String?) ?? 'GET').toUpperCase();
    final headers = _stringMap(request['headers']);
    final params = _stringMap(request['params']);
    var uri = params.isEmpty
        ? start
        : start.replace(queryParameters: {...start.queryParameters, ...params});
    Object? body = request['data'];

    final client = _pooled;
    HttpClientRequest? httpRequest;
    try {
      for (var redirect = 0; ; redirect++) {
        await _enforcePolicy(uri);
        httpRequest = await client.openUrl(method, uri);
        httpRequest.followRedirects = false;
        headers.forEach(httpRequest.headers.set);
        if (body != null && method != 'GET' && method != 'HEAD') {
          httpRequest.add(
            utf8.encode(body is String ? body : jsonEncode(body)),
          );
        }
        final response = await responseWithin(httpRequest, _timeout);
        if (response.isRedirect && redirect >= _maxRedirects) {
          await response.drain<void>();
          throw PluginHttpException(
            AppStrings.t('plugin.http.tooManyRedirects'),
          );
        }
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) {
            throw PluginHttpException(
              AppStrings.t('plugin.http.redirectMissing'),
            );
          }
          uri = uri.resolve(location);
          method = 'GET'; // Follow redirects as GET, drop the body.
          body = null;
          continue;
        }
        final bytes = await _readCapped(response);
        return {
          'status': response.statusCode,
          'headers': _responseHeaders(response),
          'data': utf8.decode(bytes, allowMalformed: true),
        };
      }
    } catch (_) {
      // A failed exchange must not leave its pooled connection half-read.
      httpRequest?.abort();
      rethrow;
    }
  }

  /// Checks [uri] up front so the plugin gets a clear message; [policy] is
  /// also attached to the client, which re-checks the address it connects to.
  Future<void> _enforcePolicy(Uri uri) async {
    try {
      await policy.vet(uri);
    } on EgressDeniedException catch (error) {
      throw PluginHttpException(error.message);
    }
  }

  Future<Uint8List> _readCapped(HttpClientResponse response) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(_timeout)) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        throw PluginHttpException(AppStrings.t('plugin.http.tooLarge'));
      }
    }
    return bytes.takeBytes();
  }

  Map<String, String> _responseHeaders(HttpClientResponse response) {
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return headers;
  }

  Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    };
  }
}

class PluginHttpException implements Exception {
  const PluginHttpException(this.message);
  final String message;
  @override
  String toString() => message;
}
