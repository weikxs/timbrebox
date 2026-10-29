import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_http.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

/// A plugin that fetches [url] as text and keeps the body for the test.
String _fetcher(String url) =>
    '''
module.exports = {
  platform: 'P',
  search() {},
  fetch: async function () {
    const res = await axios.get('$url', { responseType: 'text' });
    module.exports.body = res.data;
  },
};
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String body;

  // The test binding stubs HttpClient; these tests talk to a loopback server.
  final stubbed = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = stubbed);

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..headers.contentType = ContentType.text
        ..write(body)
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  Future<String?> fetchThroughPlugin() async {
    final runtime = PluginRuntime(
      http: PluginHttpClient(
        policy: EgressPolicy(
          lookup: (_) async => [InternetAddress.loopbackIPv4],
          isPublicAddress: (_) => true,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    await runtime.load(_fetcher('http://public.test:${server.port}/'));
    await runtime.call('fetch', const []);
    return runtime.meta('body');
  }

  test('a response body reaches the plugin unchanged', () async {
    body =
        'quote " backslash \\ newline \n tab \t '
        'separators \u2028 \u2029 '
        r"code '); globalThis.x = 1; (' ${x} </script> "
        'unicode 夜窗 🎵';

    expect(await fetchThroughPlugin(), body);
  });

  test('a large response body crosses the bridge', () async {
    body = List.filled(1 << 18, r'"\x{}').join(); // 1.3 MB, mostly escapes
    final watch = Stopwatch()..start();
    final received = await fetchThroughPlugin();
    watch.stop();
    // ignore: avoid_print
    print('1.3 MB escaped body to plugin: ${watch.elapsedMilliseconds} ms');
    expect(received, body);
  });
}
