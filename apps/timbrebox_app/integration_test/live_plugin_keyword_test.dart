import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';

/// Opt-in real keywords only; never plays audio or substitutes a link query.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('LIVE_PLUGIN_BASE64');
  const origin = String.fromEnvironment('LIVE_PLUGIN_ORIGIN');
  const query = String.fromEnvironment('LIVE_PLUGIN_QUERY');
  test(
    'live original YouTube keyword search and genuine second page',
    () async {
      expect(query, isNot(startsWith('http')));
      final directory = await Directory.systemTemp.createTemp(
        'keyword-acceptance-',
      );
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
      final watch = Stopwatch()..start();
      final first = await source.search(
        SearchRequest(query: query, cancellation: CancellationToken()),
      );
      expect(first.items, isNotEmpty);
      expect(first.nextCursor, isNotNull);
      final second = await source.search(
        SearchRequest(query: query, page: 2, cancellation: CancellationToken()),
      );
      expect(second.items, isNotEmpty);
      final previous = first.items.map((item) => item.ref.itemId).toSet();
      final fresh = second.items
          .where((item) => !previous.contains(item.ref.itemId))
          .length;
      expect(fresh, greaterThan(0));
      final matchingTitles = first.items
          .where((item) => item.title.contains(query))
          .length;
      expect(matchingTitles, greaterThan(0));
      // ignore: avoid_print
      print(
        jsonEncode({
          'realKeywordSearch': true,
          'originalDartSearchEnabled': const bool.fromEnvironment(
            'TIMBREBOX_YOUTUBE_DART_AUDIO_TEST',
          ),
          'firstPage': first.items.length,
          'secondPage': second.items.length,
          'newSecondPageIds': fresh,
          'matchingTitles': matchingTitles,
          'elapsedMs': watch.elapsedMilliseconds,
          'playbackAccepted': false,
        }),
      );
    },
    skip: encoded.isEmpty || origin.isEmpty || query.isEmpty,
    timeout: const Timeout(Duration(seconds: 65)),
  );
}
