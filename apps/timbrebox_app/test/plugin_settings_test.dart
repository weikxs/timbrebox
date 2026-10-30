import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/widgets/settings_plugins_section.dart';

import 'support/test_player_engine.dart';

/// A plugin that declares two settings and shows what it was given as the
/// title of its only search result.
const _script = '''
module.exports = {
  platform: 'Home Server',
  srcUrl: 'https://plugins.example/home.js',
  userVariables: [
    { key: 'server', name: 'Server address', hint: 'https://music.example' },
    { key: 'password', name: 'Password' },
    { key: 'bad key!', name: 'Dropped' },
    'not a variable',
  ],
  search: async function () {
    const values = env.getUserVariables();
    return { isEnd: true, data: [
      { id: '1', title: values.server || 'none', artist: Object.keys(values).join(',') },
    ] };
  },
};
''';

void main() {
  // Installing runs the plugin, and the sandbox reads its scripts from the
  // asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('plugins'));
  tearDown(() => root.delete(recursive: true));

  PluginRepository repository() =>
      PluginRepository(pluginsDirectory: () async => root);

  Future<String> firstTitle(dynamic source) async {
    final page = await source.search(
      SearchRequest(query: 'q', cancellation: CancellationToken()),
    );
    return (page as SearchPage).items.single.title;
  }

  test('installing records the settings a plugin declares', () async {
    final source = await repository().installSource(
      _script,
      Uri.parse('https://plugins.example/home.js'),
    );
    addTearDown(source.dispose);

    final variables = source.manifest.variables;
    expect(variables.map((variable) => variable.key), ['server', 'password']);
    expect(variables.first.name, 'Server address');
    expect(variables.first.hint, 'https://music.example');
    expect(variables.last.isSecret, isTrue);
  });

  test('saved settings are private to the user and kept to the declared '
      'ones', () async {
    final plugins = repository();
    final source = await plugins.installSource(
      _script,
      Uri.parse('https://plugins.example/home.js'),
    );
    addTearDown(source.dispose);

    await plugins.saveVariables(source.manifest, {
      'server': 'https://music.example',
      'other': 'not declared',
    });

    expect(await plugins.variables(source.manifest.id), {
      'server': 'https://music.example',
    });
    final file = File('${root.path}/${source.manifest.id}/variables.json');
    if (!Platform.isWindows) {
      expect(file.statSync().modeString(), 'rw-------');
    }
  });

  test('settings stay private across an update', () async {
    final plugins = PluginRepository(
      pluginsDirectory: () async => root,
      fetch: (_) async =>
          _script.replaceFirst("search:", "version: '2', search:"),
    );
    final source = await plugins.installSource(
      _script,
      Uri.parse('https://plugins.example/home.js'),
    );
    source.dispose();
    await plugins.saveVariables(source.manifest, {'password': 'demo'});

    (await plugins.update(source.manifest))!.dispose();

    expect(await plugins.variables(source.manifest.id), {'password': 'demo'});
    final file = File('${root.path}/${source.manifest.id}/variables.json');
    if (!Platform.isWindows) {
      expect(file.statSync().modeString(), 'rw-------');
    }
  });

  test('a plugin reads its settings, and a change reaches it', () async {
    final plugins = repository();
    final installed = await plugins.installSource(
      _script,
      Uri.parse('https://plugins.example/home.js'),
    );
    installed.dispose();
    final controller = AppController(
      engine: TestPlayerEngine(),
      pluginRepository: plugins,
    );
    addTearDown(controller.dispose);
    await controller.pluginsRestored;
    final id = installed.manifest.id;
    final source = controller.pluginSource(id)!;
    expect(await firstTitle(source), 'none');

    await controller.savePluginVariables(id, {
      'server': 'https://music.example',
    });

    expect(await controller.pluginVariables(id), {
      'server': 'https://music.example',
    });
    expect(
      await firstTitle(controller.pluginSource(id)!),
      'https://music.example',
    );
  });

  testWidgets('settings offer a form for a plugin that declares settings', (
    tester,
  ) async {
    final plugins = repository();
    late AppController controller;
    await tester.runAsync(() async {
      (await plugins.installSource(
        _script,
        Uri.parse('https://plugins.example/home.js'),
      )).dispose();
      controller = AppController(
        engine: TestPlayerEngine(),
        pluginRepository: plugins,
      );
      await controller.pluginsRestored;
    });
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PluginSettings(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('插件设置'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    final password = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Password'),
    );
    expect(password.obscureText, isTrue);
  });
}
