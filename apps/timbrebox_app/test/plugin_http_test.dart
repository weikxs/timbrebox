import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_http.dart';

void main() {
  late HttpServer server;
  late List<String> paths;

  setUp(() async {
    paths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      paths.add(request.uri.path);
      if (request.uri.path == '/loop') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/loop')
          ..close();
        return;
      }
      request.response
        ..write('ok')
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  test('refuses a plugin request to the local machine', () async {
    final client = PluginHttpClient();

    await expectLater(
      client.send({'url': 'http://127.0.0.1:${server.port}/quit'}),
      throwsA(isA<PluginHttpException>()),
    );
    expect(paths, isEmpty);
  });

  test('refuses a plugin request to a name that resolves locally', () async {
    final client = PluginHttpClient(
      policy: EgressPolicy(lookup: (_) async => [InternetAddress.loopbackIPv4]),
    );

    await expectLater(
      client.send({'url': 'http://rebind.example:${server.port}/quit'}),
      throwsA(isA<PluginHttpException>()),
    );
    expect(paths, isEmpty);
  });

  test('stops after too many redirects instead of returning a 3xx', () async {
    final client = PluginHttpClient(
      policy: EgressPolicy(
        lookup: (_) async => [InternetAddress.loopbackIPv4],
        isPublicAddress: (_) => true,
      ),
    );

    await expectLater(
      client.send({'url': 'http://public.test:${server.port}/loop'}),
      throwsA(isA<PluginHttpException>()),
    );
    expect(paths, hasLength(5));
  });
}
