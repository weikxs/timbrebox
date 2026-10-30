import 'dart:io';

import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';

const _searchBody = '''
{"result_count":3,"page_count":1,"page_size":20,"page":1,"results":[
  {"id":"track-1","title":"Piano Melody","creator":"An artist",
   "url":"https://cdn.example/piano.mp3","duration":190500,
   "license":"by","license_version":"4.0","mature":false},
  {"id":"track-2","title":"Night Song","creator":"Another artist",
   "url":"https://cdn.example/night.mp3","duration":61000,
   "license":"by-nc-sa","license_version":"3.0","mature":true},
  {"id":"track-3","title":"Old Recording","creator":"",
   "url":"http://cdn.example/old.mp3","duration":1000,
   "license":"pdm","license_version":"1.0","mature":false}
]}
''';

StreamRequest _streamOf(CatalogTrack track) => StreamRequest(
  ref: track.ref,
  quality: track.quality,
  cancellation: CancellationToken(),
);

void main() {
  tearDown(() => SourceStrings.english = false);

  test('searches music only, in pages the anonymous API allows', () async {
    final asked = <Uri>[];
    final source = OpenverseCatalogSource(
      readJson: (uri, _) async {
        asked.add(uri);
        return _searchBody;
      },
    );

    await source.search(
      SearchRequest(query: 'piano', cancellation: CancellationToken(), page: 2),
    );

    final uri = asked.single;
    expect(uri.host, 'api.openverse.org');
    expect(uri.path, '/v1/audio/');
    expect(uri.queryParameters, {
      'q': 'piano',
      'category': 'music',
      'mature': 'false',
      'page': '2',
      'page_size': '20',
    });
  });

  test('keeps safe tracks and labels them with their licence', () async {
    final source = OpenverseCatalogSource(
      readJson: (_, _) async => _searchBody,
    );

    final page = await source.search(
      SearchRequest(query: 'piano', cancellation: CancellationToken()),
    );
    final tracks = page.items.map(source.toCatalogTrack).toList();

    // A mature track and one served over plain HTTP are left out.
    expect(tracks, hasLength(1));
    final track = tracks.single;
    expect(track.title, 'Piano Melody');
    expect(track.artist, 'An artist');
    expect(track.duration, const Duration(milliseconds: 190500));
    expect(track.sourceId, 'openverse');
    expect(track.quality, 'CC BY 4.0');
    final resolved = await source.resolve(_streamOf(track));
    expect(resolved.uri.toString(), 'https://cdn.example/piano.mp3');
  });

  test('names public-domain and CC0 audio as such', () async {
    SourceStrings.english = true;
    final source = OpenverseCatalogSource(
      readJson: (_, _) async => '''
        {"results":[
          {"id":"a","title":"A","creator":"X","url":"https://c.example/a.mp3",
           "license":"pdm","license_version":"1.0"},
          {"id":"b","title":"B","creator":"","url":"https://c.example/b.mp3",
           "license":"cc0","license_version":"1.0"}
        ]}
      ''',
    );

    final page = await source.search(
      SearchRequest(query: 'x', cancellation: CancellationToken()),
    );
    final tracks = page.items.map(source.toCatalogTrack).toList();

    expect(tracks.map((track) => track.quality), ['Public domain', 'CC0 1.0']);
    expect(tracks.last.artist, 'Openverse');
  });

  test('looks a saved track up by its id after a restart', () async {
    final asked = <Uri>[];
    final source = OpenverseCatalogSource(
      readJson: (uri, _) async {
        asked.add(uri);
        return '{"id":"track-1","url":"https://cdn.example/piano.mp3"}';
      },
    );

    final resolved = await source.resolve(
      StreamRequest(
        ref: const MediaRef(sourceId: 'openverse', itemId: 'track-1'),
        quality: 'CC BY 4.0',
        cancellation: CancellationToken(),
      ),
    );

    expect(asked.single.path, '/v1/audio/track-1/');
    expect(resolved.uri.toString(), 'https://cdn.example/piano.mp3');
  });

  test('a saved track the directory no longer serves safely expires', () {
    final source = OpenverseCatalogSource(
      readJson: (_, _) async =>
          '{"id":"track-1","url":"http://cdn.example/piano.mp3"}',
    );

    expect(
      () => source.resolve(
        StreamRequest(
          ref: const MediaRef(sourceId: 'openverse', itemId: 'track-1'),
          quality: '',
          cancellation: CancellationToken(),
        ),
      ),
      throwsA(
        isA<SourceException>().having(
          (e) => e.code,
          'code',
          'media_reference_expired',
        ),
      ),
    );
  });

  test('stops before the depth anonymous requests may reach', () async {
    var requests = 0;
    final source = OpenverseCatalogSource(
      readJson: (_, _) async {
        requests++;
        return _searchBody;
      },
    );

    final page = await source.search(
      SearchRequest(
        query: 'piano',
        cancellation: CancellationToken(),
        page: 13,
      ),
    );

    expect(page.items, isEmpty);
    expect(requests, 0);
  });

  test('a directory that asks to slow down says so', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen(
      (request) => request.response
        ..statusCode = HttpStatus.tooManyRequests
        ..close(),
    );

    final read = JsonHttpClient().read(
      Uri.http('127.0.0.1:${server.port}', '/'),
      CancellationToken(),
    );

    await expectLater(
      read,
      throwsA(
        isA<SourceException>()
            .having((e) => e.code, 'code', 'rate_limited')
            .having((e) => e.retryable, 'retryable', isTrue),
      ),
    );
  });
}
