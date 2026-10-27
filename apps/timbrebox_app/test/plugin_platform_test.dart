import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/design/app_strings.dart';
import 'package:timbrebox_app/app/plugins/plugin_platform.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/widgets/settings_plugins_section.dart';

import 'support/test_player_engine.dart';

/// Mobile builds must never download or run plugin code.
void main() {
  test('plugins run on desktop only', () {
    expect(pluginsAllowedOn('android'), isFalse);
    expect(pluginsAllowedOn('ios'), isFalse);
    expect(pluginsAllowedOn('macos'), isTrue);
    expect(pluginsAllowedOn('windows'), isTrue);
    expect(pluginsAllowedOn('linux'), isTrue);
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
