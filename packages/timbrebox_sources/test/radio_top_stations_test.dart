import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';

const _stations = '''
[{"stationuuid":"station-1","name":"Taipei Radio","countrycode":"TW",
  "url_resolved":"https://radio.example/taipei"},
 {"stationuuid":"station-2","name":"Broken Radio","countrycode":"TW",
  "url_resolved":"ftp://radio.example/broken"}]
''';

void main() {
  test("lists a region's most voted working stations", () async {
    final asked = <Uri>[];
    final source = RadioBrowserCatalogSource(
      readJson: (uri, _) async {
        asked.add(uri);
        return _stations;
      },
    );

    final stations = await source.topStations(
      CancellationToken(),
      countryCode: 'TW',
    );

    expect(asked.single.path, '/json/stations/search');
    expect(asked.single.queryParameters, {
      'countrycode': 'TW',
      'hidebroken': 'true',
      'order': 'votes',
      'reverse': 'true',
      'limit': '30',
    });
    expect(stations.map((station) => station.title), ['Taipei Radio']);
    final track = source.toCatalogTrack(stations.single);
    final resolved = await source.resolve(
      StreamRequest(
        ref: track.ref,
        quality: track.quality,
        cancellation: CancellationToken(),
      ),
    );
    expect(resolved.uri.toString(), 'https://radio.example/taipei');
  });

  test('lists the most voted stations worldwide without a region', () async {
    final asked = <Uri>[];
    final source = RadioBrowserCatalogSource(
      readJson: (uri, _) async {
        asked.add(uri);
        return _stations;
      },
    );

    await source.topStations(CancellationToken());

    expect(asked.single.queryParameters.containsKey('countrycode'), isFalse);
  });

  test('the catalog serves top stations as tracks', () async {
    final catalog = BuiltInMusicCatalog([
      RadioBrowserCatalogSource(readJson: (_, _) async => _stations),
    ]);

    final tracks = await catalog.topStations(
      countryCode: 'TW',
      cancellation: CancellationToken(),
    );

    expect(tracks.single.title, 'Taipei Radio');
    expect(tracks.single.sourceId, 'radio_browser');
  });

  test('without the radio directory there are no top stations', () async {
    final catalog = BuiltInMusicCatalog(const []);

    final tracks = await catalog.topStations(cancellation: CancellationToken());

    expect(tracks, isEmpty);
  });
}
