import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_http.dart';
import 'package:timbrebox_app/app/plugins/plugin_platform.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';
import 'package:timbrebox_app/app/plugins/script_time_limit.dart';

/// The plugin sandbox on a real device or simulator: the engine this
/// platform uses (QuickJS on Android, JavaScriptCore on iOS) loads a plugin,
/// serves its HTTP through the host, and stops a script that never yields.
///
/// Run it on a device or simulator with
/// `flutter test integration_test/plugin_sandbox_test.dart -d DEVICE_ID`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"title":"Demo Song 1"}')
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  PluginRuntime newRuntime() {
    final runtime = PluginRuntime(
      http: PluginHttpClient(
        policy: EgressPolicy(
          lookup: (_) async => [InternetAddress.loopbackIPv4],
          isPublicAddress: (_) => true,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  test('plugins are allowed on this platform', () {
    expect(pluginsAllowedHere, isTrue);
  });

  test('a plugin loads, sees this platform and fetches through the host', () async {
    final runtime = newRuntime();
    await runtime.load('''
module.exports = {
  platform: 'Device check',
  search: async function () {
    const res = await axios.get('http://public.test:${server.port}/s');
    const url = new URL('https://a.example/p?q=1');
    return {
      isEnd: true,
      data: [{ id: '1', title: res.data.title, artist: env.os + ' ' + url.searchParams.get('q') }],
    };
  },
};
''');

    final result = await runtime.call('search', const ['demo', 1, 'music']);

    final item = ((result! as Map)['data'] as List).single as Map;
    expect(item['title'], 'Demo Song 1');
    expect(item['artist'], '${Platform.operatingSystem} 1');
  });

  test('a script that never yields is stopped within the time limit', () async {
    final runtime = newRuntime();
    await runtime.load('''
module.exports = {
  platform: 'Runaway',
  search: async function () { return { isEnd: true, data: [] }; },
  spin: async function () { while (true) {} },
};
''');

    final watch = Stopwatch()..start();
    await expectLater(
      runtime.call('spin', const []),
      throwsA(isA<PluginRuntimeException>()),
    );
    expect(watch.elapsed, lessThan(pluginScriptTimeLimit * 3));
  });
}
