import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';

void main() {
  late HttpServer server;
  late HttpClient client;
  late StreamHeaderProxy proxy;
  late List<String> ranges;
  const size = 1024 * 1024 + 8;
  setUp(() async {
    ranges = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final header = request.headers.value('range') ?? '';
      ranges.add(header);
      if (request.uri.path == '/ignores-range') {
        request.response
          ..write('not partial')
          ..close();
        return;
      }
      final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(header)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..contentLength = end - start + 1
        ..headers.set('content-range', 'bytes $start-$end/$size')
        ..add(Uint8List(end - start + 1));
      await request.response.close();
    });
    client = HttpClient();
    proxy = StreamHeaderProxy(
      policy: EgressPolicy(
        lookup: (_) async => [InternetAddress.loopbackIPv4],
        isPublicAddress: (_) => true,
      ),
    );
  });
  tearDown(() async {
    client.close(force: true);
    await proxy.dispose();
    await server.close(force: true);
  });
  test(
    'verified byte length enables bounded ranges without a provider query parameter',
    () async {
      final local = await proxy.publish(
        Uri.parse('http://media.test:${server.port}/audio'),
        {},
        chunked: true,
        contentLength: size,
      );
      final response = await (await client.getUrl(local)).close();
      final bytes = await response.fold<int>(
        0,
        (sum, chunk) => sum + chunk.length,
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(bytes, size);
      expect(ranges, ['bytes=0-1048575', 'bytes=1048576-1048583']);
    },
  );
  test(
    'a server ignoring ranges is not concatenated repeatedly as audio',
    () async {
      final local = await proxy.publish(
        Uri.parse('http://media.test:${server.port}/ignores-range'),
        {},
        chunked: true,
        contentLength: size,
      );
      final response = await (await client.getUrl(local)).close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.badGateway);
      expect(ranges, hasLength(1));
    },
  );
  test('invalid claimed lengths are rejected before publishing', () async {
    await expectLater(
      proxy.publish(
        Uri.parse('https://media.example/audio'),
        {},
        chunked: true,
        contentLength: -1,
      ),
      throwsArgumentError,
    );
  });
}
