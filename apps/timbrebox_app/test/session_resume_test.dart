import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/session_store.dart';

import 'support/test_player_engine.dart';

class _FakeSessionStore implements SessionStore {
  _FakeSessionStore(this._restored);
  RestoredSession? _restored;
  RestoredSession? lastSaved;

  @override
  Future<RestoredSession?> load() async => _restored;

  @override
  Future<void> save(
    List<CatalogTrack> queue,
    int currentIndex, {
    int positionMs = 0,
  }) async {
    lastSaved = RestoredSession(
      queue: queue,
      currentIndex: currentIndex,
      positionMs: positionMs,
    );
  }

  @override
  Future<void> clear() async => _restored = null;
}

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 5),
  quality: '待解析',
);

void main() {
  test('restores the saved playback position for the current track', () async {
    final store = _FakeSessionStore(
      RestoredSession(
        queue: [_track('a'), _track('b')],
        currentIndex: 0,
        positionMs: 90000, // 1:30
      ),
    );
    final controller =
        AppController(engine: TestPlayerEngine(), sessionStore: store);
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero); // let the async restore run

    expect(controller.currentTrack?.id, 'a');
    expect(controller.position, const Duration(milliseconds: 90000));
  });
}
