import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/model/player_shortcut.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/widgets/player_hotkeys.dart';

import 'support/test_player_engine.dart';

void main() {
  // The platform primary accelerator the default combos are built on.
  final primary = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;

  AppController makeController() => AppController(
    engine: TestPlayerEngine(),
    catalog: BuiltInMusicCatalog.standard(),
  );

  Future<void> pumpHotkeys(
    WidgetTester tester,
    AppController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerHotkeys(
          controller: controller,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump(); // let the autofocus settle so key events are delivered
  }

  Future<void> pressCombo(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(primary);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(primary);
  }

  testWidgets('primary+ArrowUp / ArrowDown nudge the volume by 5%', (
    tester,
  ) async {
    final controller = makeController();
    addTearDown(controller.dispose);
    controller.setVolume(0.5);
    await pumpHotkeys(tester, controller);

    await pressCombo(tester, LogicalKeyboardKey.arrowUp);
    expect(controller.volume, closeTo(0.55, 1e-9));

    await pressCombo(tester, LogicalKeyboardKey.arrowDown);
    await pressCombo(tester, LogicalKeyboardKey.arrowDown);
    expect(controller.volume, closeTo(0.45, 1e-9));
  });

  testWidgets('a bare arrow (no modifier) does not change the volume', (
    tester,
  ) async {
    final controller = makeController();
    addTearDown(controller.dispose);
    controller.setVolume(0.5);
    await pumpHotkeys(tester, controller);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(controller.volume, 0.5);
  });

  testWidgets('rebinding volume-up moves it to the new combo', (tester) async {
    final controller = makeController();
    addTearDown(controller.dispose);
    controller.setVolume(0.5);
    controller.setShortcut(
      PlayerAction.volumeUp,
      ShortcutBinding(LogicalKeyboardKey.keyK.keyId, control: true),
    );
    await pumpHotkeys(tester, controller);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(controller.volume, closeTo(0.55, 1e-9));

    // The former default combo no longer changes the volume.
    await pressCombo(tester, LogicalKeyboardKey.arrowUp);
    expect(controller.volume, closeTo(0.55, 1e-9));
  });
}
