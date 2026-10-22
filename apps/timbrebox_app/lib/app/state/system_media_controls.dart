import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import 'mpris_media_controls.dart';
import 'smtc_media_controls.dart';

/// A transport command delivered by the OS media session — including from
/// Bluetooth headset AVRCP buttons, which the OS routes to whichever app owns
/// the session. We never talk Bluetooth directly.
enum MediaCommand { play, pause, next, previous, stop }

/// Now-playing metadata pushed to the OS media session.
class NowPlayingInfo {
  const NowPlayingInfo({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.artUri,
    this.duration,
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final Uri? artUri;
  final Duration? duration;
}

/// Bridges TimbreBox to the OS system media session: pushes metadata + state
/// out, and surfaces transport commands (media keys, lockscreen, Bluetooth
/// headset buttons) back in. media_kit stays the only thing that plays audio;
/// this layer never touches playback itself.
abstract interface class SystemMediaControls {
  Future<void> init();
  Future<void> setNowPlaying(NowPlayingInfo info);
  Future<void> setPlaybackState({
    required bool playing,
    required Duration position,
    Duration? duration,
  });
  Stream<MediaCommand> get commands;
  Stream<Duration> get seeks;
  Future<void> dispose();
}

/// Picks the right backend for the current platform. audio_service covers the
/// Apple platforms (MPNowPlayingInfoCenter + MPRemoteCommandCenter) and Android
/// (MediaSession); Windows uses SMTC and Linux uses MPRIS. Any other target
/// falls back to a no-op.
SystemMediaControls createSystemMediaControls() {
  if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
    return AudioServiceMediaControls();
  }
  if (Platform.isWindows) return SmtcMediaControls();
  if (Platform.isLinux) return MprisMediaControls();
  return const NoopMediaControls();
}

class NoopMediaControls implements SystemMediaControls {
  const NoopMediaControls();

  @override
  Future<void> init() async {}
  @override
  Future<void> setNowPlaying(NowPlayingInfo info) async {}
  @override
  Future<void> setPlaybackState({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) async {}
  @override
  Stream<MediaCommand> get commands => const Stream.empty();
  @override
  Stream<Duration> get seeks => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

/// audio_service-backed controls, in "bridge only" mode: the handler's
/// transport overrides emit commands instead of playing anything.
class AudioServiceMediaControls implements SystemMediaControls {
  _TimbreAudioHandler? _handler;

  @override
  Future<void> init() async {
    _handler = await AudioService.init(
      builder: () => _TimbreAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.timbrebox.audio',
        androidNotificationChannelName: 'TimbreBox 播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  @override
  Future<void> setNowPlaying(NowPlayingInfo info) async {
    _handler?.mediaItem.add(
      MediaItem(
        id: info.id,
        title: info.title,
        artist: info.artist,
        album: info.album,
        artUri: info.artUri,
        duration: info.duration,
      ),
    );
  }

  @override
  Future<void> setPlaybackState({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) async {
    _handler?.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
      ),
    );
  }

  @override
  Stream<MediaCommand> get commands =>
      _handler?.commands.stream ?? const Stream.empty();

  @override
  Stream<Duration> get seeks =>
      _handler?.seeks.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await _handler?.commands.close();
    await _handler?.seeks.close();
  }
}

class _TimbreAudioHandler extends BaseAudioHandler {
  final commands = StreamController<MediaCommand>.broadcast();
  final seeks = StreamController<Duration>.broadcast();

  @override
  Future<void> play() async => commands.add(MediaCommand.play);
  @override
  Future<void> pause() async => commands.add(MediaCommand.pause);
  @override
  Future<void> skipToNext() async => commands.add(MediaCommand.next);
  @override
  Future<void> skipToPrevious() async => commands.add(MediaCommand.previous);
  @override
  Future<void> stop() async => commands.add(MediaCommand.stop);
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
}
