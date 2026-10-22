import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../model/player_shortcut.dart';
import '../state/app_controller.dart';
import 'glass_panel.dart';

/// Settings tab that lists every player keyboard shortcut and lets the user
/// rebind or reset it. Desktop only — mobile shows an explanatory note.
class ShortcutsSettings extends StatelessWidget {
  const ShortcutsSettings({required this.controller, super.key});

  final AppController controller;

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.t('settings.shortcuts'),
          style: TextStyle(
            color: TimbreColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isDesktop
              ? AppStrings.t('settings.shortcutsHint')
              : AppStrings.t('settings.shortcutDesktopOnly'),
          style: TextStyle(color: TimbreColors.muted, fontSize: 12),
        ),
        if (_isDesktop) ...[
          const SizedBox(height: 8),
          for (final action in PlayerAction.values)
            _ShortcutRow(controller: controller, action: action),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.resetShortcuts,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: Text(AppStrings.t('settings.shortcutReset')),
            ),
          ),
        ],
      ],
    ),
  );
}

class _ShortcutRow extends StatefulWidget {
  const _ShortcutRow({required this.controller, required this.action});

  final AppController controller;
  final PlayerAction action;

  @override
  State<_ShortcutRow> createState() => _ShortcutRowState();
}

class _ShortcutRowState extends State<_ShortcutRow> {
  bool _capturing = false;
  final FocusNode _focus = FocusNode();

  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _startCapture() {
    setState(() => _capturing = true);
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _capturing = false);
      return KeyEventResult.handled;
    }
    if (_modifiers.contains(key)) return KeyEventResult.handled; // await a real key
    final keyboard = HardwareKeyboard.instance;
    final hasModifier = keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
    // Combinations only: ignore a bare key and keep waiting for a modifier combo.
    if (!hasModifier) return KeyEventResult.handled;
    widget.controller.setShortcut(
      widget.action,
      ShortcutBinding(
        key.keyId,
        shift: keyboard.isShiftPressed,
        control: keyboard.isControlPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
      ),
    );
    setState(() => _capturing = false);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.controller.shortcutFor(widget.action);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(AppStrings.t('shortcut.${widget.action.name}')),
          ),
          if (_capturing)
            Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: _chip(
                AppStrings.t('settings.shortcutPress'),
                active: true,
                onTap: () => setState(() => _capturing = false),
              ),
            )
          else
            _chip(binding.label, active: false, onTap: _startCapture),
        ],
      ),
    );
  }

  Widget _chip(String text, {required bool active, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 68),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? TimbreColors.gold : TimbreColors.line,
            ),
            borderRadius: BorderRadius.circular(8),
            color: active ? TimbreColors.gold.withValues(alpha: .14) : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              color: active ? TimbreColors.gold : TimbreColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
