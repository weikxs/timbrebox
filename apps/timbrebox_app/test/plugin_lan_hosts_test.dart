import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_catalog_source.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';

/// A plugin for a server on the user's home network. The search query
/// names the address to ask and the stream address to hand back, so each
/// test chooses which host the plugin tries to reach.
const _script = '''
module.exports = {
  platform: 'Home Server',
  srcUrl: 'https://plugins.example/home.js',
  userVariables: [
    { key: 'server', name: 'Server address' },
    { key: 'password', name: 'Password' },
  ],
  search: async function (query) {
    const parts = query.split(' ');
    const res = await axios.get(parts[0], { timeout: 5000 });
    return { isEnd: true, data: [
      { id: '1', title: res.data, artist: 'Demo Artist', stream: parts[1] },
    ] };
  },
  getMediaSource: async function (item) {
    return { url: item.stream };
  },
};
''';

void main() {
  // Installing runs the plugin, and the sandbox reads its scripts from the
  // asset bundle. The test talks to servers on this machine.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory root;
  late HttpServer entered;
  late HttpServer notEntered;

  Future<HttpServer> serve() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      (request) => request.response
        ..write(request.uri.path == '/ping' ? 'Demo Song 1' : 'audio')
        ..close(),
    );
    return server;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('plugins');
    entered = await serve();
    notEntered = await serve();
  });

  tearDown(() async {
    await entered.close(force: true);
    await notEntered.close(force: true);
    await root.delete(recursive: true);
  });

  String address(HttpServer server) => 'http://127.0.0.1:${server.port}';

  /// A plugin installed with [entered]'s address in its settings (unless
  /// [enter] is false). This machine stands in for the home network: none
  /// of its addresses is public, and its loopback address counts as LAN.
  Future<PluginCatalogSource> plugin({
    bool enter = true,
    String field = 'server',
  }) async {
    final plugins = PluginRepository(
      pluginsDirectory: () async => root,
      policy: EgressPolicy(
        isPublicAddress: (_) => false,
        isLanAddress: (address) => address.isLoopback,
      ),
    );
    final source = await plugins.installSource(
      _script,
      Uri.parse('https://plugins.example/home.js'),
    );
    addTearDown(source.dispose);
    addTearDown(plugins.dispose);
    if (enter) {
      await plugins.saveVariables(source.manifest, {field: address(entered)});
    }
    return source;
  }

  Future<String> search(PluginCatalogSource source, String query) async {
    final page = await source.search(
      SearchRequest(query: query, cancellation: CancellationToken()),
    );
    return page.items.single.title;
  }

  Future<Uri> resolve(PluginCatalogSource source) async =>
      (await source.resolve(
        StreamRequest(
          ref: MediaRef(sourceId: source.descriptor.id, itemId: '1'),
          quality: 'standard',
          cancellation: CancellationToken(),
        ),
      )).uri;

  test('a plugin reaches and plays from the server the user entered', () async {
    final source = await plugin();

    final title = await search(
      source,
      '${address(entered)}/ping ${address(entered)}/song.mp3',
    );
    final local = await resolve(source);

    expect(title, 'Demo Song 1');
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(local)).close();
    expect(response.statusCode, HttpStatus.ok);
  });

  test('a plugin cannot reach a server the user did not enter', () async {
    final source = await plugin();

    await expectLater(
      search(source, '${address(notEntered)}/ping'),
      throwsA(isA<SourceException>()),
    );
  });

  test('a plugin cannot hand back a stream from a server the user did not '
      'enter', () async {
    final source = await plugin();
    await search(
      source,
      '${address(entered)}/ping ${address(notEntered)}/song.mp3',
    );

    await expectLater(
      resolve(source),
      throwsA(
        isA<SourceException>().having(
          (e) => e.code,
          'code',
          'stream_url_blocked',
        ),
      ),
    );
  });

  test('without an entered address the home network stays closed', () async {
    final source = await plugin(enter: false);

    await expectLater(
      search(source, '${address(entered)}/ping'),
      throwsA(isA<SourceException>()),
    );
  });

  test('an address typed into a password field opens nothing', () async {
    final source = await plugin(field: 'password');

    await expectLater(
      search(source, '${address(entered)}/ping'),
      throwsA(isA<SourceException>()),
    );
  });
}
