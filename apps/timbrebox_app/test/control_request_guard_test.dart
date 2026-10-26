import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/state/control_request_guard.dart';

void main() {
  const port = 8787;

  ControlRejection? check({
    String method = 'GET',
    String path = '/status',
    String? host = '127.0.0.1:8787',
    String? origin,
    String? fetchSite,
    String? token = _token,
  }) => controlRequestRejection(
    method: method,
    path: path,
    host: host,
    origin: origin,
    fetchSite: fetchSite,
    port: port,
    token: token,
    expectedToken: _token,
  );

  test('serves a local read with GET', () {
    expect(check(), isNull);
    expect(check(host: 'localhost:8787', path: '/queue'), isNull);
  });

  test('serves a local action with POST', () {
    expect(check(method: 'POST', path: '/pause'), isNull);
    expect(check(method: 'POST', path: '/search'), isNull);
  });

  test('refuses an action sent with GET (an <img> or link on a web page)', () {
    for (final path in ['/quit', '/play-ref', '/source', '/search', '/next']) {
      expect(check(path: path)?.status, 405, reason: path);
    }
  });

  test('refuses a read sent with POST', () {
    expect(check(method: 'POST', path: '/status')?.status, 405);
  });

  test('refuses a request for another host name (DNS rebinding)', () {
    expect(check(host: 'attacker.example:8787')?.status, 403);
    expect(check(host: '127.0.0.1:9999')?.status, 403);
    expect(check(host: null)?.status, 403);
  });

  test('refuses any request a browser marks as cross-site', () {
    expect(
      check(
        method: 'POST',
        path: '/quit',
        origin: 'https://evil.example',
      )?.status,
      403,
    );
    expect(check(origin: 'null')?.status, 403);
    expect(check(fetchSite: 'cross-site')?.status, 403);
    expect(check(fetchSite: 'same-site')?.status, 403);
  });

  test('accepts a request the user typed in the address bar', () {
    expect(check(fetchSite: 'none'), isNull);
  });

  test('refuses a request without this run\'s token', () {
    expect(check(token: null)?.status, 401);
    expect(check(token: '')?.status, 401);
    expect(check(method: 'POST', path: '/quit', token: 'guess')?.status, 401);
    expect(check(token: '${_token}0')?.status, 401);
  });
}

const _token = '0123456789abcdef0123456789abcdef';
