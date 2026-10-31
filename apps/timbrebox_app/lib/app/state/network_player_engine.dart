import 'dart:async';

import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import 'package:timbrebox_playback/timbrebox_playback.dart';
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
        StartPositionLoad,
        PlaybackFailureEvents {
  NetworkPlayerEngine({
    required AudioBackend backend,
    PlayerSourceResolver? resolver,
    Duration resolveTimeout = maxResolveTime,
  }) : _resolver = resolver ?? const DefaultPlayerSourceResolver(),
       // ignore: prefer_initializing_formals
       _resolveTimeout = resolveTimeout,
       // ignore: prefer_initializing_formals
       _backend = backend {
    final native = _backend;
    if (native is AudioFailureEvents) {
      _failureSubscription = (native as AudioFailureEvents).failures.listen(
        (_) => _nativeFailed(),
      );
    }
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
  StreamSubscription<void>? _failureSubscription;
  final _failures = StreamController<SourceException>.broadcast();
  @override
  Stream<SourceException> get failures => _failures.stream;
  Completer<SourceException>? _openFailure;
  bool _opening = false;
  String _stage = 'idle';
  String? _failureStage, _errorCode;
  Map<String, Object?> get diagnostics => {
    'stage': _stage,
    'failureStage': ?_failureStage,
    'errorCode': ?_errorCode,
  };
  static const maxOpenTime = Duration(seconds: 15);

  SourceException _nativeError() => SourceException(
    AppStrings.t('stream.err.nativePlaybackFailed'),
    retryable: true,
    code: 'native_playback_failed',
  );

  void _nativeFailed() {
    if (_disposed || (!_loaded && !_opening)) return;
    final error = _nativeError();
    _failureStage = _opening ? 'opening' : 'playing';
    _stage = 'failed';
    _errorCode = error.code;
    _loadGeneration++;
    _loadCancellation?.cancel();
    _loaded = false;
    _opening = false;
    final opening = _openFailure;
    if (opening != null && !opening.isCompleted) opening.complete(error);
    _failures.add(error);
    unawaited(_run(() => _backend.stop()).catchError((_) {}));
  }

  Timer? _releaseTimer;
  Future<void> _operations = Future.value();
  var _loaded = false;
  var _sourceAssigned = false;
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
    _failureStage = null;
    _errorCode = null;
    await _run(_releaseLoadedSource);
    _stage = 'resolving';
    try {
      final source = await _resolveWithin(candidate, cancellation);
      await _run(() async {
        _ensureLive();
        if (generation != _loadGeneration) throw const OperationCancelled();
        await _backend.setReleaseMode(AudioReleaseMode.stop);
        _stage = 'opening';
        _opening = true;
        _sourceAssigned = true;
        final failed = _openFailure = Completer<SourceException>();
        try {
          final backend = _backend;
          final open = start != null && backend is StartPositionAudioBackend
              ? (backend as StartPositionAudioBackend).setSourceFrom(
                  source,
                  start,
                )
              : backend.setSource(source);
          await Future.any<void>([
            open,
            failed.future.then((error) => throw error),
            cancellation.whenCancelled.then(
              (_) => throw const OperationCancelled(),
            ),
          ]).timeout(maxOpenTime, onTimeout: () => throw _nativeError());
          if (generation != _loadGeneration) throw const OperationCancelled();
          _loaded = true;
          _stage = 'ready';
        } finally {
          if (identical(_openFailure, failed)) _openFailure = null;
          _opening = false;
        }
      });
    } catch (error) {
      if (generation == _loadGeneration) {
        _failureStage = _stage == 'resolving' ? 'resolving' : 'opening';
        _stage = 'failed';
        _errorCode = error is SourceException ? error.code : 'playback_failed';
        if (_failureStage == 'opening') {
          unawaited(_run(() => _backend.stop()).catchError((_) {}));
          if (error is! SourceException) {
            _errorCode = 'native_playback_failed';
            throw _nativeError();
          }
        }
      }
      rethrow;
    }
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
    if (_loaded) _stage = 'playing';
  });

  @override
  Future<void> pause() => _run(() async {
    _ensureLive();
    await _backend.pause();
    _stage = 'paused';
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
    return _run(() async {
      await _releaseLoadedSource();
      _stage = 'idle';
      _failureStage = null;
      _errorCode = null;
    });
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
    await _failureSubscription?.cancel();
    await _failures.close();
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
    if (!_loaded && !_sourceAssigned) return;
    await _backend.stop();
    await _backend.releaseSource();
    _loaded = false;
    _sourceAssigned = false;
    if (_stage != 'failed') _stage = 'released';
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
