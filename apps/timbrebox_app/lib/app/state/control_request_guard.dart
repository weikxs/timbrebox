/// Request checks for the loopback control API.
///
/// Binding to 127.0.0.1 keeps other machines out, but any web page the user
/// opens can still make the browser send requests to 127.0.0.1. These checks
/// shut that door:
///   * the `Host` header must name the loopback server itself, which defeats
///     DNS rebinding (a page reaching us through its own domain name);
///   * a request carrying `Origin`, or a `Sec-Fetch-Site` other than `none`,
///     comes from a web page and is refused;
///   * endpoints that change anything accept only POST, so a plain `<img>` or
///     link cannot trigger them.
library;

/// Endpoints that only read state. Every other endpoint needs POST.
const controlReadPaths = {'/', '/status', '/queue', '/sources', '/lyric'};

typedef ControlRejection = ({int status, String error});

/// Why the request must be refused, or null when it may be served.
ControlRejection? controlRequestRejection({
  required String method,
  required String path,
  required String? host,
  required String? origin,
  required String? fetchSite,
  required int port,
}) {
  final normalizedHost = host?.toLowerCase();
  if (normalizedHost != '127.0.0.1:$port' &&
      normalizedHost != 'localhost:$port') {
    return (status: 403, error: 'Forbidden host');
  }
  if (origin != null || (fetchSite != null && fetchSite != 'none')) {
    return (status: 403, error: 'Requests from web pages are not allowed');
  }
  final isRead = controlReadPaths.contains(path);
  final verb = method.toUpperCase();
  if (isRead && verb != 'GET' && verb != 'HEAD') {
    return (status: 405, error: 'Use GET for $path');
  }
  if (!isRead && verb != 'POST') {
    return (status: 405, error: 'Use POST for $path');
  }
  return null;
}
