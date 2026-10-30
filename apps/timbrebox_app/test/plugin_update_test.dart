import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/plugin_manifest.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

const _srcUrl = 'https://plugins.example/demo.js';

void main() {
  // Installing runs the plugin once, and the sandbox reads its scripts from
  // the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String served;

  setUp(() async => root = await Directory.systemTemp.createTemp('plugins'));
  tearDown(() => root.delete(recursive: true));

  PluginRepository repository() => PluginRepository(
    pluginsDirectory: () async => root,
    fetch: (_) async => served,
  );

  String script(String platform, {String version = '1'}) =>
      'module.exports = {platform: "$platform", version: "$version", '
      'srcUrl: "$_srcUrl", search: async () => ({isEnd: true, data: []})};';

  Future<PluginManifest> install(PluginRepository plugins) async {
    final source = await plugins.installSource(
      script('Demo'),
      Uri.parse(_srcUrl),
    );
    source.dispose();
    return source.manifest;
  }

  List<String> entries() =>
      root
          .listSync()
          .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
          .toList()
        ..sort();

  String stored(String id, String file) =>
      File('${root.path}/$id/$file').readAsStringSync();

  test('an update that renames the plugin still replaces it', () async {
    final plugins = repository();
    final installed = await install(plugins);
    await plugins.setEnabled(installed.id, false);
    served = script('Demo Music', version: '2');

    final fresh = await plugins.update(
      PluginManifest.fromJson(
        jsonDecode(stored(installed.id, 'manifest.json'))
            as Map<String, Object?>,
      ),
    );
    fresh!.dispose();

    expect(entries(), [installed.id]);
    expect(fresh.manifest.id, installed.id);
    expect(fresh.manifest.platform, 'Demo Music');
    expect(fresh.manifest.version, '2');
    expect(fresh.manifest.enabled, isFalse);
    expect(stored(installed.id, 'plugin.js'), served);
  });

  test('a broken update leaves the installed version as it was', () async {
    final plugins = repository();
    final installed = await install(plugins);
    final script = stored(installed.id, 'plugin.js');
    final manifest = stored(installed.id, 'manifest.json');
    served = 'module.exports = {platform: "Demo", search: ';

    await expectLater(
      plugins.update(installed),
      throwsA(isA<PluginInstallException>()),
    );

    expect(entries(), [installed.id]);
    expect(stored(installed.id, 'plugin.js'), script);
    expect(stored(installed.id, 'manifest.json'), manifest);
  });

  test('an update keeps the files stored beside the plugin', () async {
    final plugins = repository();
    final installed = await install(plugins);
    File(
      '${root.path}/${installed.id}/variables.json',
    ).writeAsStringSync('{"server":"demo"}');
    served = script('Demo', version: '2');

    (await plugins.update(installed))!.dispose();

    expect(stored(installed.id, 'variables.json'), '{"server":"demo"}');
  });

  test('an update cut short is rolled back at the next launch', () async {
    final plugins = repository();
    final installed = await install(plugins);
    // The old version was moved aside, and the new one never moved in.
    Directory(
      '${root.path}/${installed.id}',
    ).renameSync('${root.path}/${installed.id}.previous');
    Directory('${root.path}/${installed.id}.staging').createSync();

    final sources = await plugins.loadInstalled();

    expect(sources.map((source) => source.manifest.id), [installed.id]);
    expect(plugins.skippedAtLoad, isEmpty);
    expect(entries(), [installed.id]);
    for (final source in sources) {
      source.dispose();
    }
  });

  test('a failed update says why', () async {
    final plugins = repository();
    await install(plugins);
    served = 'module.exports = {version: "2"};';
    final controller = AppController(
      engine: TestPlayerEngine(),
      pluginRepository: plugins,
    );
    addTearDown(controller.dispose);
    await controller.pluginsRestored;

    final report = await controller.updatePlugins();

    expect(report.updated, 0);
    final failure = report.failed.single;
    expect(failure.name, 'Demo');
    expect(failure.reason, isNotEmpty);
  });
}
