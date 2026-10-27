import 'dart:async';

import '../model/search_models.dart';
import 'playback_state.dart';
import 'player_engine.dart';

class PlayerController {
  PlayerController(this._engine) {
    final engine = _engine;
    if (engine is PlaybackCompletionEvents) {
      final completionEvents = engine as PlaybackCompletionEvents;
      _completionSubscription = completionEvents.completed.listen((_) {
        _ended = true;
        _emit(
          PlaybackState(
            status: PlaybackStatus.idle,
            candidate: _value.candidate,
          ),
        );
        if (!_completions.isClosed) _completions.add(null);
      });
    }
  }

  final PlayerEngine _engine;
  final StreamController<PlaybackState> _states = StreamController.broadcast();
  final StreamController<void> _completions = StreamController.broadcast();
  StreamSubscription<void>? _completionSubscription;
  PlaybackState _value = const PlaybackState.idle();

  /// Bumped by every [play]; a load that finishes after a newer [play] began
  /// must neither start playing nor publish its state.
  var _generation = 0;

  /// The loaded source played to its end, so resuming it would play nothing.
  var _ended = false;

  PlaybackState get value => _value;
  Stream<PlaybackState> get states => _states.stream;
  Stream<void> get completions => _completions.stream;

  /// Loads and plays [candidate], from [startAt] when the engine supports
  /// starting at a position (see [StartPositionLoad]).
  Future<void> play(StreamCandidate candidate, {Duration? startAt}) async {
    final generation = ++_generation;
    _ended = false;
    _emit(PlaybackState(status: PlaybackStatus.loading, candidate: candidate));
    try {
      final engine = _engine;
      if (startAt != null &&
          startAt > Duration.zero &&
          engine is StartPositionLoad) {
        await (engine as StartPositionLoad).loadFrom(candidate, startAt);
      } else {
        await engine.load(candidate);
      }
      if (generation != _generation) return;
      await _engine.play();
      if (generation != _generation) return;
      _emit(
        PlaybackState(status: PlaybackStatus.playing, candidate: candidate),
      );
    } catch (error) {
      if (generation != _generation) return;
      _emit(
        PlaybackState(
          status: PlaybackStatus.failed,
          candidate: candidate,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  /// Resumes the currently-loaded source in place (keeping its position),
  /// without reloading from 0. Returns false if nothing is resumable (the
  /// source was released after a long pause, failed to load, or played to its
  /// end), so the caller can reload instead.
  Future<bool> resume() async {
    if (_value.candidate == null || _ended) return false;
    if (_value.status == PlaybackStatus.failed) return false;
    try {
      await _engine.play();
      _emit(
        PlaybackState(
          status: PlaybackStatus.playing,
          candidate: _value.candidate,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> pause() async {
    if (!_value.isPlaying) return;
    try {
      await _engine.pause();
      _emit(
        PlaybackState(
          status: PlaybackStatus.paused,
          candidate: _value.candidate,
        ),
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> stop() async {
    // A load still running belongs to the play this stop ends: whatever it
    // finishes with (usually OperationCancelled) must not show.
    _generation++;
    try {
      await _engine.stop();
      _emit(
        PlaybackState(status: PlaybackStatus.idle, candidate: _value.candidate),
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> release() async {
    _generation++;
    try {
      await _engine.release();
      _emit(const PlaybackState.idle());
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> setReleaseAfterPause(bool enabled) async {
    final engine = _engine;
    if (engine is PauseReleaseConfig) {
      await (engine as PauseReleaseConfig).setReleaseAfterPause(enabled);
    }
  }

  Future<void> setVolume(double volume) async {
    final engine = _engine;
    if (engine is VolumeControllablePlayerEngine) {
      await (engine as VolumeControllablePlayerEngine).setVolume(
        volume.clamp(0, 1),
      );
    }
  }

  Future<void> setRate(double rate) async {
    final engine = _engine;
    if (engine is RateControllablePlayerEngine) {
      await (engine as RateControllablePlayerEngine).setRate(rate);
    }
  }

  Future<void> dispose() async {
    await _completionSubscription?.cancel();
    await _completions.close();
    await _engine.release();
    await _states.close();
  }

  void _emit(PlaybackState state) {
    _value = state;
    if (!_states.isClosed) _states.add(state);
  }

  void _fail(Object error) {
    _emit(
      PlaybackState(
        status: PlaybackStatus.failed,
        candidate: _value.candidate,
        errorMessage: error.toString(),
      ),
    );
  }
}
