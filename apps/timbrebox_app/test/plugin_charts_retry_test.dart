import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/plugin_manifest.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

/// A plugin whose charts fail once used to leave the hot library without
/// them, with nothing to try again.
void main() {
  test('failed plugin charts are named and can be loaded again', () async {
    final root = await Directory.systemTemp.createTemp('charts');
    addTearDown(() => root.delete(recursive: true));
    final dir = await Directory('${root.path}/plugin_p').create();
    await File('${dir.path}/plugin.js').writeAsString(r'''
var calls = 0;
module.exports = {
  platform: 'P',
  search: async function () { return { isEnd: true, data: [] }; },
  getTopLists: async function () {
    calls++;
    if (calls === 1) throw new Error('backend down');
    return [{ title: 'Charts', data: [{ id: 'c1', title: 'Top 100' }] }];
  },
};
''');
    await File('${dir.path}/manifest.json').writeAsString(
      jsonEncode(
        const PluginManifest(
          id: 'plugin_p',
          platform: 'P',
          version: '1',
          functions: ['search', 'getTopLists'],
        ).toJson(),
      ),
    );
    final controller = AppController(
      engine: TestPlayerEngine(),
      pluginRepository: PluginRepository(pluginsDirectory: () async => root),
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await controller.loadPluginTopLists();
    expect(controller.pluginTopLists, isEmpty);
    expect(controller.pluginTopListFailures, ['P']);

    await controller.retryPluginTopLists();
    expect(controller.pluginTopLists.single.title, 'Top 100');
    expect(controller.pluginTopListFailures, isEmpty);
  });
}
