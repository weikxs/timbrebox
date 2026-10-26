import 'dart:async';

import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import 'audio_source.dart';
import 'player_backend.dart';
import 'player_source_resolver.dart';

/// Owns one native decoder and resolves a short-lived stream only on play.
///
/// Resolving runs outside the queue of decoder operations, so pause, seek or
/// volume never wait behind a slow source; each load has its own
/// cancellation, a newer load or a stop cancels it, and a load that is no
/// longer the latest never touches the decoder.
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
    Duration resolveTimeout = maxResolveTime,
  }) : _resolver = resolver ?? const DefaultPlayerSourceResolver(),
       // ignore: prefer_initializing_formals
       _resolveTimeout = resolveTimeout,
       // ignore: prefer_initializing_formals
       _backend = backend {
    _completionSubscription = _backend.completed.listen((_) {
      if (!_completed.isClosed) _completed.add(null);
    });
  }

  /// The longest a track may take to resolve (a plugin may try several
  /// qualities in turn) before its load gives up.
  static const maxResolveTime = Duration(seconds: 30);

  final AudioBackend _backend;
  final PlayerSourceResolver _resolver;
  final Duration _resolveTimeout;
  CancellationToken? _loadCancellation;
  var _loadGeneration = 0;
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

  Future<void> _load(StreamCandidate candidate, Duration? start) async {
    _ensureLive();
    final cancellation = _beginLoad();
    final generation = _loadGeneration;
    // Stop the previous track first: if resolving the new one fails,
    // nothing must keep playing (or be resumable) under the new name.
    await _run(_releaseLoadedSource);
    final source = await _resolveWithin(candidate, cancellation);
    await _run(() async {
      _ensureLive();
      // A newer load or a stop took over while this one resolved.
      if (generation != _loadGeneration) throw const OperationCancelled();
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
  }

  /// Cancels the load in flight (if any) and returns the next one's token.
  CancellationToken _beginLoad() {
    _loadCancellation?.cancel();
    _loadGeneration++;
    return _loadCancellation = CancellationToken();
  }

  Future<AudioSourceSpec> _resolveWithin(
    StreamCandidate candidate,
    CancellationToken cancellation,
  ) async {
    final AudioSourceSpec source;
    try {
      source = await _resolver
          .resolve(candidate, cancellation: cancellation)
          .timeout(_resolveTimeout);
    } on TimeoutException {
      cancellation.cancel();
      throw SourceException(
        AppStrings.t('stream.err.resolveTimeout'),
        retryable: true,
        code: 'resolve_timeout',
      );
    }
    cancellation.throwIfCancelled();
    return source;
  }

  @override
  Future<void> play() => _run(() async {
    _ensureLive();
    _releaseTimer?.cancel();
    if (!_loaded) throw StateError(AppStrings.t('stream.err.notLoaded'));
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
  Future<void> stop() {
    _beginLoad().cancel();
    return _run(_releaseLoadedSource);
  }

  @override
  Future<void> release() {
    _beginLoad().cancel();
    return _run(_dispose);
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    await _releaseLoadedSource();
    _disposed = true;
    await _completionSubscription?.cancel();
    await _completed.close();
    await _backend.dispose();
  }

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
    if (_disposed) throw StateError(AppStrings.t('stream.err.engineReleased'));
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
