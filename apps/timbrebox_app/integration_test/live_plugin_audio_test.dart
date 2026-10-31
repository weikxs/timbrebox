import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_playback/timbrebox_playback.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';

/// Explicit, online, muted acceptance in the real platform application.
/// Supply LIVE_PLUGIN_BASE64 with a reviewed plugin source (never credentials).
/// No fixture responses, egress exceptions or external extraction process.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('LIVE_PLUGIN_BASE64');
  const query = String.fromEnvironment(
    'LIVE_PLUGIN_QUERY',
    defaultValue: '公版 音乐',
  );
  const minimumProgressSeconds = int.fromEnvironment(
    'LIVE_PLUGIN_MIN_PROGRESS_SECONDS',
    defaultValue: 2,
  );
  const origin = String.fromEnvironment('LIVE_PLUGIN_ORIGIN');
  const linkTemplate = String.fromEnvironment('LIVE_PLUGIN_LINK_TEMPLATE');

  test(
    'live search, native audio, transport controls and saved-reference reload',
    () async {
      final directory = await Directory.systemTemp.createTemp('live-plugin-');
      addTearDown(() => directory.delete(recursive: true));
      final repository = PluginRepository(
        pluginsDirectory: () async => directory,
      );
      addTearDown(repository.dispose);
      final script = utf8.decode(base64Decode(encoded));
      final source = await repository.installSource(script, Uri.parse(origin));
      addTearDown(source.dispose);
      expect(source.isStarted, false);

      final results = await source.search(
        SearchRequest(query: query, cancellation: CancellationToken()),
      );
      expect(results.items, isNotEmpty);
      final selected = results.items.first;
      if (results.nextCursor != null) {
        final more = await source.search(
          SearchRequest(
            query: query,
            page: 2,
            cancellation: CancellationToken(),
          ),
        );
        final previous = results.items.map((item) => item.ref.itemId).toSet();
        expect(
          more.items.any((item) => !previous.contains(item.ref.itemId)),
          true,
        );
      }
      final saved = source.toCatalogTrack(selected);
      final hint = saved.resolveHint!;
      final hintText = jsonEncode(hint);
      expect(hintText, isNot(contains('buvid')));
      expect(hintText, isNot(contains('bilivideo')));

      final request = StreamRequest(
        ref: selected.ref,
        quality: 'standard',
        cancellation: CancellationToken(),
      );
      final media = await source.resolve(request);
      expect(media.uri.host, '127.0.0.1');
      expect(
        media.mimeType,
        isIn(['audio/mp4', 'audio/webm', 'video/mp4', 'video/webm']),
      );

      // Check real proxy bytes before waiting on the decoder. Metadata must
      // not turn an upstream refusal into an opaque playback timeout.
      final probe = HttpClient();
      try {
        final request = await probe.getUrl(media.uri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        var bytes = 0;
        await for (final chunk in response.timeout(
          const Duration(seconds: 15),
        )) {
          bytes += chunk.length;
          if (bytes >= 1024) break;
        }
        // ignore: avoid_print
        print(
          jsonEncode({
            'mediaProbeStatus': response.statusCode,
            'mediaProbeBytes': bytes,
            'mediaMime': media.mimeType,
          }),
        );
        expect(response.statusCode, isIn([200, 206]));
        expect(bytes, greaterThan(0));
      } finally {
        probe.close(force: true);
      }

      Player? player;
      final backend = MediaKitBackend(
        createPlayer: () {
          MediaKit.ensureInitialized();
          return player = Player(configuration: MediaKitBackend.configuration);
        },
      );
      addTearDown(backend.dispose);
      var position = Duration.zero;
      final subscription = backend.positions.listen(
        (value) => position = value,
      );
      addTearDown(subscription.cancel);
      await backend.setVolume(0); // Do not disturb the user's audio output.
      await backend.setSource(
        RemoteAudioSource(media.uri, allowInsecure: true),
      );
      final advancing = backend.positions
          .firstWhere(
            (value) => value >= const Duration(seconds: minimumProgressSeconds),
          )
          .timeout(const Duration(seconds: 25));
      await backend.resume();
      await advancing;
      final native = player!.platform! as NativePlayer;
      expect(await native.getProperty('vid'), 'no');
      expect(await native.getProperty('audio-codec-name'), isNotEmpty);
      expect(await native.getProperty('current-ao'), isNotEmpty);

      await backend.pause();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final paused = position;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(
        (position - paused).abs(),
        lessThan(const Duration(milliseconds: 400)),
      );
      final resumed = backend.positions
          .firstWhere(
            (value) => value > paused + const Duration(milliseconds: 500),
          )
          .timeout(const Duration(seconds: 10));
      await backend.resume();
      await resumed;

      // This query must return a track long enough to exercise an actual seek.
      expect(selected.duration, greaterThan(const Duration(seconds: 12)));
      final sought = backend.positions
          .firstWhere((value) => value >= const Duration(seconds: 9))
          .timeout(const Duration(seconds: 5));
      await backend.seek(const Duration(seconds: 10));
      await sought;
      await backend.stop();

      // A new source/runtime gets only a persisted, scrubbed stable reference.
      source.dispose();
      final reloaded = (await repository.loadInstalled()).single;
      addTearDown(reloaded.dispose);
      expect(reloaded.isStarted, false);
      reloaded.rememberHint(selected.ref.itemId, hint);
      final refreshed = await reloaded.resolve(
        StreamRequest(
          ref: selected.ref,
          quality: 'standard',
          cancellation: CancellationToken(),
        ),
      );
      expect(refreshed.uri.host, '127.0.0.1');
      expect(refreshed.uri, isNot(media.uri));
      final imported = await reloaded.search(
        SearchRequest(
          query: linkTemplate.replaceAll('{id}', selected.ref.itemId),
          cancellation: CancellationToken(),
        ),
      );
      expect(imported.items.single.ref, selected.ref);
      // Only counters and booleans: no signed media URLs, session or headers.
      // ignore: avoid_print
      print(
        jsonEncode({
          'liveSearchCount': results.items.length,
          'nativeAudioProgress': true,
          'minimumProgressSeconds': minimumProgressSeconds,
          'videoDecodingDisabled': true,
          'pauseResumeSeek': true,
          'savedReferenceReload': true,
          'canonicalLinkImport': true,
          'mutedAcceptance': true,
        }),
      );
    },
    skip: encoded.isEmpty || origin.isEmpty || linkTemplate.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
