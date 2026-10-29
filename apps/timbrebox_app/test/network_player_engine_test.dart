import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_playback/timbrebox_playback.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/design/app_strings.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/catalog_player_source_resolver.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/state/player_source_resolver.dart';

void main() {
  const candidate = StreamCandidate(
    ref: MediaRef(sourceId: 'youtube', itemId: 'video-1'),
    id: 'tb://youtube/video-1',
    label: 'high',
  );

  test(
    'passes resolved headers through the engine without dropping them',
    () async {
      final source = AudioSourceSpec.remote(
        Uri.parse('https://cdn.example.test/audio.m4a'),
        headers: const {'Referer': 'https://example.test'},
      );
      final backend = _FakeAudioBackend();
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _FixedResolver(source),
      );

      await engine.load(candidate);

      expect(backend.source, same(source));
      expect((backend.source! as RemoteAudioSource).headers, {
        'Referer': 'https://example.test',
      });
      await engine.release();
    },
  );

  test(
    'loads a local file source through the same PlayerEngine contract',
    () async {
      final backend = _FakeAudioBackend();
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _FixedResolver(AudioSourceSpec.localFile('/tmp/track.m4a')),
      );

      await engine.load(candidate);

      expect(backend.source, isA<LocalAudioSource>());
      expect((backend.source! as LocalAudioSource).path, '/tmp/track.m4a');
      await engine.release();
    },
  );

  test('default resolver accepts HTTPS and local file URIs only', () async {
    const resolver = DefaultPlayerSourceResolver();
    final remote = await resolver.resolve(
      const StreamCandidate(
        ref: MediaRef(sourceId: 'youtube', itemId: 'x'),
        id: 'https://cdn.example.test/x.m4a',
        label: 'standard',
      ),
    );
    final local = await resolver.resolve(
      const StreamCandidate(
        ref: MediaRef(sourceId: 'local', itemId: 'x'),
        id: 'file:///tmp/x.m4a',
        label: 'offline',
      ),
    );

    expect(remote, isA<RemoteAudioSource>());
    expect(local, isA<LocalAudioSource>());
    await expectLater(
      resolver.resolve(
        const StreamCandidate(
          ref: MediaRef(sourceId: 'youtube', itemId: 'x'),
          id: 'http://cdn.example.test/x.m4a',
          label: 'standard',
        ),
      ),
      throwsStateError,
    );
  });

  test('a track saved from a retired source explains where it went', () async {
    AppStrings.lang = AppLang.en;
    addTearDown(() => AppStrings.lang = AppLang.zh);
    final catalog = BuiltInMusicCatalog.standard();
    final controller = AppController(
      engine: NetworkPlayerEngine(
        backend: _FakeAudioBackend(),
        resolver: CatalogPlayerSourceResolver(catalog.streamResolver),
      ),
      catalog: catalog,
    );
    addTearDown(controller.dispose);
    const saved = CatalogTrack(
      id: 'demo-item',
      title: 'Song',
      artist: 'Artist',
      sourceId: 'bilibili',
      sourceName: 'Bilibili',
      duration: Duration.zero,
      quality: 'standard',
    );

    await controller.play(saved);

    expect(
      controller.playbackError,
      contains('Bilibili is no longer built in'),
    );
    expect(controller.playbackError, contains('plugin'));
  });

  test(
    'a failed load stops the previous track instead of leaving it playing',
    () async {
      final backend = _FakeAudioBackend();
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _FailingAfterFirstResolver(
          AudioSourceSpec.remote(Uri.parse('https://cdn.example.test/a.m4a')),
        ),
      );
      await engine.load(candidate);
      await engine.play();
      backend.calls.clear();

      await expectLater(engine.load(candidate), throwsA(isA<StateError>()));

      expect(backend.calls, ['stop', 'releaseSource']);
      await expectLater(engine.play(), throwsA(isA<StateError>()));
      await engine.release();
    },
  );

  test('opens the source at a start position when the backend can', () async {
    final backend = _StartingAudioBackend();
    final engine = NetworkPlayerEngine(
      backend: backend,
      resolver: _FixedResolver(
        AudioSourceSpec.remote(Uri.parse('https://cdn.example.test/a.m4a')),
      ),
    );

    await engine.loadFrom(candidate, const Duration(seconds: 42));

    expect(backend.calls, contains('source from 0:00:42.000000'));
    await engine.release();
  });

  group('loads', () {
    StreamCandidate track(String id) => StreamCandidate(
      ref: MediaRef(sourceId: 'plugin_x', itemId: id),
      id: 'tb://plugin_x/$id',
      label: 'high',
    );

    test('a newer play cancels a slow load instead of queueing', () async {
      final backend = _FakeAudioBackend();
      final resolver = _SlowResolver();
      final engine = NetworkPlayerEngine(backend: backend, resolver: resolver);
      addTearDown(engine.release);

      final slow = expectLater(
        engine.load(track('slow')),
        throwsA(isA<OperationCancelled>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final watch = Stopwatch()..start();
      await engine.load(track('fast'));

      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      await slow;
      expect(resolver.cancelled, ['slow']);
      expect((backend.source! as RemoteAudioSource).uri.path, '/fast.m4a');
      expect(backend.calls.where((call) => call == 'source'), hasLength(1));
    });

    test('pause answers while a track is still resolving', () async {
      final backend = _FakeAudioBackend();
      final resolver = _SlowResolver();
      final engine = NetworkPlayerEngine(backend: backend, resolver: resolver);
      addTearDown(engine.release);

      final slow = expectLater(
        engine.load(track('slow')),
        throwsA(isA<OperationCancelled>()),
      );
      await engine.pause().timeout(const Duration(seconds: 2));
      await engine.stop().timeout(const Duration(seconds: 2));

      await slow;
      expect(resolver.cancelled, ['slow']);
      expect(backend.source, isNull);
    });

    test('a resolve that never ends gives up at the time cap', () async {
      final resolver = _SlowResolver();
      final engine = NetworkPlayerEngine(
        backend: _FakeAudioBackend(),
        resolver: resolver,
        resolveTimeout: const Duration(milliseconds: 60),
      );
      addTearDown(engine.release);

      await expectLater(
        engine.load(track('slow')).timeout(const Duration(seconds: 2)),
        throwsA(isA<SourceException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(resolver.cancelled, ['slow']);
    });
  });
}

/// Takes 30 s to resolve `slow` (unless cancelled); anything else at once.
class _SlowResolver implements PlayerSourceResolver {
  final cancelled = <String>[];

  @override
  Future<AudioSourceSpec> resolve(
    StreamCandidate candidate, {
    CancellationToken? cancellation,
  }) async {
    final id = candidate.ref.itemId;
    if (id == 'slow') {
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(end)) {
        if (cancellation?.isCancelled ?? false) {
          cancelled.add(id);
          throw const OperationCancelled();
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    return AudioSourceSpec.remote(
      Uri.parse('https://cdn.example.test/$id.m4a'),
    );
  }
}

class _FixedResolver implements PlayerSourceResolver {
  const _FixedResolver(this.source);

  final AudioSourceSpec source;

  @override
  Future<AudioSourceSpec> resolve(
    StreamCandidate candidate, {
    CancellationToken? cancellation,
  }) async => source;
}

class _FakeAudioBackend implements AudioBackend {
  final StreamController<void> _completed = StreamController.broadcast();
  AudioSourceSpec? source;
  final List<String> calls = [];

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> setReleaseMode(AudioReleaseMode mode) async {
    calls.add('releaseMode');
  }

  @override
  Future<void> setSource(AudioSourceSpec value) async {
    source = value;
    calls.add('source');
  }

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> releaseSource() async => calls.add('releaseSource');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume');

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _completed.close();
  }
}

class _FailingAfterFirstResolver implements PlayerSourceResolver {
  _FailingAfterFirstResolver(this.source);

  final AudioSourceSpec source;
  var _calls = 0;

  @override
  Future<AudioSourceSpec> resolve(
    StreamCandidate candidate, {
    CancellationToken? cancellation,
  }) async {
    if (_calls++ > 0) throw StateError('stream unavailable');
    return source;
  }
}

class _StartingAudioBackend extends _FakeAudioBackend
    implements StartPositionAudioBackend {
  @override
  Future<void> setSourceFrom(AudioSourceSpec value, Duration start) async {
    source = value;
    calls.add('source from $start');
  }
}
