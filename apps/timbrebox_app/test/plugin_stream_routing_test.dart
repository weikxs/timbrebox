import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_catalog_source.dart';
import 'package:timbrebox_app/app/plugins/plugin_manifest.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

/// Every plugin stream goes through the loopback proxy, so each redirect hop
/// is checked by the proxy's egress policy before libmpv ever sees it.
void main() {
  // The plugin sandbox reads its scripts from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding stubs HttpClient; these tests talk to loopback servers.
  final stubbed = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = stubbed);
  late HttpServer upstream;
  late List<String> upstreamPaths;

  setUp(() async {
    upstreamPaths = [];
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) {
      upstreamPaths.add(request.uri.path);
      request.response
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..write('audio-bytes')
        ..close();
    });
  });

  tearDown(() => upstream.close(force: true));

  final permissive = EgressPolicy(
    lookup: (_) async => [InternetAddress.loopbackIPv4],
    isPublicAddress: (_) => true,
  );

  Future<PluginCatalogSource> source(
    String streamUrl, {
    StreamHeaderProxy? proxy,
  }) async {
    final runtime = PluginRuntime();
    await runtime.load('''
module.exports = {
  platform: 'P',
  search: async function () {
    return { isEnd: true, data: [{ id: 'x', title: 'Song' }] };
  },
  getMediaSource: async function () { return { url: '$streamUrl' }; },
};
''');
    final plugin = PluginCatalogSource(
      manifest: const PluginManifest(
        id: 'plugin_p',
        platform: 'P',
        version: '1',
      ),
      runtime: runtime,
      proxy: proxy,
      policy: permissive,
    );
    await plugin.search(
      SearchRequest(query: 'q', cancellation: CancellationToken()),
    );
    return plugin;
  }

  Future<ResolvedStream> resolve(PluginCatalogSource plugin) => plugin.resolve(
    StreamRequest(
      ref: const MediaRef(sourceId: 'plugin_p', itemId: 'x'),
      quality: 'standard',
      cancellation: CancellationToken(),
    ),
  );

  test('a stream without headers is still played through the proxy', () async {
    final plugin = await source('https://93.184.216.34/a.mp3');
    addTearDown(plugin.dispose);

    final stream = await resolve(plugin);

    expect(stream.uri.host, '127.0.0.1');
    expect(stream.uri.path, startsWith('/s/'));
    expect(stream.mimeType, 'audio/mpeg');
  });

  test('updating a plugin keeps its playing stream alive', () async {
    final root = await Directory.systemTemp.createTemp('plugins');
    addTearDown(() => root.delete(recursive: true));
    final dir = await Directory('${root.path}/plugin_p').create();
    await File('${dir.path}/plugin.js').writeAsString('''
module.exports = {
  platform: 'P',
  search: async function () {
    return { isEnd: true, data: [{ id: 'x', title: 'Song' }] };
  },
  getMediaSource: async function () {
    return { url: 'http://cdn.test:${upstream.port}/track.mp3' };
  },
};
''');
    const manifest = PluginManifest(
      id: 'plugin_p',
      platform: 'P',
      version: '1',
      functions: ['search', 'getMediaSource'],
    );
    await File(
      '${dir.path}/manifest.json',
    ).writeAsString(jsonEncode(manifest.toJson()));
    final repository = PluginRepository(
      policy: permissive,
      pluginsDirectory: () async => root,
    );
    addTearDown(repository.dispose);
    final old = (await repository.loadInstalled()).single;
    await old.search(
      SearchRequest(query: 'q', cancellation: CancellationToken()),
    );
    final playing = await resolve(old);

    // An update disposes the old source while its track keeps playing.
    old.dispose();

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(playing.uri)).close();
    final body = await response
        .transform(const SystemEncoding().decoder)
        .join();
    expect(body, 'audio-bytes');
    expect(upstreamPaths, ['/track.mp3']);
  });
}
