import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_playback/timbrebox_playback.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/state/player_source_resolver.dart';

const candidate = StreamCandidate(
  ref: MediaRef(sourceId: 'fixture', itemId: 'one'),
  id: 'fixture',
  label: 'standard',
);
void main() {
  test(
    'native asynchronous failure replaces playing and is not a natural completion',
    () async {
      final backend = _Backend();
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _Resolver(),
      );
      final player = PlayerController(engine);
      addTearDown(player.dispose);
      await player.play(candidate);
      expect(player.value.status, PlaybackStatus.playing);
      final failed = expectLater(
        player.states,
        emitsThrough(
          isA<PlaybackState>().having(
            (s) => s.status,
            'status',
            PlaybackStatus.failed,
          ),
        ),
      );
      backend.errors.add(null);
      await failed;
      expect(player.value.errorCode, 'native_playback_failed');
      expect(engine.diagnostics['failureStage'], 'playing');
      backend.ends.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(player.value.status, PlaybackStatus.failed);
      expect(player.value.errorMessage, isNot(contains('https://')));
    },
  );
  test(
    'failure during a pending open wakes the load and cannot later report playing',
    () async {
      final gate = Completer<void>();
      final backend = _Backend()..opening = gate;
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _Resolver(),
      );
      final player = PlayerController(engine);
      addTearDown(player.dispose);
      final load = player.play(candidate);
      for (var i = 0; i < 40 && !backend.entered; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(backend.entered, true);
      backend.errors.add(null);
      await load.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(player.value.status, PlaybackStatus.failed);
      expect(backend.resumes, 0);
      expect(engine.diagnostics['failureStage'], 'opening');
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.value.status, PlaybackStatus.failed);
      backend.opening = null;
      await player.play(candidate);
      expect(player.value.status, PlaybackStatus.playing);
      expect(player.value.errorCode, null);
    },
  );
  test(
    'cancelling an unfinished native open actually stops the assigned source',
    () async {
      final gate = Completer<void>();
      final backend = _Backend()..opening = gate;
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _Resolver(),
      );
      final player = PlayerController(engine);
      addTearDown(player.dispose);
      final load = player.play(candidate);
      for (var i = 0; i < 40 && !backend.entered; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(backend.entered, true);
      await player.stop().timeout(const Duration(seconds: 1));
      await load;
      expect(backend.stops, greaterThan(0));
      expect(player.value.status, PlaybackStatus.idle);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(engine.diagnostics['stage'], 'idle');
    },
  );

  test('idle or stopped engine ignores unowned native errors', () async {
    final backend = _Backend();
    final engine = NetworkPlayerEngine(backend: backend, resolver: _Resolver());
    final player = PlayerController(engine);
    addTearDown(player.dispose);
    backend.errors.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(player.value.status, PlaybackStatus.idle);
    await player.play(candidate);
    await player.stop();
    backend.errors.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(player.value.status, PlaybackStatus.idle);
  });
  test(
    'resolution failure preserves the source code and never reaches the native opener',
    () async {
      final backend = _Backend();
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _Resolver(fail: true),
      );
      final player = PlayerController(engine);
      addTearDown(player.dispose);
      await player.play(candidate);
      expect(player.value.errorCode, 'content_unverified');
      expect(engine.diagnostics, {
        'stage': 'failed',
        'failureStage': 'resolving',
        'errorCode': 'content_unverified',
      });
      expect(backend.entered, false);
    },
  );
  test(
    'raw synchronous decoder errors are replaced by a safe native error',
    () async {
      final backend = _Backend()..throwOnOpen = true;
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _Resolver(),
      );
      final player = PlayerController(engine);
      addTearDown(player.dispose);
      await player.play(candidate);
      expect(player.value.errorCode, 'native_playback_failed');
      expect(player.value.errorMessage, isNot(contains('secret')));
      expect(engine.diagnostics['failureStage'], 'opening');
    },
  );
}

class _Resolver implements PlayerSourceResolver {
  _Resolver({this.fail = false});
  final bool fail;
  @override
  Future<AudioSourceSpec> resolve(
    StreamCandidate candidate, {
    CancellationToken? cancellation,
  }) async {
    if (fail) {
      throw const SourceException(
        'Permission unverified',
        retryable: false,
        code: 'content_unverified',
      );
    }
    return AudioSourceSpec.remote(Uri.parse('https://fixture.example/audio'));
  }
}

class _Backend implements AudioBackend, AudioFailureEvents {
  final errors = StreamController<void>.broadcast();
  final ends = StreamController<void>.broadcast();
  Completer<void>? opening;
  bool entered = false, throwOnOpen = false;
  int resumes = 0, stops = 0;
  @override
  Stream<void> get failures => errors.stream;
  @override
  Stream<void> get completed => ends.stream;
  @override
  Future<void> setSource(AudioSourceSpec source) async {
    entered = true;
    if (throwOnOpen) throw StateError('https://fixture.example/secret');
    await opening?.future;
  }

  @override
  Future<void> setReleaseMode(AudioReleaseMode mode) async {}
  @override
  Future<void> resume() async {
    resumes++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> releaseSource() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {
    await errors.close();
    await ends.close();
  }
}
