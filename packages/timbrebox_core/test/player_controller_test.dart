import 'dart:async';

import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  const candidate = StreamCandidate(
    ref: MediaRef(sourceId: 'youtube', itemId: 'track-1'),
    id: 'stream-1',
    label: 'Standard',
  );

  test('projects loading and playback state through one engine', () async {
    final engine = _FakePlayerEngine();
    final controller = PlayerController(engine);

    await controller.play(candidate);
    await controller.pause();
    await controller.stop();
    await controller.release();

    expect(engine.calls, ['load', 'play', 'pause', 'stop', 'release']);
    expect(controller.value.status, PlaybackStatus.idle);
    await controller.dispose();
  });

  test('turns engine failures into a visible state', () async {
    final controller = PlayerController(_FakePlayerEngine(failLoad: true));

    await controller.play(candidate);

    expect(controller.value.status, PlaybackStatus.failed);
    expect(controller.value.errorMessage, contains('load failed'));
    await controller.dispose();
  });

  test(
    'keeps pause errors visible instead of throwing them to the UI',
    () async {
      final controller = PlayerController(_FakePlayerEngine(failPause: true));

      await controller.play(candidate);
      await controller.pause();

      expect(controller.value.status, PlaybackStatus.failed);
      expect(controller.value.errorMessage, contains('pause failed'));
      await controller.dispose();
    },
  );

  test(
    'forwards optional engine controls only when the engine supports them',
    () async {
      final engine = _ConfigurablePlayerEngine();
      final controller = PlayerController(engine);

      await controller.setReleaseAfterPause(false);
      await controller.setVolume(.35);

      expect(engine.releaseAfterPause, isFalse);
      expect(engine.volume, .35);
      await controller.dispose();
    },
  );

  test(
    'publishes a native playback completion to the application layer',
    () async {
      final engine = _CompletingPlayerEngine();
      final controller = PlayerController(engine);
      final completion = expectLater(controller.completions, emits(null));

      await controller.play(candidate);
      engine.complete();
      await completion;

      expect(controller.value.status, PlaybackStatus.idle);
      await controller.dispose();
    },
  );

  test(
    'a superseded play never starts and never overwrites the newer state',
    () async {
      final engine = _GatedPlayerEngine();
      final controller = PlayerController(engine);
      const second = StreamCandidate(
        ref: MediaRef(sourceId: 'youtube', itemId: 'track-2'),
        id: 'stream-2',
        label: 'Standard',
      );

      final first = controller.play(candidate);
      await Future<void>.delayed(Duration.zero);
      await controller.play(second);
      engine.releaseFirstLoad();
      await first;

      expect(engine.calls, ['load stream-1', 'load stream-2', 'play']);
      expect(controller.value.status, PlaybackStatus.playing);
      expect(controller.value.candidate, second);
      await controller.dispose();
    },
  );

  test('resume refuses after a failed load so the caller reloads', () async {
    final engine = _FakePlayerEngine(failLoad: true);
    final controller = PlayerController(engine);

    await controller.play(candidate);

    expect(await controller.resume(), isFalse);
    expect(engine.calls, ['load']);
    await controller.dispose();
  });

  test(
    'resume refuses after the track ended so the caller restarts it',
    () async {
      final engine = _CompletingPlayerEngine();
      final controller = PlayerController(engine);
      await controller.play(candidate);

      engine.complete();
      await Future<void>.delayed(Duration.zero);

      expect(await controller.resume(), isFalse);
      await controller.dispose();
    },
  );

  test('starts at a position when the engine can load from one', () async {
    final engine = _StartingPlayerEngine();
    final controller = PlayerController(engine);

    await controller.play(candidate, startAt: const Duration(seconds: 42));

    expect(engine.calls, ['load from 0:00:42.000000', 'play']);
    await controller.dispose();
  });

  test('loads from the beginning on an engine without start support', () async {
    final engine = _FakePlayerEngine();
    final controller = PlayerController(engine);

    await controller.play(candidate, startAt: const Duration(seconds: 42));

    expect(engine.calls, ['load', 'play']);
    await controller.dispose();
  });

  test('stopping during a load drops what that load ends with', () async {
    final engine = _CancellableLoadEngine();
    final controller = PlayerController(engine);

    final playing = controller.play(candidate);
    await Future<void>.delayed(Duration.zero);
    await controller.stop();
    engine.cancelLoad();
    await playing;

    expect(controller.value.status, PlaybackStatus.idle);
    expect(controller.value.errorMessage, isNull);
    expect(engine.calls, isNot(contains('play')));
    await controller.dispose();
  });

  test('a source failure shows its own message', () async {
    final controller = PlayerController(
      _FakePlayerEngine(
        loadError: const SourceException('Track expired', retryable: true),
      ),
    );

    await controller.play(candidate);

    expect(controller.value.errorMessage, 'Track expired');
    await controller.dispose();
  });
}

class _FakePlayerEngine implements PlayerEngine {
  _FakePlayerEngine({
    this.failLoad = false,
    this.failPause = false,
    this.loadError,
  });

  final bool failLoad;
  final bool failPause;
  final Object? loadError;
  final List<String> calls = [];

  @override
  Future<void> load(StreamCandidate candidate) async {
    calls.add('load');
    if (failLoad) throw StateError('load failed');
    if (loadError case final error?) throw error;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    if (failPause) throw StateError('pause failed');
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> release() async => calls.add('release');

  @override
  Future<void> stop() async => calls.add('stop');
}

class _ConfigurablePlayerEngine extends _FakePlayerEngine
    implements PauseReleaseConfig, VolumeControllablePlayerEngine {
  bool releaseAfterPause = true;
  double volume = 1;

  @override
  Future<void> setReleaseAfterPause(bool enabled) async {
    releaseAfterPause = enabled;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }
}

class _CompletingPlayerEngine extends _FakePlayerEngine
    implements PlaybackCompletionEvents {
  final StreamController<void> _events = StreamController.broadcast();

  @override
  Stream<void> get completed => _events.stream;

  void complete() => _events.add(null);

  @override
  Future<void> release() async {
    await super.release();
    await _events.close();
  }
}

class _GatedPlayerEngine extends _FakePlayerEngine {
  final _firstLoad = Completer<void>();

  void releaseFirstLoad() => _firstLoad.complete();

  @override
  Future<void> load(StreamCandidate candidate) async {
    calls.add('load ${candidate.id}');
    if (candidate.id == 'stream-1') await _firstLoad.future;
  }
}

class _StartingPlayerEngine extends _FakePlayerEngine
    implements StartPositionLoad {
  @override
  Future<void> loadFrom(StreamCandidate candidate, Duration start) async =>
      calls.add('load from $start');
}

/// A load that ends only when cancelled, the way the network engine's does
/// once a stop cancels it.
class _CancellableLoadEngine extends _FakePlayerEngine {
  final _cancelled = Completer<void>();

  void cancelLoad() => _cancelled.complete();

  @override
  Future<void> load(StreamCandidate candidate) async {
    calls.add('load');
    await _cancelled.future;
    throw const OperationCancelled();
  }
}
