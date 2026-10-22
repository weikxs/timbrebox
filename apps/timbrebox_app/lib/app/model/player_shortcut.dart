import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A player action that can be bound to a desktop keyboard shortcut.
enum PlayerAction {
  playPause,
  seekForward,
  seekBackward,
  volumeUp,
  volumeDown,
  nextTrack,
  previousTrack,
}

/// An immutable keyboard binding: one logical key plus modifier flags.
///
/// Serializes by [LogicalKeyboardKey.keyId] so a binding survives restarts and
/// can be rebuilt into a [SingleActivator] for `CallbackShortcuts`.
class ShortcutBinding {
  const ShortcutBinding(
    this.keyId, {
    this.shift = false,
    this.control = false,
    this.alt = false,
    this.meta = false,
  });

  final int keyId;
  final bool shift;
  final bool control;
  final bool alt;
  final bool meta;

  LogicalKeyboardKey get key => LogicalKeyboardKey.findKeyByKeyId(keyId) ??
      LogicalKeyboardKey(keyId);

  SingleActivator get activator => SingleActivator(
    key,
    shift: shift,
    control: control,
    alt: alt,
    meta: meta,
  );

  /// A platform-standard label: Apple symbols in canonical order on macOS
  /// (`⇧⌘→`), spelled modifiers joined with `+` elsewhere (`Ctrl+Shift+→`).
  String get label {
    if (Platform.isMacOS) {
      final buffer = StringBuffer();
      if (control) buffer.write('⌃');
      if (alt) buffer.write('⌥');
      if (shift) buffer.write('⇧');
      if (meta) buffer.write('⌘');
      buffer.write(_keyLabel);
      return buffer.toString();
    }
    final parts = <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) Platform.isWindows ? 'Win' : 'Super',
      _keyLabel,
    ];
    return parts.join('+');
  }

  String get _keyLabel {
    final special = _specialLabels[keyId];
    if (special != null) return special;
    final printable = key.keyLabel;
    if (printable.trim().isNotEmpty) return printable.toUpperCase();
    return key.debugName ?? 'Key'; // e.g. function keys.
  }

  Map<String, Object?> toJson() => {
    'keyId': keyId,
    if (shift) 'shift': true,
    if (control) 'control': true,
    if (alt) 'alt': true,
    if (meta) 'meta': true,
  };

  static ShortcutBinding? fromJson(Object? json) {
    if (json is! Map) return null;
    final keyId = (json['keyId'] as num?)?.toInt();
    if (keyId == null) return null;
    return ShortcutBinding(
      keyId,
      shift: json['shift'] == true,
      control: json['control'] == true,
      alt: json['alt'] == true,
      meta: json['meta'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShortcutBinding &&
      other.keyId == keyId &&
      other.shift == shift &&
      other.control == control &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(keyId, shift, control, alt, meta);
}

/// Symbols for keys whose `keyLabel` is empty or unfriendly.
final Map<int, String> _specialLabels = {
  LogicalKeyboardKey.space.keyId: 'Space',
  LogicalKeyboardKey.arrowLeft.keyId: '←',
  LogicalKeyboardKey.arrowRight.keyId: '→',
  LogicalKeyboardKey.arrowUp.keyId: '↑',
  LogicalKeyboardKey.arrowDown.keyId: '↓',
  LogicalKeyboardKey.enter.keyId: 'Enter',
  LogicalKeyboardKey.escape.keyId: 'Esc',
  LogicalKeyboardKey.tab.keyId: 'Tab',
  LogicalKeyboardKey.backspace.keyId: 'Backspace',
  LogicalKeyboardKey.home.keyId: 'Home',
  LogicalKeyboardKey.end.keyId: 'End',
};

/// The factory-default bindings. Each is a modifier combination built on the
/// platform's primary accelerator — Command (⌘) on macOS, Control elsewhere —
/// so shortcuts never collide with plain typing or navigation.
Map<PlayerAction, ShortcutBinding> defaultShortcuts() {
  final bool primaryIsMeta = Platform.isMacOS;
  ShortcutBinding combo(LogicalKeyboardKey key, {bool shift = false}) =>
      ShortcutBinding(
        key.keyId,
        shift: shift,
        meta: primaryIsMeta,
        control: !primaryIsMeta,
      );
  return {
    PlayerAction.playPause: combo(LogicalKeyboardKey.keyP),
    PlayerAction.seekForward: combo(LogicalKeyboardKey.arrowRight),
    PlayerAction.seekBackward: combo(LogicalKeyboardKey.arrowLeft),
    PlayerAction.volumeUp: combo(LogicalKeyboardKey.arrowUp),
    PlayerAction.volumeDown: combo(LogicalKeyboardKey.arrowDown),
    PlayerAction.nextTrack: combo(LogicalKeyboardKey.arrowRight, shift: true),
    PlayerAction.previousTrack: combo(LogicalKeyboardKey.arrowLeft, shift: true),
  };
}

/// Serializes the whole binding map for [SettingsStore].
Map<String, Object?> shortcutsToJson(Map<PlayerAction, ShortcutBinding> map) => {
  for (final entry in map.entries) entry.key.name: entry.value.toJson(),
};

/// Rebuilds a binding map from stored JSON, filling any gap with the default.
Map<PlayerAction, ShortcutBinding> shortcutsFromJson(Object? json) {
  final result = defaultShortcuts();
  if (json is Map) {
    for (final action in PlayerAction.values) {
      final binding = ShortcutBinding.fromJson(json[action.name]);
      if (binding != null) result[action] = binding;
    }
  }
  return result;
}
