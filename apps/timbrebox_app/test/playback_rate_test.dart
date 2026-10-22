import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

void main() {
  test('sets, clamps, and forwards the playback rate to the engine', () {
    final engine = TestPlayerEngine();
    final controller = AppController(engine: engine);
    addTearDown(controller.dispose);

    expect(controller.playbackRate, 1.0);

    controller.setPlaybackRate(1.5);
    expect(controller.playbackRate, 1.5);
    expect(engine.rate, 1.5);

    controller.setPlaybackRate(5.0); // clamped to 3.0
    expect(controller.playbackRate, 3.0);

    controller.setPlaybackRate(0.1); // clamped to 0.25
    expect(controller.playbackRate, 0.25);
  });
}
