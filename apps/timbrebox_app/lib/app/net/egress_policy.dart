import 'dart:io';

import '../design/app_strings.dart';

typedef HostLookup = Future<List<InternetAddress>> Function(String host);
typedef AddressCheck = bool Function(InternetAddress address);

/// Decides which remote hosts the app may contact on behalf of untrusted
/// input (plugins, plugin-provided stream URLs, plugin downloads).
///
/// A host is allowed only when it is reached over http(s) and every address it
/// resolves to is public. [attach] makes an [HttpClient] connect to the exact
/// address that was checked, so DNS rebinding cannot swap in a private one,
/// and because the client calls it for every connection, each redirect hop is
/// checked too.
final class EgressPolicy {
  const EgressPolicy({
    this.lookup = InternetAddress.lookup,
    this.isPublicAddress = isPublic,
  });

  final HostLookup lookup;
  final AddressCheck isPublicAddress;

  static const _connectTimeout = Duration(seconds: 15);

  /// Checks [uri] and returns the addresses it may be reached at.
  /// Throws [EgressDeniedException] when the scheme or host is not allowed.
  Future<List<InternetAddress>> vet(Uri uri, {bool httpsOnly = false}) async {
    final scheme = uri.scheme.toLowerCase();
    final schemeAllowed = httpsOnly
        ? scheme == 'https'
        : scheme == 'https' || scheme == 'http';
    if (!schemeAllowed) {
      throw EgressDeniedException(
        AppStrings.t('net.blockedScheme').replaceFirst('{s}', uri.scheme),
      );
    }
    final host = _bareHost(uri.host);
    if (host.isEmpty || _isLocalName(host) || _isNonCanonicalNumeric(host)) {
      throw _deniedHost(uri.host);
    }
    final literal = InternetAddress.tryParse(host);
    final addresses = literal != null ? [literal] : await _resolve(host, uri);
    if (addresses.isEmpty || !addresses.every(isPublicAddress)) {
      throw _deniedHost(uri.host);
    }
    return addresses;
  }

  /// Routes every connection [client] makes through [vet], connecting to the
  /// checked address (TLS still verifies the original host name).
  void attach(HttpClient client, {bool httpsOnly = false}) {
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final addresses = await vet(uri, httpsOnly: httpsOnly);
      final secure = uri.scheme.toLowerCase() == 'https';
      final port = uri.hasPort ? uri.port : (secure ? 443 : 80);
      final socket = _connectAny(addresses, port).then<Socket>(
        (raw) => secure ? SecureSocket.secure(raw, host: uri.host) : raw,
      );
      return ConnectionTask.fromSocket(socket, () {});
    };
  }

  Future<List<InternetAddress>> _resolve(String host, Uri uri) async {
    try {
      return await lookup(host);
    } on SocketException {
      throw _deniedHost(uri.host);
    }
  }

  Future<Socket> _connectAny(List<InternetAddress> addresses, int port) async {
    Object? lastError;
    for (final address in addresses) {
      try {
        return await Socket.connect(address, port, timeout: _connectTimeout);
      } on SocketException catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? const SocketException('No address to connect to');
  }

  EgressDeniedException _deniedHost(String host) => EgressDeniedException(
    AppStrings.t('net.blockedHost').replaceFirst('{h}', host),
  );

  static String _bareHost(String host) {
    final lower = host.toLowerCase();
    final unbracketed = lower.startsWith('[') && lower.endsWith(']')
        ? lower.substring(1, lower.length - 1)
        : lower;
    return unbracketed.endsWith('.')
        ? unbracketed.substring(0, unbracketed.length - 1)
        : unbracketed;
  }

  static bool _isLocalName(String host) =>
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal');

  /// Hosts such as `127.1`, `0177.0.0.1`, `2130706433` or `0x7f000001` are
  /// IPv4 addresses to the system resolver (and to libmpv), which may read
  /// them differently from [InternetAddress]. A numeric last label never
  /// belongs to a domain name, so only the plain dotted-decimal form passes.
  static bool _isNonCanonicalNumeric(String host) {
    if (host.contains(':')) return false; // IPv6 literal
    final labels = host.split('.');
    if (!RegExp(r'^(0x[0-9a-f]*|[0-9]+)$').hasMatch(labels.last)) return false;
    final octet = RegExp(r'^(0|[1-9][0-9]{0,2})$');
    final canonical =
        labels.length == 4 &&
        labels.every((l) => octet.hasMatch(l) && int.parse(l) <= 255);
    return !canonical;
  }

  /// Whether [address] is routable on the public internet.
  static bool isPublic(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) return _isPublicV4(bytes);
    if (bytes.length != 16) return false;
    final embedded = _embeddedV4(bytes);
    if (embedded != null) return _isPublicV4(embedded);
    if (bytes.every((b) => b == 0)) return false; // ::
    if (bytes.sublist(0, 15).every((b) => b == 0) && bytes[15] == 1) {
      return false; // ::1
    }
    final b0 = bytes[0];
    final b1 = bytes[1];
    if ((b0 & 0xfe) == 0xfc) return false; // fc00::/7 unique local
    if (b0 == 0xfe && (b1 & 0x80) == 0x80) {
      return false; // fe80::/10 link local, fec0::/10 site local
    }
    if (b0 == 0xff) return false; // multicast
    return true;
  }

  /// The IPv4 address carried by an IPv4-mapped (::ffff:a.b.c.d),
  /// IPv4-compatible (::a.b.c.d) or NAT64 (64:ff9b::a.b.c.d) address.
  static List<int>? _embeddedV4(List<int> bytes) {
    final tail = bytes.sublist(12);
    final prefix = bytes.sublist(0, 12);
    final mapped =
        prefix.sublist(0, 10).every((b) => b == 0) &&
        prefix[10] == 0xff &&
        prefix[11] == 0xff;
    final compatible =
        prefix.every((b) => b == 0) && !(tail[0] == 0 && tail[1] == 0);
    final nat64 =
        prefix[0] == 0x00 &&
        prefix[1] == 0x64 &&
        prefix[2] == 0xff &&
        prefix[3] == 0x9b &&
        prefix.sublist(4).every((b) => b == 0);
    return mapped || compatible || nat64 ? tail : null;
  }

  static bool _isPublicV4(List<int> b) {
    final a = b[0];
    if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
    if (a == 100 && (b[1] & 0xc0) == 64) return false; // 100.64/10
    if (a == 169 && b[1] == 254) return false;
    if (a == 172 && (b[1] & 0xf0) == 16) return false; // 172.16/12
    if (a == 192 && b[1] == 0 && b[2] == 0) return false; // 192.0.0/24
    if (a == 192 && b[1] == 168) return false;
    if (a == 198 && (b[1] & 0xfe) == 18) return false; // 198.18/15
    return true;
  }
}

class EgressDeniedException implements Exception {
  const EgressDeniedException(this.message);
  final String message;
  @override
  String toString() => message;
}
