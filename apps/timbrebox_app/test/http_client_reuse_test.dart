import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_http.dart';

/// Each HTTP owner keeps one client, so back-to-back requests to a host reuse
/// one keep-alive connection instead of a new connection (and TLS handshake)
/// per request.
void main() {
  late HttpServer server;
  late Set<int> connections;
  late int requests;

  setUp(() async {
    connections = {};
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requests++;
      connections.add(request.connectionInfo!.remotePort);
      if (request.uri.path == '/missing') {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('gone')
          ..close();
        return;
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"ok":true}')
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri local(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  final allowLoopback = EgressPolicy(
    lookup: (_) async => [InternetAddress.loopbackIPv4],
    isPublicAddress: (_) => true,
  );

  test('the catalog JSON client reuses its connection', () async {
    final client = JsonHttpClient();

    for (var index = 0; index < 3; index++) {
      expect(
        await client.read(local('/a'), CancellationToken()),
        '{"ok":true}',
      );
    }

    expect(requests, 3);
    expect(connections, hasLength(1));
  });

  test('a failed catalog request does not poison the next one', () async {
    final client = JsonHttpClient();

    await expectLater(
      client.read(local('/missing'), CancellationToken()),
      throwsA(isA<SourceException>()),
    );
    expect(await client.read(local('/a'), CancellationToken()), '{"ok":true}');
  });

  test('a plugin reuses its connection and still vets every request', () async {
    final client = PluginHttpClient(policy: allowLoopback);
    addTearDown(client.close);
    final url = 'http://public.test:${server.port}/a';

    for (var index = 0; index < 3; index++) {
      final response = await client.send({'url': url});
      expect(response['data'], '{"ok":true}');
    }
    expect(connections, hasLength(1));

    final strict = PluginHttpClient();
    addTearDown(strict.close);
    await expectLater(
      strict.send({'url': local('/a').toString()}),
      throwsA(isA<PluginHttpException>()),
    );
  });

  test('the stream proxy reuses its upstream connection', () async {
    final proxy = StreamHeaderProxy(policy: allowLoopback);
    addTearDown(proxy.dispose);
    final published = await proxy.publish(
      Uri.parse('http://cdn.test:${server.port}/track.mp3'),
      const {'Referer': 'https://example.org/'},
    );
    final player = HttpClient();
    addTearDown(() => player.close(force: true));

    for (var index = 0; index < 3; index++) {
      final response = await (await player.getUrl(published)).close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.ok);
    }

    expect(requests, 3);
    expect(connections, hasLength(1));
  });
}
