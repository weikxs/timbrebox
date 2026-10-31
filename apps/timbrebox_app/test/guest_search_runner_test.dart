import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/guest_search_runner.dart';
import 'package:timbrebox_app/app/plugins/media_extraction_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('guest-search-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late NativeGuestSearchRunner runner;
  setUp(() {
    calls = [];
    runner = NativeGuestSearchRunner(channel: channel, enabled: true);
  });
  tearDown(() {
    runner.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  Matcher code(String value) =>
      isA<MediaExtractionException>().having((e) => e.code, 'code', value);

  test(
    'deadline partial snapshot exposes its short cached page without another native task',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'cancel') return null;
        return {'data': List.generate(24, item), 'isEnd': false};
      });
      final first = await runner.search('tiktok', 'music', 1);
      final second = await runner.search('tiktok', 'music', 2);
      final third = await runner.search('tiktok', 'music', 3);
      expect(first['entries'] as List, hasLength(10));
      expect(second['entries'] as List, hasLength(10));
      expect(third['entries'] as List, hasLength(4));
      expect(third['isEnd'], false);
      expect(calls.where((call) => call.method == 'search'), hasLength(1));
    },
  );

  test('disabled builds never create a native browser task', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final disabled = NativeGuestSearchRunner(channel: channel, enabled: false);
    addTearDown(disabled.dispose);
    await expectLater(
      disabled.search('tiktok', 'music', 1),
      throwsA(code('platform_search_unavailable')),
    );
    expect(calls, isEmpty);
  });

  test(
    'metadata pages cache briefly and retain unknown playback access',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'cancel') return null;
        final args = call.arguments as Map;
        final seen = (args['seenIds'] as List).length;
        return {
          'data': List.generate(12, (i) => item(seen + i)),
          'isEnd': false,
        };
      });
      final first = await runner.search('tiktok', 'music', 1);
      expect(first['entries'] as List, hasLength(10));
      expect((first['entries'] as List).first, isNot(contains('is_paid')));
      runner.cancel(); // Normal successful invocation cleanup keeps metadata.
      await runner.search('tiktok', 'music', 1);
      expect(calls, hasLength(1));
      final second = await runner.search('tiktok', 'music', 2);
      expect(second['entries'] as List, hasLength(2));
      expect(calls, hasLength(1));
      final third = await runner.search('tiktok', 'music', 3);
      expect((third['entries'] as List).first['id'], item(12)['id']);
      expect(third['entries'] as List, hasLength(10));
      final repeated = await runner.search('tiktok', 'music', 2);
      expect(repeated['entries'], second['entries']);
      expect((calls.last.arguments as Map)['wanted'], 38);
      expect((calls.last.arguments as Map)['seenIds'], hasLength(12));
      expect(
        (first['entries'] as List)
            .map((e) => e['id'])
            .toSet()
            .intersection(
              (second['entries'] as List).map((e) => e['id']).toSet(),
            ),
        isEmpty,
      );
    },
  );

  test(
    'five UI pages use one bounded metadata snapshot without an idle browser',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'data': List.generate(50, item), 'isEnd': false};
      });
      final ids = <Object?>{};
      for (var page = 1; page <= 5; page++) {
        final result = await runner.search('tiktok', 'music', page);
        final entries = result['entries'] as List;
        expect(entries, hasLength(10));
        for (final entry in entries) {
          expect(ids.add(entry['id']), isTrue);
        }
        expect(result['isEnd'], page == 5);
        runner.cancel();
      }
      expect(ids, hasLength(50));
      expect(calls, hasLength(1));
      expect((calls.single.arguments as Map)['wanted'], 50);
    },
  );

  test(
    'exhaustion respects cached leftovers rather than ending the first slice early',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'data': List.generate(12, item), 'isEnd': true};
      });
      expect((await runner.search('tiktok', 'music', 1))['isEnd'], isFalse);
      final second = await runner.search('tiktok', 'music', 2);
      expect(second['isEnd'], isTrue);
      expect(second['entries'] as List, hasLength(2));
      expect(calls, hasLength(1));
    },
  );

  test(
    'changed keywords and expired cache start from an empty metadata session',
    () async {
      var now = DateTime.utc(2026);
      runner.dispose();
      runner = NativeGuestSearchRunner(
        channel: channel,
        enabled: true,
        clock: () => now,
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'data': List.generate(10, item), 'isEnd': true};
      });
      await runner.search('tiktok', 'old', 1);
      await runner.search('tiktok', 'new', 1);
      now = now.add(const Duration(minutes: 3));
      await runner.search('tiktok', 'new', 1);
      expect(calls, hasLength(3));
      for (final call in calls) {
        expect((call.arguments as Map)['seenIds'], isEmpty);
      }
    },
  );

  test(
    'known end may be genuinely empty but unfinished responses may not fake an empty page',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'data': [], 'isEnd': false},
      );
      await expectLater(
        runner.search('tiktok', 'music', 1),
        throwsA(code('guest_search_incomplete')),
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'data': [], 'isEnd': true},
      );
      expect((await runner.search('tiktok', 'music', 1))['entries'], isEmpty);
    },
  );

  test(
    'untrusted native metadata cannot upgrade access or change stable identity',
    () async {
      for (final bad in [
        item(0)..['access'] = 'allowed',
        item(0)..['id'] = '2000000000000000000',
        item(0)..['url'] = 'https://127.0.0.1/video/1000000000000000000',
      ]) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
            'data': [bad],
            'isEnd': true,
          },
        );
        await expectLater(
          runner.search('tiktok', 'music', 1),
          throwsA(isA<MediaExtractionException>()),
        );
      }
    },
  );

  test(
    'platform errors never expose native raw details or signed URLs',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'unexpected',
          message: 'sensitive fixture details',
        ),
      );
      await expectLater(
        runner.search('tiktok', 'music', 1),
        throwsA(code('guest_search_failed')),
      );
    },
  );

  test(
    'cancel owns a job ID, drops late data, and permits another search',
    () async {
      final pending = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'cancel') return null;
        if (calls.where((c) => c.method == 'search').length == 1) {
          return pending.future;
        }
        return {'data': List.generate(10, item), 'isEnd': true};
      });
      final old = runner.search('tiktok', 'old', 1);
      final oldCheck = expectLater(old, throwsA(code('extractor_cancelled')));
      await pumpEventQueue();
      runner.cancel();
      final next = await runner.search('tiktok', 'new', 1);
      pending.complete({'data': List.generate(10, item), 'isEnd': true});
      await oldCheck;
      expect(next['entries'] as List, hasLength(10));
      final cancel = calls.singleWhere((c) => c.method == 'cancel');
      expect(
        (cancel.arguments as Map)['jobId'],
        (calls.first.arguments as Map)['jobId'],
      );
    },
  );
}

Map<String, Object?> item(int index) {
  final id = '${1000000000000000000 + index}';
  return {
    'id': id,
    'title': 'Fixture $index',
    'artist': 'Fixture',
    'duration': 20,
    'url': 'https://www.tiktok.com/@fixture_author/video/$id',
    'access': 'unverified',
    'contentKind': 'video_audio',
  };
}
