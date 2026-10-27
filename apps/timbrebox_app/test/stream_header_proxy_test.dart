import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/data/stream_header_proxy.dart';
import 'package:timbrebox_app/app/net/egress_policy.dart';

void main() {
  late HttpServer upstream;
  late List<String> upstreamPaths;
  late HttpClient player;

  setUp(() async {
    upstreamPaths = [];
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) {
      upstreamPaths.add(request.uri.path);
      request.response
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..write('audio-bytes')
        ..close();
    });
    player = HttpClient();
  });

  tearDown(() async {
    player.close(force: true);
    await upstream.close(force: true);
  });

  Future<(int, String)> fetch(Uri local) async {
    final response = await (await player.getUrl(local)).close();
    final body = await response
        .transform(const SystemEncoding().decoder)
        .join();
    return (response.statusCode, body);
  }

  test('refuses to relay a stream that points at the local machine', () async {
    final proxy = StreamHeaderProxy();
    final local = await proxy.publish(
      Uri.parse('http://127.0.0.1:${upstream.port}/secret'),
      {'Referer': 'https://example.org/'},
    );

    final (status, _) = await fetch(local);

    expect(status, HttpStatus.badGateway);
    expect(upstreamPaths, isEmpty);
  });

  test('relays a stream from an allowed host with its headers', () async {
    final proxy = StreamHeaderProxy(
      policy: EgressPolicy(
        lookup: (_) async => [InternetAddress.loopbackIPv4],
        isPublicAddress: (_) => true,
      ),
    );
    final local = await proxy.publish(
      Uri.parse('http://cdn.test:${upstream.port}/track.mp3'),
      {'Referer': 'https://example.org/'},
    );

    final (status, body) = await fetch(local);

    expect(status, HttpStatus.ok);
    expect(body, 'audio-bytes');
    expect(upstreamPaths, ['/track.mp3']);
  });

  test('publishes unguessable tokens instead of a counter', () async {
    final proxy = StreamHeaderProxy();
    addTearDown(proxy.dispose);
    final first = await proxy.publish(Uri.parse('https://cdn.test/a'), {});
    final second = await proxy.publish(Uri.parse('https://cdn.test/b'), {});

    final tokens = [first.pathSegments.last, second.pathSegments.last];
    for (final token in tokens) {
      expect(token, matches(RegExp(r'^[0-9a-f]{32}$')));
    }
    expect(tokens.first, isNot(tokens.last));
  });

  test('refuses a request that names another host', () async {
    final proxy = StreamHeaderProxy(
      policy: EgressPolicy(
        lookup: (_) async => [InternetAddress.loopbackIPv4],
        isPublicAddress: (_) => true,
      ),
    );
    addTearDown(proxy.dispose);
    final local = await proxy.publish(
      Uri.parse('http://cdn.test:${upstream.port}/track.mp3'),
      const {},
    );

    final request = await player.getUrl(local);
    request.headers.host = 'rebound.example';
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.forbidden);
    expect(upstreamPaths, isEmpty);
  });
}
