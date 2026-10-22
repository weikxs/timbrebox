import 'dart:convert';
import 'dart:io';

/// A tiny client for the TimbreBox loopback control API. Discovers the running
/// player on its fixed preferred port range and performs JSON requests.
class ControlApiClient {
  ControlApiClient({List<int>? ports})
    : ports = ports ?? const [8787, 8788, 8789, 8790, 8791, 8792, 8793, 8794, 8795, 8796];

  final List<int> ports;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);

  /// Returns the base URL of the running control API, or null if none answers.
  Future<String?> discover() async {
    for (final port in ports) {
      try {
        final body = await _raw('http://127.0.0.1:$port/');
        if (body.contains('TimbreBox control API')) {
          return 'http://127.0.0.1:$port';
        }
      } catch (_) {
        // Port not listening — try the next.
      }
    }
    return null;
  }

  /// GETs [path] on [base] and decodes the JSON object response.
  Future<Map<String, Object?>> getJson(String base, String path) async {
    final decoded = jsonDecode(await _raw('$base$path'));
    return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
  }

  Future<String> _raw(String url) async {
    final request = await _http.getUrl(Uri.parse(url));
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  }

  void close() => _http.close(force: true);
}
