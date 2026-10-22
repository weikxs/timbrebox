import 'dart:async';

import 'package:smtc_windows/smtc_windows.dart';

import 'system_media_controls.dart';

/// Windows System Media Transport Controls (SMTC) backend.
///
/// Bridges TimbreBox to the Windows "now playing" applet so media keys and
/// Bluetooth headset AVRCP buttons reach the app. media_kit remains the only
/// thing that plays audio; this layer only pushes metadata/state out and
/// surfaces transport commands back in.
///
/// Everything is best-effort: if the platform channel or the native SMTC
/// instance cannot be created, the backend degrades to a silent no-op instead
/// of throwing.
class SmtcMediaControls implements SystemMediaControls {
  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _buttonSub;

  final StreamController<MediaCommand> _commands =
      StreamController<MediaCommand>.broadcast();
  final StreamController<Duration> _seeks =
      StreamController<Duration>.broadcast();

  @override
  Future<void> init() async {
    try {
      await SMTCWindows.initialize();
      final smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: true,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
      );
      _smtc = smtc;
      _buttonSub = smtc.buttonPressStream.listen(_onButtonPressed);
    } catch (_) {
      // Best-effort: leave the backend inert if SMTC is unavailable.
      _smtc = null;
    }
  }

  void _onButtonPressed(PressedButton button) {
    switch (button) {
      case PressedButton.play:
        _commands.add(MediaCommand.play);
      case PressedButton.pause:
        _commands.add(MediaCommand.pause);
      case PressedButton.next:
        _commands.add(MediaCommand.next);
      case PressedButton.previous:
        _commands.add(MediaCommand.previous);
      case PressedButton.stop:
        _commands.add(MediaCommand.stop);
      case PressedButton.fastForward:
      case PressedButton.rewind:
      case PressedButton.record:
      case PressedButton.channelUp:
      case PressedButton.channelDown:
        // Not surfaced by the TimbreBox transport contract.
        break;
    }
  }

  @override
  Future<void> setNowPlaying(NowPlayingInfo info) async {
    final smtc = _smtc;
    if (smtc == null) return;
    try {
      await smtc.updateMetadata(
        MusicMetadata(
          title: info.title,
          artist: info.artist,
          album: info.album,
          thumbnail: info.artUri?.toString(),
        ),
      );
    } catch (_) {
      // Ignore transient native failures.
    }
  }

  @override
  Future<void> setPlaybackState({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) async {
    final smtc = _smtc;
    if (smtc == null) return;
    try {
      await smtc.setPlaybackStatus(
        playing ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
      await smtc.updateTimeline(
        PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: (duration ?? Duration.zero).inMilliseconds,
          positionMs: position.inMilliseconds,
        ),
      );
    } catch (_) {
      // Ignore transient native failures.
    }
  }

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Stream<Duration> get seeks => _seeks.stream;

  @override
  Future<void> dispose() async {
    await _buttonSub?.cancel();
    _buttonSub = null;
    final smtc = _smtc;
    _smtc = null;
    if (smtc != null) {
      try {
        await smtc.disableSmtc();
      } catch (_) {
        // Ignore.
      }
      try {
        await smtc.dispose();
      } catch (_) {
        // Ignore.
      }
    }
    await _commands.close();
    await _seeks.close();
  }
}
