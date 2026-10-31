import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timbrebox_app/app/plugins/media_extractor_process.dart';

/// Separates tool startup/initialization from remote platform availability.
/// Opt in with the same explicit path and checksum used by the host bridge.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const path = String.fromEnvironment('TIMBREBOX_YTDLP_PATH');
  const bundle = String.fromEnvironment('TIMBREBOX_MEDIA_BUNDLE_SHA256');
  test(
    'the pinned desktop tool initializes in the real application sandbox',
    () async {
      final runner = PinnedMediaExtractionRunner();
      addTearDown(runner.dispose);
      try {
        final version = await runner.run([
          '--ignore-config',
          '--no-plugin-dirs',
          '--no-cache-dir',
          '--no-js-runtimes',
          '--no-remote-components',
          '--version',
        ]);
        expect(
          RegExp(
            r'^\d{4}\.\d{2}\.\d{2}(?:[\w.\-]*)?$',
          ).hasMatch(version.trim()),
          true,
        );
      } on MediaExtractionException catch (error) {
        fail(
          'Pinned tool initialization failed (${error.code}); no platform request was made.',
        );
      }
    },
    skip: path.isEmpty && bundle.isEmpty,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
