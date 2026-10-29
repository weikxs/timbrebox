import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_catalog_source.dart';
import 'package:timbrebox_app/app/plugins/plugin_manifest.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

/// Radio, plugin and short-video tracks resolve from state their source
/// keeps in memory after a search. Saved in favorites, a playlist or the
/// session, they must still play after a restart.
void main() {
  StreamRequest request(MediaRef ref) => StreamRequest(
    ref: ref,
    quality: 'high',
    cancellation: CancellationToken(),
  );

  test('a saved track keeps its hint; older saved tracks still load', () {
    const track = CatalogTrack(
      id: 'x',
      title: 'Song',
      artist: 'Artist',
      sourceId: 'plugin_p',
      sourceName: 'P',
      duration: Duration.zero,
      quality: 'high',
      resolveHint: {'songmid': '42'},
    );

    final restored = CatalogTrack.fromJson(
      jsonDecode(jsonEncode(track.toJson())) as Map<String, Object?>,
    );
    final legacy = CatalogTrack.fromJson(const {
      'id': 'x',
      'sourceId': 'plugin_p',
      'title': 'Song',
    });

    expect(restored.resolveHint, {'songmid': '42'});
    expect(legacy.resolveHint, isNull);
  });

  test('a radio station resolves by its id after a restart', () async {
    final requested = <String>[];
    final source = RadioBrowserCatalogSource(
      readJson: (uri, _) async {
        requested.add(uri.path);
        return jsonEncode([
          {
            'stationuuid': 'uuid-1',
            'name': 'Jazz FM',
            'url_resolved': 'https://radio.example/jazz',
          },
        ]);
      },
    );

    final stream = await source.resolve(
      request(const MediaRef(sourceId: 'radio_browser', itemId: 'uuid-1')),
    );

    expect(stream.uri.toString(), 'https://radio.example/jazz');
    expect(requested, ['/json/stations/byuuid/uuid-1']);
  });

  test('a plugin track resolves from its hint after a restart', () async {
    Future<PluginCatalogSource> plugin() async {
      final runtime = PluginRuntime();
      await runtime.load(r'''
module.exports = {
  platform: 'P',
  search: async function () {
    return { isEnd: true, data: [{
      id: 'x', title: 'Song', songmid: '42',
      url: 'https://cdn.example/old.mp3', token: 'secret',
      album: { name: 'A', cover: 'https://img.example/a.jpg' },
    }] };
  },
  getMediaSource: async function (item) {
    return { url: 'https://93.184.216.34/' + item.songmid + '.mp3' };
  },
};
''');
      return PluginCatalogSource(
        manifest: const PluginManifest(
          id: 'plugin_p',
          platform: 'P',
          version: '1',
        ),
        runtime: runtime,
        policy: const EgressPolicy(),
      );
    }

    final before = await plugin();
    addTearDown(before.dispose);
    final page = await before.search(
      SearchRequest(query: 'q', cancellation: CancellationToken()),
    );
    final saved = before.toCatalogTrack(page.items.single);
    final hint = saved.resolveHint!;
    expect(jsonEncode(hint), isNot(contains('https://')));
    expect(jsonEncode(hint), isNot(contains('secret')));

    final after = await plugin(); // A restart: nothing searched yet.
    addTearDown(after.dispose);
    after.rememberHint(saved.id, hint);
    final stream = await after.resolve(request(saved.ref));

    expect(stream.uri.host, '127.0.0.1'); // Relayed through the proxy.
  });

  test('play hands a saved track\'s hint back to its source', () async {
    final catalog = _HintCatalog();
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: catalog,
    );
    addTearDown(controller.dispose);
    const track = CatalogTrack(
      id: 'x',
      title: 'Song',
      artist: 'Artist',
      sourceId: 'audius',
      sourceName: 'Audius',
      duration: Duration.zero,
      quality: 'high',
      resolveHint: {'songmid': '42'},
    );

    await controller.play(track);

    expect(catalog.remembered, ['tb://audius/x']);
  });

  test('search again looks the failed track up by title and artist', () async {
    final catalog = _HintCatalog();
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: catalog,
    );
    addTearDown(controller.dispose);
    await controller.play(_track);

    await controller.searchAgainForCurrent();

    expect(catalog.queries, ['Song Artist']);
    expect(controller.query, 'Song Artist');
  });
}

const _track = CatalogTrack(
  id: 'x',
  title: 'Song',
  artist: 'Artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: Duration.zero,
  quality: 'high',
);

final class _HintCatalog implements MusicCatalog, ResolveHintCatalog {
  final remembered = <String>[];
  final queries = <String>[];

  @override
  void rememberResolveHint(CatalogTrack track) {
    if (track.resolveHint != null) remembered.add('${track.ref}');
  }

  @override
  Iterable<SourceDescriptor> get sources => [
    SourceDescriptor(
      id: 'audius',
      name: 'Audius',
      capabilities: const [SourceCapability.search],
    ),
  ];

  @override
  bool isEnabled(String sourceId) => true;

  @override
  void setEnabled(String sourceId, bool enabled) {}

  @override
  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  }) async {
    queries.add(query);
    return const [];
  }
}
