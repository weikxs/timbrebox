import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/design/app_strings.dart';
import 'package:timbrebox_app/app/plugins/plugin_platform.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/widgets/settings_plugins_section.dart';

import 'support/test_player_engine.dart';

/// Plugins run on the five platforms TimbreBox ships for, each in its
/// sandboxed engine; anything else gets the settings' explanation.
void main() {
  test('plugins run on desktop and mobile', () {
    for (final os in ['android', 'ios', 'macos', 'windows', 'linux']) {
      expect(pluginsAllowedOn(os), isTrue, reason: os);
    }
  });

  test('a system TimbreBox does not ship for runs no plugins', () {
    expect(pluginsAllowedOn('fuchsia'), isFalse);
  });

  testWidgets('without plugin support the settings say why', (tester) async {
    final controller = AppController(engine: TestPlayerEngine());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PluginSettings(controller: controller)),
      ),
    );

    expect(find.text(AppStrings.t('plugin.unsupported')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await expectLater(
      controller.installPluginFromUrl('https://example.org/p.js'),
      throwsA(anything),
    );
  });
}
