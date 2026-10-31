import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/media_extraction_error.dart';
import 'package:timbrebox_app/app/plugins/platform_media_backend.dart';
import 'package:timbrebox_app/app/plugins/youtube_keyword_search.dart';

void main() {
  Matcher code(String value) =>
      isA<MediaExtractionException>().having((e) => e.code, 'code', value);
  test(
    'original keyword client is lazy, receives the actual query/page and closes',
    () async {
      var created = 0;
      final client = _Client();
      final search = DartYouTubeKeywordSearch(
        createClient: () {
          created++;
          return client;
        },
      );
      addTearDown(search.dispose);
      expect(created, 0);
      final result = await search.search('  query fixture  ', 2);
      expect(client.requests, [
        ['query fixture', 2],
      ]);
      expect(result['isEnd'], false);
      expect(client.closed, greaterThan(0));
      expect(
        (result['entries'] as List).single,
        isNot(contains('availability')),
      );
    },
  );
  test('invalid requests never start dependency HTTP', () async {
    var created = 0;
    final search = DartYouTubeKeywordSearch(
      createClient: () {
        created++;
        return _Client();
      },
    );
    addTearDown(search.dispose);
    await expectLater(
      search.search('', 1),
      throwsA(code('invalid_media_request')),
    );
    await expectLater(
      search.search('query', 6),
      throwsA(code('invalid_media_request')),
    );
    expect(created, 0);
  });
  test('timeout closes the real session boundary', () async {
    final client = _Client(pending: Completer());
    final search = DartYouTubeKeywordSearch(
      createClient: () => client,
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(search.dispose);
    await expectLater(
      search.search('query', 1),
      throwsA(code('extractor_timeout')),
    );
    expect(client.closed, greaterThan(0));
    client.pending!.complete([]);
  });
  test(
    'cancellation completes promptly without accepting late metadata',
    () async {
      final client = _Client(pending: Completer());
      final search = DartYouTubeKeywordSearch(createClient: () => client);
      addTearDown(search.dispose);
      final task = search.search('query', 1);
      final rejected = expectLater(task, throwsA(code('extractor_cancelled')));
      search.cancel();
      await rejected;
      expect(client.closed, greaterThan(0));
      client.pending!.complete([]);
    },
  );
  test('dependency details never become raw public errors', () async {
    final search = DartYouTubeKeywordSearch(
      createClient: () => _Client(fail: true),
    );
    addTearDown(search.dispose);
    await expectLater(
      search.search('query', 1),
      throwsA(code('extractor_failed')),
    );
  });
  test(
    'plugin host uses original keyword results but cannot upgrade their rights',
    () async {
      final search = DartYouTubeKeywordSearch(createClient: _Client.new);
      final backend = DesktopPlatformMediaBackend(youtubeSearch: search);
      addTearDown(backend.dispose);
      final result = await backend.call({
        'platform': 'youtube',
        'operation': 'search',
        'query': 'real query fixture',
        'page': 1,
      });
      final item = (result['data'] as List).single as Map;
      expect(item['id'], 'abcdefghijk');
      expect(item['accessState'], 'unknown');
      expect(item.containsKey('url'), false);
      expect(item['contentKind'], 'video_audio');
      expect(result['isEnd'], false);
    },
  );
}

class _Client implements YouTubeKeywordClient {
  _Client({this.pending, this.fail = false});
  final Completer<List<Map<String, Object?>>>? pending;
  final bool fail;
  final requests = <List<Object>>[];
  int closed = 0;
  @override
  Future<List<Map<String, Object?>>> search(String query, int page) async {
    requests.add([query, page]);
    if (fail) throw StateError('Synthetic private transport detail');
    if (pending != null) return pending!.future;
    return [
      {
        'id': 'abcdefghijk',
        'webpage_url': 'https://www.youtube.com/watch?v=abcdefghijk',
        'title': 'Synthetic query fixture',
        'duration': 120,
      },
    ];
  }

  @override
  void close() {
    closed++;
  }
}
