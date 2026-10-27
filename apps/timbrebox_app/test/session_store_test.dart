import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/state/session_store.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('session'));
  tearDown(() => root.delete(recursive: true));

  FileSessionStore store() => FileSessionStore(directory: () async => root);

  test('a position update rewrites only the small position file', () async {
    final sessions = store();
    await sessions.save([_track('a'), _track('b')], 1, positionMs: 1000);
    final queueFile = File('${root.path}/session.json');
    final queueBefore = await queueFile.readAsString();

    await sessions.savePosition(42000);

    expect(await queueFile.readAsString(), queueBefore);
    final restored = await sessions.load();
    expect(restored!.currentIndex, 1);
    expect(restored.positionMs, 42000);
    expect(restored.queue.map((track) => track.id), ['a', 'b']);
  });

  test('a session saved by an older version still loads', () async {
    await File('${root.path}/session.json').writeAsString(
      jsonEncode({
        'currentIndex': 0,
        'positionMs': 90000,
        'queue': [_track('a').toJson()],
      }),
    );

    final restored = await store().load();

    expect(restored!.positionMs, 90000);
    expect(restored.queue.single.id, 'a');
  });

  test('playing ticks save the position, not the whole queue', () async {
    final sessions = _CountingSessionStore();
    final engine = _TickingEngine();
    final controller = AppController(engine: engine, sessionStore: sessions);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    await controller.play(_track('a'));
    final queueSaves = sessions.queueSaves;
    for (var second = 1; second <= 35; second++) {
      engine.emit(Duration(seconds: second));
    }

    expect(sessions.queueSaves, queueSaves);
    expect(sessions.positionSaves, 3);
    expect(sessions.lastPositionMs, 30000);

    controller.addNext(_track('b'));
    expect(sessions.queueSaves, queueSaves + 1);
  });
}

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 5),
  quality: 'public',
);

final class _CountingSessionStore implements SessionStore {
  var queueSaves = 0;
  var positionSaves = 0;
  var lastPositionMs = 0;

  @override
  Future<void> save(
    List<CatalogTrack> queue,
    int currentIndex, {
    int positionMs = 0,
  }) async {
    queueSaves++;
    lastPositionMs = positionMs;
  }

  @override
  Future<void> savePosition(int positionMs) async {
    positionSaves++;
    lastPositionMs = positionMs;
  }

  @override
  Future<RestoredSession?> load() async => null;

  @override
  Future<void> clear() async {}
}

final class _TickingEngine
    implements PlayerEngine, PlaybackProgressEvents, PauseReleaseConfig {
  final _positions = StreamController<Duration>.broadcast(sync: true);

  void emit(Duration value) => _positions.add(value);

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<Duration> get durations => const Stream.empty();

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> load(StreamCandidate candidate) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> release() async {}

  @override
  Future<void> setReleaseAfterPause(bool enabled) async {}
}
