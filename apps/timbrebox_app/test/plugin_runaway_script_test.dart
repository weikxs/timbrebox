import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

/// A plugin runs on the UI isolate (flutter_js evaluates synchronously), so a
/// script that never yields would freeze the whole app. The engine's time
/// limit ends it instead.
void main() {
  // The plugin sandbox reads its scripts from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a script that never yields is stopped, not left to freeze the app',
    () async {
      final runtime = PluginRuntime();
      addTearDown(runtime.dispose);
      await runtime.load(_spinPlugin);

      final watch = Stopwatch()..start();
      await expectLater(
        runtime.call('search', const ['q', 1, 'music']),
        throwsA(isA<PluginRuntimeException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    },
  );

  // A new engine can take the memory of one closed before it.
  test('an engine started after another was closed is still limited', () async {
    final first = PluginRuntime();
    await first.load(_spinPlugin);
    first.dispose();
    final second = PluginRuntime();
    addTearDown(second.dispose);
    await second.load(_spinPlugin);

    final watch = Stopwatch()..start();
    await expectLater(
      second.call('search', const ['q', 1, 'music']),
      throwsA(isA<PluginRuntimeException>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  });
}

const _spinPlugin = '''
module.exports = {
  platform: 'Spin',
  search: async function () { while (true) {} },
};
''';
