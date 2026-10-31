import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_playback/timbrebox_playback.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';
import 'package:timbrebox_app/app/state/catalog_player_source_resolver.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/state/player_source_resolver.dart';

/// Real source -> application engine/controller -> native decoder. Opt-in,
/// muted, temporary repository; never changes the user's current queue/player.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('LIVE_PLUGIN_BASE64');
  const origin = String.fromEnvironment('LIVE_PLUGIN_ORIGIN');
  const query = String.fromEnvironment('LIVE_PLUGIN_QUERY');
  test(
    'real user reference opens through the app pipeline and native errors become failed',
    () async {
      final directory = await Directory.systemTemp.createTemp('live-pipeline-');
      addTearDown(() => directory.delete(recursive: true));
      final repository = PluginRepository(
        pluginsDirectory: () async => directory,
      );
      addTearDown(repository.dispose);
      final source = await repository.installSource(
        utf8.decode(base64Decode(encoded)),
        Uri.parse(origin),
      );
      addTearDown(source.dispose);
      final results = await source.search(
        SearchRequest(query: query, cancellation: CancellationToken()),
      );
      expect(results.items, isNotEmpty);
      final track = source.toCatalogTrack(results.items.first);
      final backend = MediaKitBackend();
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: CatalogPlayerSourceResolver(source),
      );
      final player = PlayerController(engine);
      addTearDown(player.dispose);
      await engine.setVolume(0);
      await player.play(track.candidate);
      // ignore: avoid_print
      print(
        jsonEncode({
          'appPipelineAfterPlay': engine.diagnostics,
          'state': player.value.status.name,
        }),
      );
      expect(player.value.status, PlaybackStatus.playing);
      await backend.positions
          .firstWhere((p) => p >= const Duration(seconds: 8))
          .timeout(const Duration(seconds: 25));
      await player.pause();
      expect(player.value.status, PlaybackStatus.paused);
      await engine.seek(const Duration(seconds: 3));
      await player.resume();
      expect(player.value.status, PlaybackStatus.playing);
      await player.stop();
      await player.play(track.candidate);
      expect(player.value.status, PlaybackStatus.playing);
      final reloaded = await backend.positions
          .firstWhere((p) => p >= const Duration(seconds: 2))
          .timeout(const Duration(seconds: 15));
      expect(reloaded.inMilliseconds, greaterThanOrEqualTo(2000));
      await player.stop();
      await player.release();

      // Deliberately invalid local bytes are a negative test, never audio evidence.
      final invalid = File('${directory.path}/invalid-media.dat');
      await invalid.writeAsString('Not an audio container');
      final badBackend = MediaKitBackend();
      final badEngine = NetworkPlayerEngine(
        backend: badBackend,
        resolver: const DefaultPlayerSourceResolver(),
      );
      final badPlayer = PlayerController(badEngine);
      addTearDown(badPlayer.dispose);
      await badEngine.setVolume(0);
      final nativeFailure = badBackend.failures.first.timeout(
        const Duration(seconds: 10),
      );
      final stateFailure = badPlayer.states
          .firstWhere((s) => s.status == PlaybackStatus.failed)
          .timeout(const Duration(seconds: 10));
      var completions = 0;
      final ended = badPlayer.completions.listen((_) => completions++);
      addTearDown(ended.cancel);
      await badPlayer.play(
        StreamCandidate(
          ref: const MediaRef(sourceId: 'local', itemId: 'invalid-fixture'),
          id: invalid.uri.toString(),
          label: 'negative-test',
        ),
      );
      await nativeFailure;
      final failure = await stateFailure;
      expect(failure.errorCode, 'native_playback_failed');
      expect(failure.errorMessage, isNot(contains(directory.path)));
      expect(completions, 0);
      // ignore: avoid_print
      print(
        jsonEncode({
          'realAppPipelineProgress': true,
          'minimumProgressSeconds': 8,
          'pauseResumeSeekReload': true,
          'nativeFailureObserved': true,
          'failedStateObserved': true,
          'noFalseCompletion': true,
          'mutedAcceptance': true,
        }),
      );
    },
    skip: encoded.isEmpty || origin.isEmpty || query.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
