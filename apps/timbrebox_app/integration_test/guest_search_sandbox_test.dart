import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';

/// Explicit real-network search acceptance only. Not playback acceptance.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('TIMBREBOX_GUEST_SEARCH_TEST');
  const encoded = String.fromEnvironment('LIVE_GUEST_PLUGIN_BASE64');
  const origin = String.fromEnvironment('LIVE_GUEST_PLUGIN_ORIGIN');
  const platform = String.fromEnvironment(
    'LIVE_GUEST_PLATFORM',
    defaultValue: 'tiktok',
  );
  const query = String.fromEnvironment(
    'LIVE_GUEST_QUERY',
    defaultValue: 'music',
  );
  test(
    'official guest search through real plugin JS, fixed RPC and native sandbox',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'guest-search-acceptance-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final repository = PluginRepository(
        pluginsDirectory: () async => temporary,
      );
      addTearDown(repository.dispose);
      final source = await repository.installSource(
        utf8.decode(base64Decode(encoded)),
        Uri.parse(origin),
      );
      addTearDown(source.dispose);
      expect(source.isStarted, isFalse);
      final stopwatch = Stopwatch()..start();
      final first = await source
          .search(
            SearchRequest(query: query, cancellation: CancellationToken()),
          )
          .catchError((Object error, StackTrace stack) async {
            const channel = MethodChannel('timbrebox/guest_search');
            final state = await channel.invokeMapMethod<String, Object?>(
              'state',
            );
            // ignore: avoid_print
            print(jsonEncode({'guestSearchDiagnostic': state}));
            Error.throwWithStackTrace(error, stack);
          });
      expect(first.items, isNotEmpty);
      expect(first.nextCursor, isNotNull);
      final second = await source.search(
        SearchRequest(query: query, page: 2, cancellation: CancellationToken()),
      );
      expect(second.items, isNotEmpty);
      final previous = first.items.map((item) => item.ref.itemId).toSet();
      expect(
        second.items.every((item) => !previous.contains(item.ref.itemId)),
        isTrue,
      );
      previous.addAll(second.items.map((item) => item.ref.itemId));
      var verifiedPages = 2;
      var nextCursor = second.nextCursor;
      const maximumPages = int.fromEnvironment(
        'LIVE_GUEST_MAX_PAGES',
        defaultValue: 5,
      );
      expect(maximumPages, inInclusiveRange(2, 5));
      for (var page = 3; page <= maximumPages && nextCursor != null; page++) {
        final more = await source.search(
          SearchRequest(
            query: query,
            page: page,
            cancellation: CancellationToken(),
          ),
        );
        expect(more.items, isNotEmpty);
        for (final item in more.items) {
          expect(previous.add(item.ref.itemId), isTrue);
        }
        nextCursor = more.nextCursor;
        verifiedPages++;
      }
      if (const bool.fromEnvironment('LIVE_GUEST_RESOLVE_DIAGNOSTIC')) {
        final selected = first.items.first;
        try {
          await source.resolve(
            StreamRequest(
              ref: selected.ref,
              quality: 'standard',
              cancellation: CancellationToken(),
            ),
          );
          // ignore: avoid_print
          print(
            jsonEncode({'guestResolveDiagnostic': 'resolved_without_playback'}),
          );
        } on SourceException catch (error) {
          // ignore: avoid_print
          print(jsonEncode({'guestResolveDiagnostic': error.code}));
        }
      }
      const channel = MethodChannel('timbrebox/guest_search');
      final state = await channel.invokeMapMethod<String, Object?>('state');
      for (final key in ['active', 'hasView', 'hasWindow']) {
        expect(state?[key], false);
      }
      // ignore: avoid_print
      print(
        jsonEncode({
          'guestSearchPlatform': platform,
          'firstPage': first.items.length,
          'secondPage': second.items.length,
          'distinctPages': true,
          'verifiedPages': verifiedPages,
          'uniqueResults': previous.length,
          'nativeReleased': true,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'playbackAccepted': false,
        }),
      );
    },
    skip: !enabled || encoded.isEmpty || origin.isEmpty,
    timeout: const Timeout(Duration(seconds: 75)),
  );

  test(
    'guest searches never attach a window while active and cancel cleanly',
    () async {
      const channel = MethodChannel('timbrebox/guest_search');
      for (final site in ['tiktok', 'douyin']) {
        final id = site == 'tiktok'
            ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            : 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        final task = channel.invokeMapMethod<String, Object?>('search', {
          'jobId': id,
          'platform': site,
          'query': 'music',
          'wanted': 10,
          'seenIds': <String>[],
        });
        final cancelled = expectLater(
          task,
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'guest_search_cancelled',
            ),
          ),
        );
        try {
          await _waitForJobs(channel, 1);
          for (var sample = 0; sample < 10; sample++) {
            final state = await channel.invokeMapMethod<String, Object?>(
              'state',
            );
            expect(state?['active'], true);
            expect(state?['hasView'], true);
            expect(state?['hasWindow'], false);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        } finally {
          await channel.invokeMethod<void>('cancel', {'jobId': id});
          await cancelled;
        }
        final state = await channel.invokeMapMethod<String, Object?>('state');
        for (final key in ['active', 'hasView', 'hasWindow']) {
          expect(state?[key], false);
        }
      }
      // ignore: avoid_print
      print(
        jsonEncode({
          'guestSearchNoWindows': true,
          'platformsChecked': 2,
          'activeViewObserved': true,
          'cancelReleased': true,
          'searchSuccessClaimed': false,
        }),
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'two platform jobs are isolated; cancelling one preserves the other',
    () async {
      const channel = MethodChannel('timbrebox/guest_search');
      const dyId = 'dddddddddddddddddddddddddddddddd';
      const ttId = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      final dy = channel.invokeMapMethod<String, Object?>('search', {
        'jobId': dyId,
        'platform': 'douyin',
        'query': '音乐',
        'wanted': 10,
        'seenIds': <String>[],
      });
      final cancellation = expectLater(
        dy,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'guest_search_cancelled',
          ),
        ),
      );
      await _waitForJobs(channel, 1);
      final tt = channel.invokeMapMethod<String, Object?>('search', {
        'jobId': ttId,
        'platform': 'tiktok',
        'query': 'music',
        'wanted': 10,
        'seenIds': <String>[],
      });
      await _waitForJobs(channel, 2);
      await channel.invokeMethod<void>('cancel', {'jobId': dyId});
      await cancellation;
      final result = await tt;
      expect(result?['data'] as List, isNotEmpty);
      await _waitForJobs(channel, 0);
      // ignore: avoid_print
      print(
        jsonEncode({
          'guestSearchConcurrentIsolation': true,
          'cancelReleased': true,
        }),
      );
    },
    skip: !enabled || platform != 'tiktok',
    timeout: const Timeout(Duration(seconds: 40)),
  );
}

Future<void> _waitForJobs(MethodChannel channel, int count) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final state = await channel.invokeMapMethod<String, Object?>('state');
    if (state?['activeCount'] == count) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Native guest job count did not reach the expected state.');
}
