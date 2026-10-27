import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../model/player_shortcut.dart';
import '../state/app_controller.dart';

/// Desktop in-app keyboard shortcuts for the player. Wraps the app shell so
/// hardware keyboard keys drive transport when nothing else consumes them — a
/// focused search box keeps its own typing, because Flutter only bubbles
/// unhandled key events up to these bindings.
///
/// These are distinct from hardware **media keys** (play/pause/next), which the
/// OS media session already delivers via `SystemMediaControls`; this layer adds
/// the ordinary keys a desktop listener expects (space, arrows).
///
/// Bindings are user-configurable (Settings → Shortcuts) and come from
/// [AppController.shortcutFor]. Defaults are modifier combinations on the
/// platform's primary accelerator (⌘ on macOS, Ctrl elsewhere) — e.g. ⌘P /
/// ⌘← / ⇧⌘→.
class PlayerHotkeys extends StatelessWidget {
  const PlayerHotkeys({
    required this.controller,
    required this.child,
    super.key,
  });

  final AppController controller;
  final Widget child;

  static const Duration _seekStep = Duration(seconds: 5);
  static const double _volumeStep = 0.05;

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    // Mobile relies on the on-screen controls and the OS media session; a
    // physical-keyboard binding only makes sense on desktop.
    if (!_isDesktop) return child;
    // Rebinds when the user edits a shortcut without rebuilding [child].
    return ListenableBuilder(
      listenable: controller,
      builder: (context, focused) => CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          for (final action in PlayerAction.values)
            controller.shortcutFor(action).activator: () => _run(action),
        },
        child: focused!,
      ),
      child: Focus(autofocus: true, child: child),
    );
  }

  void _run(PlayerAction action) {
    switch (action) {
      case PlayerAction.playPause:
        unawaited(controller.togglePlayback());
      case PlayerAction.seekForward:
        _seekBy(_seekStep);
      case PlayerAction.seekBackward:
        _seekBy(-_seekStep);
      case PlayerAction.volumeUp:
        _nudgeVolume(_volumeStep);
      case PlayerAction.volumeDown:
        _nudgeVolume(-_volumeStep);
      case PlayerAction.nextTrack:
        unawaited(controller.next());
      case PlayerAction.previousTrack:
        unawaited(controller.previous());
    }
  }

  void _seekBy(Duration delta) {
    final target = controller.position + delta;
    final max = controller.playbackDuration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (max > Duration.zero && target > max ? max : target);
    unawaited(controller.seek(clamped));
  }

  void _nudgeVolume(double delta) =>
      controller.setVolume((controller.volume + delta).clamp(0.0, 1.0));
}
