import '../model/search_models.dart';

abstract interface class PlayerEngine {
  Future<void> load(StreamCandidate candidate);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> release();
}

/// Optional capability for engines that can release native decoders after a
/// paused period.  Keeping it separate lets the pure Dart controller stay
/// usable with deterministic test engines.
abstract interface class PauseReleaseConfig {
  Future<void> setReleaseAfterPause(bool enabled);
}

/// Optional capability for engines with a platform volume control.
abstract interface class VolumeControllablePlayerEngine {
  Future<void> setVolume(double volume);
}

/// Optional capability for engines that can change the playback rate (speed).
abstract interface class RateControllablePlayerEngine {
  Future<void> setRate(double rate);
}

/// Implemented by native engines that can report a natural end of playback.
///
/// Mode decisions stay above the adapter so every platform follows the same
/// queue, repeat and shuffle semantics.
abstract interface class PlaybackCompletionEvents {
  Stream<void> get completed;
}

/// Asynchronous failures after a native source has begun opening or playing.
/// Errors must be sanitized by the adapter; never expose transient media URLs.
abstract interface class PlaybackFailureEvents {
  Stream<SourceException> get failures;
}

/// Optional capability for engines that can open a source at a position, so
/// resuming does not depend on a seek that a not-yet-loaded stream may drop.
abstract interface class StartPositionLoad {
  Future<void> loadFrom(StreamCandidate candidate, Duration start);
}
