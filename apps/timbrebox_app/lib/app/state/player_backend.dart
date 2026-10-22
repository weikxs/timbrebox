import 'audio_source.dart';

enum AudioReleaseMode { stop, loop }

/// Small platform adapter kept behind the app-level player engine.
///
/// The interface is deliberately narrower than the underlying player so the
/// backend can be swapped (media_kit today) without changing PlayerEngine or UI
/// code.
abstract interface class AudioBackend {
  Stream<void> get completed;

  Future<void> setReleaseMode(AudioReleaseMode mode);

  Future<void> setSource(AudioSourceSpec source);

  Future<void> resume();

  Future<void> pause();

  Future<void> stop();

  Future<void> releaseSource();

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

/// Optional native capability to change the playback rate (speed). Separate so
/// the core AudioBackend contract (and its test fakes) stays minimal.
abstract interface class RateAudioBackend {
  Future<void> setRate(double rate);
}

/// Optional native progress capability. Keeping it separate preserves the
/// tiny backend contract used by deterministic tests and CLI adapters.
abstract interface class ProgressAudioBackend {
  Stream<Duration> get positions;

  Stream<Duration> get durations;

  Future<void> seek(Duration position);
}
