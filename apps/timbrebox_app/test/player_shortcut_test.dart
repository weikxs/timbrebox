import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/player_shortcut.dart';

void main() {
  test('defaults bind every action', () {
    final defaults = defaultShortcuts();
    for (final action in PlayerAction.values) {
      expect(defaults[action], isNotNull, reason: '$action must have a default');
    }
  });

  test('every default is a modifier combination', () {
    for (final entry in defaultShortcuts().entries) {
      final b = entry.value;
      expect(
        b.shift || b.control || b.alt || b.meta,
        isTrue,
        reason: '${entry.key} default must include a modifier',
      );
    }
  });

  test('a binding round-trips through JSON', () {
    final binding = ShortcutBinding(
      LogicalKeyboardKey.arrowRight.keyId,
      shift: true,
      meta: true,
    );
    expect(ShortcutBinding.fromJson(binding.toJson()), binding);
  });

  test('shortcutsFromJson keeps stored keys and fills gaps with defaults', () {
    final json = {
      'playPause': ShortcutBinding(LogicalKeyboardKey.enter.keyId).toJson(),
    };
    final map = shortcutsFromJson(json);
    expect(map[PlayerAction.playPause]!.keyId, LogicalKeyboardKey.enter.keyId);
    expect(
      map[PlayerAction.nextTrack],
      defaultShortcuts()[PlayerAction.nextTrack],
    );
  });

  test('label renders modifiers and the key symbol', () {
    final binding = ShortcutBinding(
      LogicalKeyboardKey.arrowRight.keyId,
      shift: true,
    );
    expect(binding.label, contains('⇧'));
    expect(binding.label, contains('→'));
  });
}
