import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/plugin_manifest.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('plugins'));
  tearDown(() => root.delete(recursive: true));

  PluginRepository repository() =>
      PluginRepository(pluginsDirectory: () async => root);

  Future<void> store(String id, {String? manifest, String? srcUrl}) async {
    final dir = await Directory('${root.path}/$id').create();
    await File(
      '${dir.path}/plugin.js',
    ).writeAsString('module.exports = {platform: "$id", search() {}};');
    await File('${dir.path}/manifest.json').writeAsString(
      manifest ??
          jsonEncode(
            PluginManifest(
              id: id,
              platform: id,
              version: '1',
              srcUrl: srcUrl,
              functions: const ['search'],
            ).toJson(),
          ),
    );
  }

  test('a damaged stored plugin is reported instead of vanishing', () async {
    await store('plugin_good');
    await store('plugin_bad', manifest: '{ not json');
    final plugins = repository();

    final sources = await plugins.loadInstalled();

    expect(sources.map((source) => source.manifest.id), ['plugin_good']);
    expect(plugins.skippedAtLoad, ['plugin_bad']);
    for (final source in sources) {
      source.dispose();
    }
  });

  test('the controller tells the user which plugins were skipped', () async {
    await store('plugin_bad', manifest: '{ not json');
    final controller = AppController(
      engine: TestPlayerEngine(),
      pluginRepository: repository(),
    );
    addTearDown(controller.dispose);

    await controller.pluginsRestored;

    expect(controller.skippedPlugins, ['plugin_bad']);
  });

  test('switching a plugin off rewrites its manifest in one piece', () async {
    await store('plugin_a');
    final plugins = repository();

    await plugins.setEnabled('plugin_a', false);

    final names = root
        .listSync(recursive: true)
        .map((entry) => entry.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toSet();
    expect(names, {'plugin_a', 'plugin.js', 'manifest.json'});
    final saved = PluginManifest.fromJson(
      jsonDecode(
            await File('${root.path}/plugin_a/manifest.json').readAsString(),
          )
          as Map<String, Object?>,
    );
    expect(saved.enabled, isFalse);
  });

  test('checking for updates reports the plugins that failed', () async {
    // The local machine is not a public host, so this update cannot fetch.
    await store('plugin_a', srcUrl: 'https://127.0.0.1:9/a.js');
    await store('plugin_b');
    final controller = AppController(
      engine: TestPlayerEngine(),
      pluginRepository: repository(),
    );
    addTearDown(controller.dispose);
    await controller.pluginsRestored;

    final report = await controller.updatePlugins();

    expect(report.updated, 0);
    expect(report.failed, ['plugin_a']);
  });
}
