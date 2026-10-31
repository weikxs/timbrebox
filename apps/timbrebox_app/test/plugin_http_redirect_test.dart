import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_http.dart';

void main() {
  late HttpServer first;
  late HttpServer second;
  late Map<String, List<String>> received;
  late PluginHttpClient client;

  setUp(() async {
    received = {};
    first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    void finish(HttpRequest request) {
      request.headers.forEach((key, values) => received[key] = values);
      request.response
        ..write('done')
        ..close();
    }

    second.listen(finish);
    first.listen((request) {
      if (request.uri.path == '/done') {
        finish(request);
        return;
      }
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, switch (request.uri.path) {
          '/same' => '/done',
          '/unsupported' => 'file:///not-a-platform-page',
          _ => 'http://other.test:${second.port}/done',
        })
        ..close();
    });
    client = PluginHttpClient(
      policy: EgressPolicy(
        lookup: (_) async => [InternetAddress.loopbackIPv4],
        isPublicAddress: (_) => true,
      ),
    );
  });
  tearDown(() async {
    client.close();
    await first.close(force: true);
    await second.close(force: true);
  });

  Map<String, Object?> request(String path) => {
    'url': 'http://public.test:${first.port}/$path',
    'headers': {
      'Cookie': 'demo-anonymous=value',
      'Authorization': 'Bearer demo-test-only',
      'X-Private-Header': 'demo-test-only',
      'Referer': 'https://public.test/?demo-private=value',
      'User-Agent': 'TimbreBox-test',
      'Accept': 'application/json',
      'Range': 'bytes=0-10',
    },
  };

  test('cross-origin redirect strips all secret and custom headers', () async {
    final result = await client.send(request('cross'));
    expect(result['status'], 200);
    expect(result['url'], 'http://other.test:${second.port}/done');
    for (final name in [
      'cookie',
      'authorization',
      'x-private-header',
      'referer',
    ]) {
      expect(received.containsKey(name), false);
    }
    expect(received['user-agent'], ['TimbreBox-test']);
    expect(received['accept'], ['application/json']);
    expect(received['range'], ['bytes=0-10']);
  });

  test('same-origin redirect retains explicitly configured headers', () async {
    final result = await client.send(request('same'));
    expect(result['url'], 'http://public.test:${first.port}/done');
    expect(received['cookie'], ['demo-anonymous=value']);
    expect(received['authorization'], ['Bearer demo-test-only']);
    expect(received['x-private-header'], ['demo-test-only']);
  });

  test('unsupported redirect is still refused by the egress policy', () async {
    await expectLater(
      client.send(request('unsupported')),
      throwsA(isA<PluginHttpException>()),
    );
    expect(received, isEmpty);
  });
}
