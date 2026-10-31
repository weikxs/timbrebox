import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/media_extraction_error.dart';
import 'package:timbrebox_app/app/plugins/media_stream_probe.dart';

void main() {
  late HttpServer server;
  late GuardedMediaStreamProbe probe;
  late List<String> paths;
  late Completer<void> stalled;
  setUp(() async {
    paths = [];
    stalled = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      paths.add(request.uri.path);
      expect(request.headers.value('range'), 'bytes=0-1023');
      if (request.uri.path == '/stall') {
        if (!stalled.isCompleted) stalled.complete();
        return;
      }
      if (request.uri.path == '/denied') {
        request.response
          ..statusCode = 403
          ..close();
      } else if (request.uri.path == '/html') {
        request.response
          ..headers.contentType = ContentType.html
          ..write('<html>Not audio</html>')
          ..close();
      } else {
        final bytes = [
          0,
          0,
          0,
          16,
          0x66,
          0x74,
          0x79,
          0x70,
          ...List.filled(256, 0),
        ];
        request.response
          ..statusCode = 206
          ..headers.contentType = ContentType('audio', 'mp4')
          ..headers.set(
            'content-range',
            'bytes 0-${bytes.length - 1}/${bytes.length}',
          )
          ..add(bytes)
          ..close();
      }
    });
    probe = GuardedMediaStreamProbe(
      policy: EgressPolicy(
        lookup: (_) async => [InternetAddress.loopbackIPv4],
        isPublicAddress: (_) => true,
      ),
    );
  });
  tearDown(() async {
    probe.dispose();
    await server.close(force: true);
  });
  Map<String, Object?> candidate(String path) => {
    'url': 'http://public.test:${server.port}/$path',
    'mimeType': 'audio/mp4',
    'headers': <String, String>{},
  };
  test(
    'denied nominal best format falls back to genuinely readable full media',
    () async {
      final result = await probe.select([
        candidate('denied'),
        candidate('valid'),
      ]);
      expect(result['url'], endsWith('/valid'));
      expect(result['boundedRanges'], true);
      expect(result['contentLength'], 264);
      expect(paths, ['/denied', '/valid']);
    },
  );
  test('HTML with status 200 is not accepted as audio', () async {
    final result = await probe.select([candidate('html'), candidate('valid')]);
    expect(result['url'], endsWith('/valid'));
  });
  test(
    'the lowest-bandwidth fallback survives a long quality ladder',
    () async {
      final list = [
        for (var i = 0; i < 9; i++)
          candidate('denied')
            ..['url'] = 'http://public.test:${server.port}/denied?variant=$i',
        candidate('valid'),
      ];
      final result = await probe.select(list);
      expect(result['url'], endsWith('/valid'));
      expect(paths.length, 6);
    },
  );
  test(
    'all CDN refusals remain a distinct typed failure, not empty success or raw URLs',
    () async {
      await expectLater(
        probe.select([candidate('denied')]),
        throwsA(
          isA<MediaExtractionException>()
              .having((e) => e.code, 'code', 'media_access_denied')
              .having(
                (e) => e.message,
                'privacy',
                isNot(contains('public.test')),
              ),
        ),
      );
    },
  );
  test('slow best formats cannot starve the low-bandwidth fallback', () async {
    final policy = probe.policy;
    probe.dispose();
    probe = GuardedMediaStreamProbe(
      policy: policy,
      totalBudget: const Duration(milliseconds: 500),
      attemptBudget: const Duration(milliseconds: 100),
    );
    final result = await probe.select([
      for (var index = 0; index < 5; index++)
        candidate('stall')
          ..['url'] = 'http://public.test:${server.port}/stall?variant=$index',
      candidate('valid'),
    ]);
    expect(result['url'], endsWith('/valid'));
    expect(paths.last, '/valid');
    expect(paths.length, lessThan(6));
  });

  test(
    'default policy rejects private destinations before connecting',
    () async {
      final guarded = GuardedMediaStreamProbe();
      addTearDown(guarded.dispose);
      await expectLater(
        guarded.select([
          {'url': 'http://127.0.0.1:${server.port}/valid'},
        ]),
        throwsA(isA<MediaExtractionException>()),
      );
      expect(paths, isEmpty);
    },
  );
  test(
    'cancel closes a stalled request and the next selection can run',
    () async {
      final result = probe.select([candidate('stall')]);
      final rejected = expectLater(
        result,
        throwsA(
          isA<MediaExtractionException>().having(
            (e) => e.code,
            'code',
            'extractor_cancelled',
          ),
        ),
      );
      await stalled.future.timeout(const Duration(seconds: 2));
      probe.cancel();
      await rejected;
      expect(
        (await probe.select([candidate('valid')]))['url'],
        endsWith('/valid'),
      );
    },
  );
}
