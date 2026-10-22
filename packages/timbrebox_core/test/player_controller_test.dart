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
}

class _FakePlayerEngine implements PlayerEngine {
  _FakePlayerEngine({this.failLoad = false, this.failPause = false});

  final bool failLoad;
  final bool failPause;
  final List<String> calls = [];

  @override
  Future<void> load(StreamCandidate candidate) async {
    calls.add('load');
    if (failLoad) throw StateError('load failed');
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
