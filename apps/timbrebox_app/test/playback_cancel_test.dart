import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/audio_source.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/state/player_backend.dart';
import 'package:timbrebox_app/app/state/player_source_resolver.dart';

/// A plugin track can take many seconds to resolve. The play/pause button
/// must answer meanwhile instead of being ignored until the load ends.
void main() {
  test('play/pause during a load cancels it', () async {
    final resolver = _NeverResolves();
    final controller = AppController(
      engine: NetworkPlayerEngine(backend: _Backend(), resolver: resolver),
    );
    addTearDown(controller.dispose);

    final playing = controller.play(_track);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.isLoading, isTrue);

    await controller.togglePlayback().timeout(const Duration(seconds: 2));
    await playing.timeout(const Duration(seconds: 2));

    expect(controller.isLoading, isFalse);
    expect(controller.isPlaying, isFalse);
    expect(controller.playbackError, isNull);
    expect(resolver.cancelled, isTrue);
  });
}

const _track = CatalogTrack(
  id: 'slow',
  title: 'Slow',
  artist: 'Artist',
  sourceId: 'plugin_x',
  sourceName: 'X',
  duration: Duration(minutes: 3),
  quality: 'high',
);

final class _NeverResolves implements PlayerSourceResolver {
  var cancelled = false;

  @override
  Future<AudioSourceSpec> resolve(
    StreamCandidate candidate, {
    CancellationToken? cancellation,
  }) async {
    while (!(cancellation?.isCancelled ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    cancelled = true;
    throw const OperationCancelled();
  }
}

final class _Backend implements AudioBackend {
  @override
  Stream<void> get completed => const Stream.empty();

  @override
  Future<void> setReleaseMode(AudioReleaseMode mode) async {}

  @override
  Future<void> setSource(AudioSourceSpec source) async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> releaseSource() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}
