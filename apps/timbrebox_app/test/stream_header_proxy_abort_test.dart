import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/data/stream_header_proxy.dart';
import 'package:timbrebox_app/app/net/egress_policy.dart';

/// libmpv drops its connection whenever it seeks; a chunked (googlevideo)
/// relay must then stop pulling windows from upstream.
void main() {
  const total = 16 * 1024 * 1024;
  late HttpServer upstream;
  late int windowsServed;
  late int bytesServed;

  setUp(() async {
    windowsServed = 0;
    bytesServed = 0;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final range = RegExp(
        r'bytes=(\d+)-(\d+)',
      ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '')!;
      final start = int.parse(range.group(1)!);
      final end = int.parse(range.group(2)!);
      windowsServed++;
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.contentType = ContentType('audio', 'mp4')
        ..contentLength = end - start + 1;
      for (var at = start; at <= end; at += 64 * 1024) {
        final size = (end + 1 - at).clamp(0, 64 * 1024);
        request.response.add(Uint8List(size));
        bytesServed += size;
        await request.response.flush();
      }
      await request.response.close();
    });
  });

  tearDown(() => upstream.close(force: true));

  StreamHeaderProxy proxy() => StreamHeaderProxy(
    policy: EgressPolicy(
      lookup: (_) async => [InternetAddress.loopbackIPv4],
      isPublicAddress: (_) => true,
    ),
  );

  test('stops fetching upstream windows once the player hangs up', () async {
    final relay = proxy();
    addTearDown(relay.dispose);
    final local = await relay.publish(
      Uri.parse('http://media.test:${upstream.port}/v?clen=$total'),
      const {'User-Agent': 'test'},
      chunked: true,
    );

    // Read the start of the stream like a player, then drop the connection
    // the way libmpv does on a seek.
    final socket = await Socket.connect(local.host, local.port);
    socket.write(
      'GET ${local.path} HTTP/1.1\r\nHost: ${local.host}:${local.port}\r\n\r\n',
    );
    var received = 0;
    final enough = Completer<void>();
    final subscription = socket.listen((data) {
      received += data.length;
      if (received > 256 * 1024 && !enough.isCompleted) enough.complete();
    });
    await enough.future;
    await subscription.cancel();
    socket.destroy();
    await Future<void>.delayed(const Duration(seconds: 2));

    // ignore: avoid_print
    print(
      'after hang-up at ${received ~/ 1024} KB: upstream served '
      '$windowsServed windows, ${bytesServed ~/ (1024 * 1024)} MB of '
      '${total ~/ (1024 * 1024)} MB',
    );
    expect(windowsServed, lessThanOrEqualTo(3));
    expect(bytesServed, lessThan(total ~/ 4));
  });

  test('still relays a whole stream window by window', () async {
    final relay = proxy();
    addTearDown(relay.dispose);
    const size = 3 * 1024 * 1024 + 5;
    final local = await relay.publish(
      Uri.parse('http://media.test:${upstream.port}/v?clen=$size'),
      const {'User-Agent': 'test'},
      chunked: true,
    );

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(local)).close();
    final length = await response.fold<int>(
      0,
      (sum, data) => sum + data.length,
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(length, size);
    expect(windowsServed, 4);
  });
}
