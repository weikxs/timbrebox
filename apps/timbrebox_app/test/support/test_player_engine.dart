import 'package:timbrebox_core/timbrebox_core.dart';

final class TestPlayerEngine
    implements
        PlayerEngine,
        PauseReleaseConfig,
        VolumeControllablePlayerEngine,
        RateControllablePlayerEngine {
  StreamCandidate? candidate;
  var isPlaying = false;
  var rate = 1.0;

  @override
  Future<void> load(StreamCandidate value) async => candidate = value;

  @override
  Future<void> play() async => isPlaying = true;

  @override
  Future<void> pause() async => isPlaying = false;

  @override
  Future<void> stop() async => isPlaying = false;

  @override
  Future<void> release() async {
    candidate = null;
    isPlaying = false;
  }

  @override
  Future<void> setReleaseAfterPause(bool enabled) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setRate(double value) async => rate = value;
}
