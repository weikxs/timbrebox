part of 'app_controller.dart';

/// Preference setters: each applies the change and saves the settings.
extension AppControllerSettings on AppController {
  void setSettingsSection(SettingsSection value) {
    _settingsSection = value;
    _notify();
  }

  void setLanguage(String value) {
    _language = value;
    AppStrings.lang = AppStrings.fromName(value);
    _persistSettings();
    _notify();
  }

  void setAutoPlay(bool value) {
    _autoPlay = value;
    _persistSettings();
    if (!value) {
      _savedQueueKey = null; // The next save writes the whole session again.
      unawaited(_sessionStore?.clear());
    }
    _notify();
  }

  /// Without a GPU, turning "reduce" off keeps the effects on despite it.
  void setReducedEffects(bool value) {
    _reducedEffects = value;
    if (softwareRendering) _effectsWithoutGpu = !value;
    AppEffects.reduced = reducedEffects;
    _persistSettings();
    _notify();
  }

  void setReleaseAfterPause(bool value) {
    _releaseAfterPause = value;
    unawaited(_player.setReleaseAfterPause(value));
    _persistSettings();
    _notify();
  }

  void setDiagnosticLogging(bool value) {
    _diagnosticLogging = value;
    DiagnosticLog.enabled = value;
    _persistSettings();
    _notify();
  }

  void setVolume(double value) {
    _volume = value.clamp(0, 1);
    unawaited(_player.setVolume(_volume));
    _persistSettings();
    _notify();
  }

  double get playbackRate => _rate;

  void setPlaybackRate(double value) {
    _rate = value.clamp(0.25, 3.0);
    unawaited(_player.setRate(_rate));
    _persistSettings();
    _notify();
  }

  void setLoop(PlaybackLoop value) {
    _loop = value;
    _persistSettings();
    _notify();
  }

  /// Rebinds [action] to [binding]. If another action already holds that key
  /// combo, the two swap so every action stays bound and bindings stay unique.
  void setShortcut(PlayerAction action, ShortcutBinding binding) {
    final previous = _shortcuts[action];
    PlayerAction? conflict;
    _shortcuts.forEach((other, existing) {
      if (other != action && existing == binding) conflict = other;
    });
    if (conflict != null && previous != null) _shortcuts[conflict!] = previous;
    _shortcuts[action] = binding;
    _persistSettings();
    _notify();
  }

  /// Restores every shortcut to its factory default.
  void resetShortcuts() {
    _shortcuts
      ..clear()
      ..addAll(defaultShortcuts());
    _persistSettings();
    _notify();
  }
}
