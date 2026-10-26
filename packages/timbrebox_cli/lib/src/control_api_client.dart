import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'control_token.dart';

/// A tiny client for the TimbreBox loopback control API. Discovers the running
/// player on its fixed preferred port range and performs JSON requests, each
/// carrying the run's token (see [readControlToken]).
class ControlApiClient {
  ControlApiClient({
    List<int>? ports,
    String? token,
    this.timeout = defaultTimeout,
  }) : ports =
           ports ??
           const [8787, 8788, 8789, 8790, 8791, 8792, 8793, 8794, 8795, 8796],
       _fixedToken = token;

  /// How long one request may take, answer included. A search waits for
  /// every enabled source, so this is generous.
  static const defaultTimeout = Duration(seconds: 45);

  /// How long discovery waits on each port.
  static const _probeTimeout = Duration(seconds: 3);

  final List<int> ports;
  final Duration timeout;
  final String? _fixedToken;

  /// The token is read again for every request: it changes each time the
  /// app starts, and the MCP server outlives app restarts.
  String? get _token => _fixedToken ?? readControlToken();
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);

  /// Returns the base URL of the running control API, or null if none answers.
  /// Throws [ControlApiException] when the player answers but refuses the
  /// token (missing, or from an earlier run).
  Future<String?> discover() async {
    for (final port in ports) {
      final (int, String) answer;
      try {
        answer = await _raw('http://127.0.0.1:$port/', limit: _probeTimeout);
      } catch (_) {
        continue; // Port not listening — try the next.
      }
      final (status, body) = answer;
      if (status == HttpStatus.unauthorized &&
          body.contains(controlTokenHeader)) {
        throw ControlApiException(
          _token == null
              ? 'TimbreBox is running, but its control token was not found '
                    '(set TIMBREBOX_TOKEN_FILE to its control-token file).'
              : 'TimbreBox refused the control token (it changes every run; '
                    'is TIMBREBOX_TOKEN or TIMBREBOX_TOKEN_FILE stale?).',
        );
      }
      if (body.contains('TimbreBox control API')) {
        return 'http://127.0.0.1:$port';
      }
    }
    return null;
  }

  /// Endpoints that only read state; the player accepts every other
  /// endpoint only as POST.
  static const readPaths = {'/', '/status', '/queue', '/sources', '/lyric'};

  /// GETs [path] on [base] and decodes the JSON object response.
  Future<Map<String, Object?>> getJson(String base, String path) async =>
      _json((await _raw('$base$path')).$2);

  /// Calls [path] (with its query) on [base] using the method the player
  /// expects for it — GET for reads, POST for actions — and decodes the JSON.
  Future<Map<String, Object?>> requestJson(String base, String path) async {
    final uri = Uri.parse('$base$path');
    final method = readPaths.contains(uri.path) ? 'GET' : 'POST';
    return _json((await _raw(uri.toString(), method: method)).$2);
  }

  Map<String, Object?> _json(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
  }

  /// The status and body of one request, all of it within [limit] (default
  /// [timeout]).
  Future<(int, String)> _raw(
    String url, {
    String method = 'GET',
    Duration? limit,
  }) async {
    final request = await _http.openUrl(method, Uri.parse(url));
    final token = _token;
    if (token != null) request.headers.set(controlTokenHeader, token);
    Future<(int, String)> exchange() async {
      final response = await request.close();
      return (
        response.statusCode,
        await response.transform(utf8.decoder).join(),
      );
    }

    return exchange().timeout(
      limit ?? timeout,
      onTimeout: () {
        request.abort();
        throw TimeoutException('TimbreBox did not answer in time.', timeout);
      },
    );
  }

  void close() => _http.close(force: true);
}

/// The player answered, but not with what was asked for.
class ControlApiException implements Exception {
  const ControlApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
