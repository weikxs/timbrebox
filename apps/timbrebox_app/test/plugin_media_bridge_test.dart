import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/plugins/media_extractor_process.dart';
import 'package:timbrebox_app/app/plugins/platform_media_backend.dart';
import 'package:timbrebox_app/app/plugins/plugin_catalog_source.dart';
import 'package:timbrebox_app/app/plugins/plugin_manifest.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

class _Backend implements PlatformMediaBackend {
  final calls = <Map<String, Object?>>[];
  Future<Map<String, Object?>> Function(Map<String, Object?>)? answer;
  bool disposed = false;
  bool cancelled = false;
  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    calls.add(request);
    return answer == null ? {'isEnd': true, 'data': []} : answer!(request);
  }

  @override
  void cancel() => cancelled = true;
  @override
  void dispose() => disposed = true;
}

const _source =
    "module.exports = Object.assign({platform:'YouTube'}, env.media.source('youtube'));";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'two live plugin engines route asynchronous messages to their own backend',
    () async {
      final a = _Backend(), b = _Backend();
      a.answer = (_) async => {'owner': 'a'};
      b.answer = (_) async => {'owner': 'b'};
      final first = PluginRuntime(media: a), second = PluginRuntime(media: b);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.load(_source);
      await second.load(_source);
      final results = await Future.wait([
        first.call('search', ['engine-a', 1, 'music']),
        second.call('search', ['engine-b', 1, 'music']),
      ]).timeout(const Duration(milliseconds: 500), onTimeout: () => []);
      expect(a.calls.map((call) => call['query']), ['engine-a']);
      expect(b.calls.map((call) => call['query']), ['engine-b']);
      expect(results, [
        {'owner': 'a'},
        {'owner': 'b'},
      ]);
    },
  );

  test(
    'four engines remain isolated when the newest engine is disposed',
    () async {
      final backends = List.generate(4, (_) => _Backend());
      final engines = [
        for (final backend in backends) PluginRuntime(media: backend),
      ];
      for (var i = 0; i < engines.length; i++) {
        final owner = i;
        backends[i].answer = (_) async {
          await Future<void>.delayed(Duration(milliseconds: 5 * (4 - owner)));
          return {'owner': owner};
        };
        addTearDown(engines[i].dispose);
        await engines[i].load(_source);
      }
      final results = await Future.wait([
        for (var i = 0; i < 4; i++)
          engines[i].call('search', ['engine-$i', 1, 'music']),
      ]);
      expect(results, [
        for (var i = 0; i < 4; i++) {'owner': i},
      ]);
      engines.last.dispose();
      expect(await engines.first.call('search', ['still-first', 1, 'music']), {
        'owner': 0,
      });
      expect(backends.first.calls.last['query'], 'still-first');
    },
  );

  test(
    'timers belong to their engine and disposal cannot re-enter a released context',
    () async {
      const timed =
          "module.exports = {platform:'Timer fixture', search:function(q){return new Promise(function(resolve){setTimeout(function(){resolve(q);},40);});}};";
      final first = PluginRuntime(), second = PluginRuntime();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.load(timed);
      await second.load(timed);
      final cancelled = first
          .call('search', ['closed'])
          .then<Object?>((v) => v, onError: (Object e) => e);
      final kept = second.call('search', ['kept']);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      first.dispose();
      expect(
        await cancelled,
        isA<PluginRuntimeException>().having(
          (e) => e.code,
          'code',
          'extractor_cancelled',
        ),
      );
      expect(await kept, 'kept');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await second.call('search', ['again']), 'again');
    },
  );

  test('plugin calls the fixed host search bridge', () async {
    final backend = _Backend();
    final runtime = PluginRuntime(media: backend);
    addTearDown(runtime.dispose);
    await runtime.load(_source);
    final raw = await runtime.call('search', ['demo song', 2, 'music']);
    expect(raw, {'isEnd': true, 'data': []});
    expect(backend.calls.single, containsPair('operation', 'search'));
    expect(backend.calls.single, containsPair('platform', 'youtube'));
    expect(backend.calls.single, containsPair('page', 2));
  });

  test(
    'links import through the existing search path without persisting a stream',
    () async {
      final backend = _Backend()
        ..answer = (_) async => {
          'item': {'id': 'abcdefghijk', 'title': 'Demo song'},
          'media': {'url': 'https://media.example/audio.m4a?token=demo'},
        };
      final runtime = PluginRuntime(media: backend);
      addTearDown(runtime.dispose);
      await runtime.load(_source);
      final raw = await runtime.call('search', [
        'https://youtu.be/abcdefghijk',
        1,
        'music',
      ]);
      expect(raw, {
        'isEnd': true,
        'data': [
          {'id': 'abcdefghijk', 'title': 'Demo song'},
        ],
      });
      expect(backend.calls.single['operation'], 'resolve');
      expect(backend.calls.single['url'], 'https://youtu.be/abcdefghijk');
      await runtime.call('search', [
        'https://www.douyin.com/video/1234567890123456789',
        1,
        'music',
      ]);
      expect(backend.calls.length, 1);
    },
  );

  test('host error codes survive the JS envelope and source adapter', () async {
    final backend = _Backend()
      ..answer = (_) async => throw const MediaExtractionException(
        'platform_search_unavailable',
        'raw secret error',
      );
    final runtime = PluginRuntime(media: backend);
    await runtime.load(_source);
    final source = PluginCatalogSource(
      manifest: const PluginManifest(
        id: 'plugin_youtube',
        platform: 'YouTube',
        version: '0.1.0',
      ),
      runtime: runtime,
    );
    addTearDown(source.dispose);
    await expectLater(
      source.search(
        SearchRequest(query: 'demo', cancellation: CancellationToken()),
      ),
      throwsA(
        isA<SourceException>()
            .having((e) => e.code, 'code', 'platform_search_unavailable')
            .having((e) => e.retryable, 'retryable', false)
            .having(
              (e) => e.message.contains('secret'),
              'no raw backend errors',
              false,
            ),
      ),
    );
  });

  test(
    'cancellation stops active media work and preserves JS serialization',
    () async {
      final entered = Completer<void>();
      final pending = Completer<Map<String, Object?>>();
      final backend = _Backend()
        ..answer = (_) {
          if (!entered.isCompleted) {
            entered.complete();
            return pending.future;
          }
          return Future.value({'isEnd': true, 'data': []});
        };
      final runtime = PluginRuntime(media: backend);
      addTearDown(runtime.dispose);
      await runtime.load(_source);
      final token = CancellationToken();
      final first = runtime.call('search', [
        'first',
        1,
        'music',
      ], cancellation: token);
      final cancelled = expectLater(first, throwsA(isA<OperationCancelled>()));
      await entered.future;
      final second = runtime.call('search', ['second', 1, 'music']);
      token.cancel();
      await cancelled;
      expect(backend.cancelled, true);
      expect(backend.calls.length, 1);
      pending.completeError(
        const MediaExtractionException('extractor_cancelled', 'cancelled'),
      );
      expect(await second, {'isEnd': true, 'data': []});
      expect(backend.calls.length, 2);
    },
  );

  test('a cancelled queued invocation never calls the media backend', () async {
    final entered = Completer<void>();
    final pending = Completer<Map<String, Object?>>();
    final backend = _Backend()
      ..answer = (_) {
        entered.complete();
        return pending.future;
      };
    final runtime = PluginRuntime(media: backend);
    addTearDown(runtime.dispose);
    await runtime.load(_source);
    final first = runtime.call('search', ['first', 1, 'music']);
    await entered.future;
    final token = CancellationToken();
    final second = runtime.call('search', [
      'second',
      1,
      'music',
    ], cancellation: token);
    final cancelled = expectLater(second, throwsA(isA<OperationCancelled>()));
    token.cancel();
    await cancelled;
    expect(backend.cancelled, false);
    pending.complete({'isEnd': true, 'data': []});
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(backend.calls.length, 1);
  });

  test('cancellation before RPC dispatch cannot start backend work', () async {
    final backend = _Backend();
    final runtime = PluginRuntime(media: backend);
    addTearDown(runtime.dispose);
    await runtime.load(_source);
    final token = CancellationToken();
    final result = runtime.call('search', [
      'demo',
      1,
      'music',
    ], cancellation: token);
    final check = expectLater(result, throwsA(isA<OperationCancelled>()));
    scheduleMicrotask(token.cancel);
    await check;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(backend.calls, isEmpty);
  });

  test('invalid JS error codes are not exposed as protocol codes', () async {
    final runtime = PluginRuntime(media: _Backend());
    addTearDown(runtime.dispose);
    await runtime.load(
      "module.exports = {platform:'P', search:function(){var e=new Error('demo');e.code='bad;code';throw e;}};",
    );
    await expectLater(
      runtime.call('search', []),
      throwsA(
        isA<PluginRuntimeException>().having((e) => e.code, 'code', isNull),
      ),
    );
  });

  test('malformed bridge IDs cannot inject code into settlement', () async {
    final backend = _Backend();
    final runtime = PluginRuntime(media: backend);
    addTearDown(runtime.dispose);
    await runtime.load('''
module.exports = {
  platform: 'P', marker: 'clean',
  attack: function () {
    sendMessage('__hostMedia', JSON.stringify({id: "1); __plugin.marker='injected'; //", operation:'search', platform:'youtube'}));
    sendMessage('__hostHttp', JSON.stringify({id: "1); __plugin.marker='injected'; //", url:'https://media.example/'}));
  }
};
''');
    await runtime.call('attack', []);
    expect(runtime.meta('marker'), 'clean');
    expect(backend.calls, isEmpty);
  });

  test('loading plugin metadata cannot start native media work', () async {
    final backend = _Backend();
    final runtime = PluginRuntime(media: backend);
    addTearDown(runtime.dispose);
    await runtime.load(
      "env.media.search('youtube','demo',1).catch(function(){}); module.exports={platform:'P'};",
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.calls, isEmpty);
  });

  test(
    'fire-and-forget media work is cancelled when the invocation ends',
    () async {
      final pending = Completer<Map<String, Object?>>();
      final backend = _Backend()..answer = (_) => pending.future;
      final runtime = PluginRuntime(media: backend);
      addTearDown(runtime.dispose);
      await runtime.load(
        "module.exports={platform:'P',search:function(){env.media.search('youtube','demo',1).catch(function(){});return {isEnd:true,data:[]};}};",
      );
      await runtime.call('search', []);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(backend.calls.isEmpty || backend.cancelled, true);
      pending.complete({'isEnd': true, 'data': []});
    },
  );

  test(
    'disposing a pending call stops its pump before releasing the engine',
    () async {
      final entered = Completer<void>();
      final pending = Completer<Map<String, Object?>>();
      final backend = _Backend()
        ..answer = (_) {
          entered.complete();
          return pending.future;
        };
      final runtime = PluginRuntime(media: backend);
      await runtime.load(_source);
      final result = runtime.call('search', ['demo', 1, 'music']);
      final check = expectLater(result, throwsA(isA<PluginRuntimeException>()));
      await entered.future;
      runtime.dispose();
      await check;
      pending.complete({'isEnd': true, 'data': []});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(backend.disposed, true);
      expect(
        () => runtime.meta('platform'),
        throwsA(isA<PluginRuntimeException>()),
      );
    },
  );

  test(
    'disposing while assets load never evaluates a released engine',
    () async {
      final runtime = PluginRuntime(media: _Backend());
      final loading = runtime.load(_source);
      final check = expectLater(
        loading,
        throwsA(isA<PluginRuntimeException>()),
      );
      runtime.dispose();
      await check;
      expect(
        () => runtime.hasFunction('search'),
        throwsA(isA<PluginRuntimeException>()),
      );
    },
  );

  test('runtime disposal disposes the backend', () async {
    final backend = _Backend();
    final runtime = PluginRuntime(media: backend);
    runtime.dispose();
    expect(backend.disposed, true);
  });
}
