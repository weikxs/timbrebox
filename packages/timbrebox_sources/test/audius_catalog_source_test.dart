import 'package:test/test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  test('standard catalog registers only the open directory sources', () {
    final catalog = BuiltInMusicCatalog.standard();

    expect(catalog.sources.map((source) => source.id), [
      'audius',
      'internet_archive',
      'radio_browser',
    ]);
    expect(
      catalog.sources.where(
        (source) => source.supports(SourceCapability.search),
      ),
      hasLength(3),
    );
  });

  group('a track saved from a source that is no longer built in', () {
    tearDown(() => SourceStrings.english = false);

    for (final id in ['youtube', 'bilibili', 'douyin', 'tiktok']) {
      test('$id explains that a plugin can add it back', () {
        SourceStrings.english = true;
        final resolver = BuiltInMusicCatalog.standard().streamResolver;

        expect(
          () => resolver.resolve(
            StreamRequest(
              ref: MediaRef(sourceId: id, itemId: 'demo-item'),
              quality: 'standard',
              cancellation: CancellationToken(),
            ),
          ),
          throwsA(
            isA<SourceException>()
                .having((e) => e.retryable, 'retryable', isFalse)
                .having((e) => e.code, 'code', 'source_retired')
                .having((e) => e.message, 'message', contains('plugin')),
          ),
        );
      });
    }

    test('an unknown source still reports that it is not registered', () {
      final resolver = BuiltInMusicCatalog.standard().streamResolver;

      expect(
        () => resolver.resolve(
          StreamRequest(
            ref: MediaRef(sourceId: 'demo_source', itemId: 'demo-item'),
            quality: 'standard',
            cancellation: CancellationToken(),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('maps public Audius search data to a safe playback candidate', () async {
    final source = AudiusCatalogSource(
      readJson: (_, _) async => '''
        {"data":[
          {"id":"vZJJz","title":"Public track","duration":190,
           "is_streamable":true,"user":{"name":"An artist"}},
          {"id":"private","title":"Private track","is_streamable":false}
        ]}
      ''',
    );

    final page = await source.search(
      SearchRequest(query: 'public', cancellation: CancellationToken()),
    );
    final track = source.toCatalogTrack(page.items.single);

    expect(track.title, 'Public track');
    expect(track.artist, 'An artist');
    expect(track.duration, const Duration(seconds: 190));
    expect(track.sourceId, 'audius');
    final resolved = await source.resolve(
      StreamRequest(
        ref: track.ref,
        quality: track.quality,
        cancellation: CancellationToken(),
      ),
    );
    expect(resolved.uri.path, '/v1/tracks/vZJJz/stream');
    expect(resolved.uri.queryParameters['app_name'], 'TimbreBox');
  });

  test(
    'maps only secure public radio streams to playback candidates',
    () async {
      final source = RadioBrowserCatalogSource(
        readJson: (_, _) async => '''
        [{"stationuuid":"station-1","name":"Night Radio",
          "countrycode":"DE","url_resolved":"https://radio.example/live"},
         {"stationuuid":"station-2","name":"Unsafe Radio",
          "url_resolved":"ftp://radio.example/live"}]
      ''',
      );

      final page = await source.search(
        SearchRequest(query: 'night', cancellation: CancellationToken()),
      );
      final station = source.toCatalogTrack(page.items.single);

      expect(station.title, 'Night Radio');
      expect(station.artist, 'Internet radio · DE');
      expect(station.quality, '直播电台');
      final resolved = await source.resolve(
        StreamRequest(
          ref: station.ref,
          quality: station.quality,
          cancellation: CancellationToken(),
        ),
      );
      expect(resolved.uri.toString(), 'https://radio.example/live');
    },
  );

  test(
    'maps Internet Archive metadata to a deferred public audio stream',
    () async {
      final source = InternetArchiveCatalogSource(
        readJson: (uri, _) async {
          if (uri.path == '/advancedsearch.php') {
            return '''
            {"response":{"docs":[
              {"identifier":"open-set","title":"Open Set",
               "creator":["A. Artist"],"mediatype":"audio"}
            ]}}
          ''';
          }
          return '''
          {"files":[
            {"name":"cover.jpg","format":"JPEG"},
            {"name":"open-set.mp3","format":"VBR MP3","private":"0"}
          ]}
        ''';
        },
      );

      final page = await source.search(
        SearchRequest(query: 'open set', cancellation: CancellationToken()),
      );
      final track = source.toCatalogTrack(page.items.single);
      expect(track.sourceId, 'internet_archive');
      expect(track.artist, 'A. Artist');

      final resolved = await source.resolve(
        StreamRequest(
          ref: track.ref,
          quality: track.quality,
          cancellation: CancellationToken(),
        ),
      );
      expect(
        resolved.uri.toString(),
        'https://archive.org/download/open-set/open-set.mp3',
      );
    },
  );

  test('rejects Internet Archive entries without public audio files', () async {
    final source = InternetArchiveCatalogSource(
      readJson: (_, _) async =>
          '{"files":[{"name":"private.mp3","format":"VBR MP3","private":"true"},{"name":"cover.jpg","format":"JPEG"}]}',
    );
    expect(
      () => source.prepareItem('no-audio', CancellationToken()),
      throwsA(
        isA<SourceException>().having(
          (error) => error.code,
          'code',
          'audio_file_unavailable',
        ),
      ),
    );
  });

  test(
    'resolves an Internet Archive file name with spaces to a playable URL',
    () async {
      final source = InternetArchiveCatalogSource(
        readJson: (_, _) async =>
            '{"files":[{"name":"01 - Clair de lune (Suite bergamasque).flac","format":"Flac"}]}',
      );

      final resolved = await source.resolve(
        StreamRequest(
          ref: const MediaRef(
            sourceId: 'internet_archive',
            itemId: 'piano-set',
          ),
          quality: 'public',
          cancellation: CancellationToken(),
        ),
      );

      expect(
        resolved.uri.toString(),
        'https://archive.org/download/piano-set/'
        '01%20-%20Clair%20de%20lune%20(Suite%20bergamasque).flac',
      );
    },
  );
}
