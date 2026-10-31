part of 'app_controller.dart';

extension AppControllerPlaybackStatus on AppController {
  /// Local read-only counters/state, never native error text or media addresses.
  Map<String, Object?> get playbackDiagnostics {
    final engine = _playerEngine;
    final detail = engine is NetworkPlayerEngine
        ? engine.diagnostics
        : <String, Object?>{};
    final state = _player.value;
    final code = state.errorCode ?? detail['errorCode'];
    return {
      ...detail,
      'state': state.status.name,
      'hasError': state.status == PlaybackStatus.failed,
      if (code is String)
        'errorCode': RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(code)
            ? code
            : 'playback_failed',
    };
  }
}
