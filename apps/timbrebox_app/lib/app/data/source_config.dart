/// Network settings used by compiled-in source adapters.
///
/// Keeping endpoints and resource limits here prevents source implementations
/// from scattering environment values through parsing and state code.
final class SourceHttpPolicy {
  const SourceHttpPolicy({
    this.timeout = const Duration(seconds: 12),
    this.maxResponseBytes = 1024 * 1024,
    this.userAgent = 'TimbreBox/0.1',
  });

  final Duration timeout;
  final int maxResponseBytes;
  final String userAgent;
}

final class SourceEndpoint {
  const SourceEndpoint({required this.host, required this.paths});

  final String host;
  final Map<String, String> paths;

  Uri uri(
    String key, {
    Map<String, String> pathValues = const {},
    Map<String, String> query = const {},
  }) {
    var path = paths[key];
    if (path == null) throw ArgumentError.value(key, 'key');
    for (final entry in pathValues.entries) {
      path = path!.replaceAll(
        '{${entry.key}}',
        Uri.encodeComponent(entry.value),
      );
    }
    // `Uri(path:)` keeps the escapes made above; `Uri.https` would encode
    // their `%` again (a space would reach the server as `%2520`).
    return Uri(
      scheme: 'https',
      host: host,
      path: path,
      queryParameters: query.isEmpty ? null : query,
    );
  }
}

final class BuiltInSourceConfig {
  static const http = SourceHttpPolicy();
  static const pageSize = 30;
  static const videoApiMaxResponseBytes = 4 * 1024 * 1024;
  static const appName = 'TimbreBox';

  /// A current desktop-browser User-Agent. Some sources (e.g. Bilibili) reject
  /// the default client UA at their edge/WAF, so those adapters send this.
  static const browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static const audius = SourceEndpoint(
    host: 'api.audius.co',
    paths: {
      'search': '/v1/tracks/search',
      'trending': '/v1/tracks/trending',
      'stream': '/v1/tracks/{id}/stream',
    },
  );

  static const archive = SourceEndpoint(
    host: 'archive.org',
    paths: {
      'search': '/advancedsearch.php',
      'metadata': '/metadata/{id}',
      'download': '/download/{id}/{file}',
    },
  );

  static const radioBrowser = SourceEndpoint(
    host: 'de1.api.radio-browser.info',
    paths: {'search': '/json/stations/byname/{query}'},
  );

  static const bilibili = SourceEndpoint(
    host: 'api.bilibili.com',
    paths: {
      'search': '/x/web-interface/search/type',
      'view': '/x/web-interface/view',
      'play': '/x/player/playurl',
      'finger': '/x/frontend/finger/spi',
    },
  );
  static const bilibiliReferer = 'https://www.bilibili.com/';

  static const douyin = SourceEndpoint(
    host: 'www.douyin.com',
    paths: {'search': '/search/{query}', 'video': '/video/{id}'},
  );

  static const tiktok = SourceEndpoint(
    host: 'www.tiktok.com',
    paths: {'search': '/search', 'video': '/@{author}/video/{id}'},
  );

  const BuiltInSourceConfig._();
}
