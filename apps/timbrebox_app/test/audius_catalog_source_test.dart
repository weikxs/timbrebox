import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/data/music_catalog.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  test(
    'standard catalog registers the four video and three directory sources',
    () {
      final catalog = BuiltInMusicCatalog.standard();

      expect(catalog.sources.map((source) => source.id), [
        'youtube',
        'bilibili',
        'douyin',
        'tiktok',
        'audius',
        'internet_archive',
        'radio_browser',
      ]);
      expect(
        catalog.sources.where(
          (source) => source.supports(SourceCapability.search),
        ),
        hasLength(7),
      );
    },
  );

  test('v2 catalog keeps open directory sources out of v1 registration', () {
    final catalog = BuiltInMusicCatalog.v2();

    expect(catalog.sources.map((source) => source.id), [
      'audius',
      'internet_archive',
      'radio_browser',
    ]);
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
}
