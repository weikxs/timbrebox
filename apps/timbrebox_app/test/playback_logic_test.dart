import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/state/session_store.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  final a = _track('a');
  final b = _track('b');
  final c = _track('c');
  final x = _track('x');

  List<String> ids(AppController controller) =>
      controller.queue.map((t) => t.id).toList();

  test(
    'a repeated track in the queue does not loop back to its first copy',
    () async {
      final controller = AppController(engine: _ProgressEngine());
      addTearDown(controller.dispose);
      await controller.play(a);
      controller.addNext(b);
      controller.addNext(a); // queue: a, a, b

      await controller.next();
      await controller.next();

      expect(ids(controller), ['a', 'a', 'b']);
      expect(controller.currentTrack?.ref, b.ref);
    },
  );

  test('playing a list replaces the queue in the list order', () async {
    final controller = AppController(engine: _ProgressEngine());
    addTearDown(controller.dispose);
    await controller.play(x);
    controller.addNext(b); // queue: x, b

    await controller.playAll([a, b, c]);
    await controller.next();

    expect(ids(controller), ['a', 'b', 'c']);
    expect(controller.currentTrack?.ref, b.ref);
  });

  test(
    'removing the playing track from the queue does not skip the next one',
    () async {
      final controller = AppController(engine: _ProgressEngine());
      addTearDown(controller.dispose);
      await controller.playAll([a, b, c]);

      controller.removeFromQueue(0);
      await controller.next();

      expect(controller.currentTrack?.ref, b.ref);
    },
  );

  test(
    'a slow earlier play does not overwrite the track chosen after it',
    () async {
      final engine = _ProgressEngine()..gate = Completer<void>();
      final controller = AppController(engine: engine);
      addTearDown(controller.dispose);

      final first = controller.play(a);
      await Future<void>.delayed(Duration.zero);
      engine.gate = null;
      await controller.play(b);
      engine.releaseGate();
      await first;

      expect(controller.currentTrack?.ref, b.ref);
      expect(controller.isPlaying, isTrue);
      expect(engine.played, ['b']);
    },
  );

  test(
    'resuming after the paused source was released keeps the position',
    () async {
      final engine = _ProgressEngine();
      final controller = AppController(engine: engine);
      addTearDown(controller.dispose);
      await controller.play(a);
      engine.emitPosition(const Duration(seconds: 90));
      await Future<void>.delayed(Duration.zero);
      await controller.togglePlayback(); // pause
      engine.releaseSource(); // what the 30 s release timer does
      await Future<void>.delayed(Duration.zero);
      expect(controller.position, const Duration(seconds: 90));

      await controller.togglePlayback(); // play again

      expect(controller.isPlaying, isTrue);
      expect(engine.startedAt, [const Duration(seconds: 90)]);
      expect(engine.seeks, isEmpty);
    },
  );

  test('pausing saves the current position for the next launch', () async {
    final sessions = _RecordingSessionStore();
    final engine = _ProgressEngine();
    final controller = AppController(engine: engine, sessionStore: sessions);
    addTearDown(controller.dispose);
    await controller.play(a);
    engine.emitPosition(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);

    await controller.togglePlayback(); // pause

    expect(sessions.lastPositionMs, 42000);
  });

  test(
    'a sleep timer that ends while a track is loading still pauses',
    () async {
      final engine = _ProgressEngine()..gate = Completer<void>();
      final controller = AppController(engine: engine);
      addTearDown(controller.dispose);

      final loading = controller.play(a);
      controller.setSleepTimer(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      engine.releaseGate();
      await loading;

      expect(controller.isPlaying, isFalse);
      expect(controller.hasSleepTimer, isFalse);
    },
  );
}

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: 'public',
);

/// An engine with progress events whose loads can be held open, and whose
/// loaded source can be released like the real pause-release timer does.
final class _ProgressEngine
    implements
        PlayerEngine,
        PlaybackProgressEvents,
        PauseReleaseConfig,
        VolumeControllablePlayerEngine,
        StartPositionLoad {
  final _positions = StreamController<Duration>.broadcast();
  final List<String> played = [];
  final List<Duration> seeks = [];
  final List<Duration> startedAt = [];
  Completer<void>? gate;
  Completer<void>? _held;
  StreamCandidate? _loading;
  StreamCandidate? _loaded;

  void emitPosition(Duration value) => _positions.add(value);

  /// What the pause-release timer does: the source goes away and the native
  /// player reports position 0.
  void releaseSource() {
    _loaded = null;
    _positions.add(Duration.zero);
  }

  void releaseGate() => _held?.complete();

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<Duration> get durations => const Stream.empty();

  @override
  Future<void> load(StreamCandidate candidate) async {
    _loading = candidate;
    final hold = gate;
    if (hold != null) {
      _held = hold;
      await hold.future;
    }
    _loaded = candidate;
  }

  @override
  Future<void> loadFrom(StreamCandidate candidate, Duration start) async {
    startedAt.add(start);
    await load(candidate);
  }

  @override
  Future<void> play() async {
    final loaded = _loaded;
    if (loaded == null) throw StateError('nothing loaded');
    if (_loading != null && loaded.ref == _loading!.ref) {
      played.add(loaded.ref.itemId);
    }
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async => _loaded = null;

  @override
  Future<void> release() async => _loaded = null;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setReleaseAfterPause(bool enabled) async {}

  @override
  Future<void> setVolume(double volume) async {}
}

final class _RecordingSessionStore implements SessionStore {
  int? lastPositionMs;

  @override
  Future<void> save(
    List<CatalogTrack> queue,
    int currentIndex, {
    int positionMs = 0,
  }) async => lastPositionMs = positionMs;

  @override
  Future<void> savePosition(int positionMs) async =>
      lastPositionMs = positionMs;

  @override
  Future<RestoredSession?> load() async => null;

  @override
  Future<void> clear() async {}
}
