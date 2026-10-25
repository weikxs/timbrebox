import 'dart:async';

import 'package:timbrebox_core/timbrebox_core.dart';

import 'player_backend.dart';
import 'player_source_resolver.dart';

/// Owns one native decoder and resolves a short-lived stream only on play.
class NetworkPlayerEngine
    implements
        PlayerEngine,
        PauseReleaseConfig,
        VolumeControllablePlayerEngine,
        RateControllablePlayerEngine,
        PlaybackCompletionEvents,
        PlaybackProgressEvents,
        StartPositionLoad {
  NetworkPlayerEngine({
    required AudioBackend backend,
    PlayerSourceResolver? resolver,
  }) : _resolver = resolver ?? const DefaultPlayerSourceResolver(),
       // ignore: prefer_initializing_formals
       _backend = backend {
    _completionSubscription = _backend.completed.listen((_) {
      if (!_completed.isClosed) _completed.add(null);
    });
  }

  final AudioBackend _backend;
  final PlayerSourceResolver _resolver;
  final StreamController<void> _completed = StreamController.broadcast();
  StreamSubscription<void>? _completionSubscription;
  Timer? _releaseTimer;
  Future<void> _operations = Future.value();
  var _loaded = false;
  var _releaseAfterPause = true;
  var _disposed = false;
  var _generation = 0;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<Duration> get positions => switch (_backend) {
    ProgressAudioBackend backend => backend.positions,
    _ => const Stream<Duration>.empty(),
  };

  @override
  Stream<Duration> get durations => switch (_backend) {
    ProgressAudioBackend backend => backend.durations,
    _ => const Stream<Duration>.empty(),
  };

  @override
  Future<void> seek(Duration position) => _run(() async {
    _ensureLive();
    final backend = _backend;
    if (backend is! ProgressAudioBackend) return;
    await (backend as ProgressAudioBackend).seek(position);
  });

  @override
  Future<void> load(StreamCandidate candidate) => _load(candidate, null);

  @override
  Future<void> loadFrom(StreamCandidate candidate, Duration start) =>
      _load(candidate, start);

  Future<void> _load(StreamCandidate candidate, Duration? start) =>
      _run(() async {
        _ensureLive();
        // Stop the previous track first: if resolving the new one fails,
        // nothing must keep playing (or be resumable) under the new name.
        await _releaseLoadedSource();
        final source = await _resolver.resolve(candidate);
        _ensureLive();
        await _backend.setReleaseMode(AudioReleaseMode.stop);
        final backend = _backend;
        if (start != null && backend is StartPositionAudioBackend) {
          await (backend as StartPositionAudioBackend).setSourceFrom(
            source,
            start,
          );
        } else {
          await backend.setSource(source);
        }
        _loaded = true;
      });

  @override
  Future<void> play() => _run(() async {
    _ensureLive();
    _releaseTimer?.cancel();
    if (!_loaded) throw StateError('播放前必须先解析音频流。');
    await _backend.resume();
  });

  @override
  Future<void> pause() => _run(() async {
    _ensureLive();
    await _backend.pause();
    if (_releaseAfterPause) {
      final generation = _generation;
      _releaseTimer = Timer(const Duration(seconds: 30), () {
        if (generation == _generation) unawaited(_releaseLoadedSource());
      });
    }
  });

  @override
  Future<void> stop() => _run(_releaseLoadedSource);

  @override
  Future<void> release() => _run(() async {
    if (_disposed) return;
    await _releaseLoadedSource();
    _disposed = true;
    await _completionSubscription?.cancel();
    await _completed.close();
    await _backend.dispose();
  });

  @override
  Future<void> setReleaseAfterPause(bool enabled) async {
    _releaseAfterPause = enabled;
    if (!enabled) _releaseTimer?.cancel();
  }

  @override
  Future<void> setVolume(double volume) =>
      _run(() => _backend.setVolume(volume.clamp(0, 1)));

  @override
  Future<void> setRate(double rate) => _run(() async {
    final backend = _backend;
    if (backend is RateAudioBackend) {
      await (backend as RateAudioBackend).setRate(rate);
    }
  });

  Future<void> _releaseLoadedSource() async {
    _generation++;
    _releaseTimer?.cancel();
    if (!_loaded) return;
    await _backend.stop();
    await _backend.releaseSource();
    _loaded = false;
  }

  void _ensureLive() {
    if (_disposed) throw StateError('音频引擎已经释放。');
  }

  Future<T> _run<T>(Future<T> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }
}

/// Progress is intentionally an app capability instead of a required core
/// engine method, so headless and CLI engines do not need native position APIs.
abstract interface class PlaybackProgressEvents {
  Stream<Duration> get positions;

  Stream<Duration> get durations;

  Future<void> seek(Duration position);
}
