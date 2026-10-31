import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_http.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final stubbed = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = stubbed);

  test(
    'cancel aborts stalled HTTP and prevents the obsolete continuation request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final started = Completer<void>();
      final paths = <String>[];
      server.listen((request) {
        paths.add(request.uri.path);
        if (request.uri.path == '/seed') {
          started.complete();
          return; // Deliberately stall until the client aborts its own socket.
        }
        request.response
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}')
          ..close();
      });
      final runtime = PluginRuntime(
        http: PluginHttpClient(
          policy: EgressPolicy(
            lookup: (_) async => [InternetAddress.loopbackIPv4],
            isPublicAddress: (_) => true,
          ),
        ),
      );
      addTearDown(runtime.dispose);
      await runtime.load('''
module.exports = {
  platform: 'HTTP cancellation check',
  search: async function() {
    try { await axios.get('http://public.test:${server.port}/seed'); }
    catch (e) { /* An old plugin might try to continue after a failed request. */ }
    await axios.get('http://public.test:${server.port}/obsolete');
    return null;
  },
  next: async function() {
    return (await axios.get('http://public.test:${server.port}/next')).data;
  },
};
''');
      final cancellation = CancellationToken();
      final old = runtime.call('search', const [], cancellation: cancellation);
      final rejected = expectLater(old, throwsA(isA<OperationCancelled>()));
      await started.future.timeout(const Duration(seconds: 2));
      cancellation.cancel();
      await rejected;
      final next = await runtime
          .call('next', const [])
          .timeout(const Duration(seconds: 2));
      expect(next, {'ok': true});
      expect(paths, ['/seed', '/next']);
    },
  );

  test('a cancelled queued HTTP call never starts a request', () async {
    final runtime = PluginRuntime();
    addTearDown(runtime.dispose);
    await runtime.load('''
module.exports = {
  platform: 'Queued HTTP cancellation',
  search: async function() { return axios.get('https://never-request.example/'); },
};
''');
    final cancellation = CancellationToken()..cancel();
    await expectLater(
      runtime.call('search', const [], cancellation: cancellation),
      throwsA(isA<OperationCancelled>()),
    );
  });
}
