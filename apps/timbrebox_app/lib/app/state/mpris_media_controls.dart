import 'dart:async';

import 'package:mpris_service/mpris_service.dart';

import 'system_media_controls.dart';

/// Linux MPRIS (D-Bus) backend.
///
/// Exposes an `org.mpris.MediaPlayer2` player so desktop environments, media
/// keys and Bluetooth headset AVRCP buttons can drive TimbreBox. media_kit
/// stays the only thing that plays audio; this layer only mirrors metadata and
/// playback state onto the bus and forwards transport method calls back in.
///
/// Everything is best-effort: if the session bus is unavailable or the name is
/// already taken, the backend degrades to a silent no-op instead of throwing.
class MprisMediaControls implements SystemMediaControls {
  static const String _busName = 'org.mpris.MediaPlayer2.timbrebox';
  static const String _identity = 'TimbreBox';
  static const String _desktopEntry = 'timbrebox';

  MPRIS? _mpris;
  bool _playing = false;
  Duration _position = Duration.zero;

  final StreamController<MediaCommand> _commands =
      StreamController<MediaCommand>.broadcast();
  final StreamController<Duration> _seeks =
      StreamController<Duration>.broadcast();

  @override
  Future<void> init() async {
    try {
      final mpris = await MPRIS.create(
        busName: _busName,
        identity: _identity,
        desktopEntry: _desktopEntry,
      );
      _mpris = mpris;

      mpris
        ..canPlay = true
        ..canPause = true
        ..canGoNext = true
        ..canGoPrevious = true
        ..canSeek = true
        ..canControl = true;

      mpris.setEventHandler(
        MPRISEventHandler(
          play: () async => _commands.add(MediaCommand.play),
          pause: () async => _commands.add(MediaCommand.pause),
          playPause: () async => _commands.add(
            _playing ? MediaCommand.pause : MediaCommand.play,
          ),
          next: () async => _commands.add(MediaCommand.next),
          previous: () async => _commands.add(MediaCommand.previous),
          stop: () async => _commands.add(MediaCommand.stop),
          seek: (offset) async {
            final target = _position + offset;
            _seeks.add(target < Duration.zero ? Duration.zero : target);
          },
          setPosition: (trackId, position) async {
            _seeks.add(Duration(microseconds: position));
          },
        ),
      );
    } catch (_) {
      // Best-effort: leave the backend inert if MPRIS is unavailable.
      _mpris = null;
    }
  }

  @override
  Future<void> setNowPlaying(NowPlayingInfo info) async {
    final mpris = _mpris;
    if (mpris == null) return;
    try {
      mpris.metadata = MPRISMetadata(
        Uri.tryParse(info.id) ?? Uri(scheme: 'timbrebox', path: info.id),
        length: info.duration,
        artUrl: info.artUri,
        album: info.album,
        albumArtist: [info.artist],
        artist: [info.artist],
        title: info.title,
      );
    } catch (_) {
      // Ignore transient bus failures.
    }
  }

  @override
  Future<void> setPlaybackState({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) async {
    _playing = playing;
    _position = position;
    final mpris = _mpris;
    if (mpris == null) return;
    try {
      mpris.playbackStatus =
          playing ? MPRISPlaybackStatus.playing : MPRISPlaybackStatus.paused;
      mpris.position = position;
    } catch (_) {
      // Ignore transient bus failures.
    }
  }

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Stream<Duration> get seeks => _seeks.stream;

  @override
  Future<void> dispose() async {
    final mpris = _mpris;
    _mpris = null;
    if (mpris != null) {
      try {
        await mpris.dispose();
      } catch (_) {
        // Ignore.
      }
    }
    await _commands.close();
    await _seeks.close();
  }
}
