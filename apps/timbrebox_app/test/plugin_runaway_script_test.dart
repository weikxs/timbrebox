import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

/// A plugin runs on the UI isolate (flutter_js evaluates synchronously), so a
/// script that never yields would freeze the whole app. The engine's time
/// limit ends it instead.
void main() {
  test(
    'a script that never yields is stopped, not left to freeze the app',
    () async {
      final runtime = PluginRuntime();
      addTearDown(runtime.dispose);
      await runtime.load('''
module.exports = {
  platform: 'Spin',
  search: async function () { while (true) {} },
};
''');

      final watch = Stopwatch()..start();
      await expectLater(
        runtime.call('search', const ['q', 1, 'music']),
        throwsA(isA<PluginRuntimeException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    },
  );
}
