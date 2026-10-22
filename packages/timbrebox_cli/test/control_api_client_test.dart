import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:timbrebox_cli/timbrebox_cli.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/':
          request.response.write(jsonEncode({'name': 'TimbreBox control API'}));
        case '/status':
          request.response.write(jsonEncode({'playing': true, 'volume': 0.4}));
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('discovers the control API on its port and parses JSON', () async {
    final client = ControlApiClient(ports: [server.port]);
    addTearDown(client.close);

    final base = await client.discover();
    expect(base, 'http://127.0.0.1:${server.port}');

    final status = await client.getJson(base!, '/status');
    expect(status['playing'], true);
    expect(status['volume'], 0.4);
  });

  test('returns null when nothing answers on the scanned ports', () async {
    final client = ControlApiClient(ports: const [1]); // refused → not found
    addTearDown(client.close);
    expect(await client.discover(), isNull);
  });
}
