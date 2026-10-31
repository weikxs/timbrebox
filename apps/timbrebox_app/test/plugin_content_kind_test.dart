import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/design/app_strings.dart';
import 'package:timbrebox_app/app/plugins/plugin_catalog_source.dart';
import 'package:timbrebox_app/app/plugins/plugin_manifest.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'video audio is visibly labelled rather than promised as a full song',
    () async {
      final runtime = PluginRuntime();
      addTearDown(runtime.dispose);
      await runtime.load('''
module.exports = {
  platform: 'Demo source',
  search: async function() { return { isEnd: true, data: [
    { id: 'video', title: 'Demo video', contentKind: 'video_audio' },
    { id: 'normal', title: 'Demo track' },
  ] }; },
};
''');
      final source = PluginCatalogSource(
        manifest: const PluginManifest(
          id: 'plugin_demo',
          platform: 'Demo source',
          version: '1',
        ),
        runtime: runtime,
      );
      addTearDown(source.dispose);
      final page = await source.search(
        SearchRequest(query: 'demo', cancellation: CancellationToken()),
      );
      expect(
        source.toCatalogTrack(page.items.first).quality,
        AppStrings.t(
          'plugin.src.videoAudioFmt',
        ).replaceFirst('{p}', 'Demo source'),
      );
      expect(
        source.toCatalogTrack(page.items.last).quality,
        AppStrings.t(
          'plugin.src.qualityFmt',
        ).replaceFirst('{p}', 'Demo source'),
      );
    },
  );
}
