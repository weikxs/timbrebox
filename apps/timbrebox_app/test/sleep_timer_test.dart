import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: '待解析',
);

void main() {
  test('set and cancel report state', () {
    final controller = AppController(engine: TestPlayerEngine());
    addTearDown(controller.dispose);

    expect(controller.hasSleepTimer, isFalse);
    controller.setSleepTimer(const Duration(minutes: 30));
    expect(controller.hasSleepTimer, isTrue);
    expect(controller.sleepTimerTotal, const Duration(minutes: 30));

    controller.setSleepTimer(null);
    expect(controller.hasSleepTimer, isFalse);
    expect(controller.sleepTimerTotal, isNull);
  });

  test('pauses playback when the timer elapses', () async {
    final controller = AppController(engine: TestPlayerEngine());
    addTearDown(controller.dispose);
    await controller.play(_track('a'));
    expect(controller.isPlaying, isTrue);

    controller.setSleepTimer(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 1300));

    expect(controller.isPlaying, isFalse);
    expect(controller.hasSleepTimer, isFalse);
  });
}
