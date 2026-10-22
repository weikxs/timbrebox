import 'dart:convert';
import 'dart:io';

import '../design/app_strings.dart';

/// The single privileged capability handed to plugins: HTTP. Every plugin
/// network call flows through here, so egress policy (scheme, private-IP
/// blocking on every redirect hop, size/timeout caps) is enforced in one place.
final class PluginHttpClient {
  PluginHttpClient({this.maxBytes = 8 * 1024 * 1024});

  final int maxBytes;

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
        : start.replace(
            queryParameters: {...start.queryParameters, ...params},
          );
    Object? body = request['data'];

    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      for (var redirect = 0; ; redirect++) {
        _enforcePolicy(uri);
        final httpRequest = await client.openUrl(method, uri);
        httpRequest.followRedirects = false;
        headers.forEach(httpRequest.headers.set);
        if (body != null && method != 'GET' && method != 'HEAD') {
          httpRequest.add(utf8.encode(body is String ? body : jsonEncode(body)));
        }
        final response = await httpRequest.close().timeout(_timeout);
        if (response.isRedirect && redirect < _maxRedirects) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) {
            throw PluginHttpException(AppStrings.t('plugin.http.redirectMissing'));
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
    } finally {
      client.close(force: true);
    }
  }

  void _enforcePolicy(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw PluginHttpException(AppStrings.t('plugin.http.scheme').replaceFirst('{s}', uri.scheme));
    }
    if (_isBlockedHost(uri.host)) {
      throw PluginHttpException(AppStrings.t('plugin.http.privateHost').replaceFirst('{h}', uri.host));
    }
  }

  /// Blocks loopback / link-local / private / ULA targets in every encoding
  /// (dotted-quad, IPv6, numeric-looking hosts) so a plugin can't reach the
  /// local machine or LAN (SSRF).
  bool _isBlockedHost(String host) {
    final lower = host.toLowerCase();
    if (lower == 'localhost' || lower.endsWith('.local')) return true;
    final bare = lower.startsWith('[') && lower.endsWith(']')
        ? lower.substring(1, lower.length - 1)
        : lower;
    final address = InternetAddress.tryParse(bare);
    if (address != null) {
      if (address.isLoopback ||
          address.isLinkLocal ||
          address.isMulticast) {
        return true;
      }
      final raw = address.rawAddress;
      if (address.type == InternetAddressType.IPv4) {
        if (raw[0] == 10 || raw[0] == 0) return true;
        if (raw[0] == 192 && raw[1] == 168) return true;
        if (raw[0] == 169 && raw[1] == 254) return true;
        if (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) return true;
      } else if (raw.isNotEmpty && (raw[0] & 0xfe) == 0xfc) {
        return true; // IPv6 unique-local fc00::/7
      }
      return false;
    }
    // A host that looks numeric but didn't parse (decimal/hex/octal IPv4
    // encodings of internal addresses) is treated as untrusted.
    if (RegExp(r'^(0x)?[0-9a-f]+$').hasMatch(bare)) return true;
    return false;
  }

  Future<List<int>> _readCapped(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw PluginHttpException(AppStrings.t('plugin.http.tooLarge'));
      }
    }
    return bytes;
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
