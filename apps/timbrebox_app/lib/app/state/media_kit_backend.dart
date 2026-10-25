import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'audio_source.dart';
import 'player_backend.dart';

/// libmpv-backed audio backend (media_kit). mpv streams DASH/fragmented audio
/// (YouTube) and remote URLs with request headers natively, so no loopback relay
/// or file buffering is needed.
final class MediaKitBackend
    implements
        AudioBackend,
        ProgressAudioBackend,
        RateAudioBackend,
        StartPositionAudioBackend {
  MediaKitBackend({Player? player}) : _player = player ?? Player();

  final Player _player;
  var _disposed = false;

  @override
  Stream<void> get completed =>
      _player.stream.completed.where((done) => done).map((_) {});

  @override
  Stream<Duration> get positions => _player.stream.position;

  @override
  Stream<Duration> get durations => _player.stream.duration;

  /// The OS audio output devices, updated live by libmpv's `audio-device-list`.
  /// Used on desktop to detect a Bluetooth/headphone connect or disconnect.
  Stream<List<AudioDevice>> get audioDeviceList => _player.stream.audioDevices;

  @override
  Future<void> setReleaseMode(AudioReleaseMode mode) => _player.setPlaylistMode(
    switch (mode) {
      AudioReleaseMode.loop => PlaylistMode.single,
      AudioReleaseMode.stop => PlaylistMode.none,
    },
  );

  @override
  Future<void> setSource(AudioSourceSpec source) => _open(source, null);

  /// Opens [source] at [start]: libmpv applies `start` while opening, where a
  /// seek sent right after opening may be dropped before the stream is ready.
  @override
  Future<void> setSourceFrom(AudioSourceSpec source, Duration start) =>
      _open(source, start);

  Future<void> _open(AudioSourceSpec source, Duration? start) {
    _ensureLive();
    return switch (source) {
      RemoteAudioSource(:final uri, :final headers) => _player.open(
        Media(
          uri.toString(),
          httpHeaders: headers.isEmpty ? null : Map<String, String>.of(headers),
          start: start,
        ),
        play: false,
      ),
      LocalAudioSource(:final path) => _player.open(
        Media(path, start: start),
        play: false,
      ),
    };
  }

  @override
  Future<void> resume() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> releaseSource() => _player.stop();

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0, 1) * 100);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate.clamp(0.25, 3.0));

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.dispose();
  }

  void _ensureLive() {
    if (_disposed) throw StateError('音频后端已经释放。');
  }
}
