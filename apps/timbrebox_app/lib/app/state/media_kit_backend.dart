import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../design/app_strings.dart';
import 'audio_source.dart';
import 'player_backend.dart';
import 'position_sampler.dart';

/// libmpv-backed audio backend (media_kit). mpv streams DASH/fragmented audio
/// (YouTube) and remote URLs with request headers natively.
final class MediaKitBackend
    implements
        AudioBackend,
        ProgressAudioBackend,
        RateAudioBackend,
        StartPositionAudioBackend {
  MediaKitBackend({Player? player})
    : _player = player ?? Player(configuration: configuration) {
    final native = _player.platform;
    if (native is NativePlayer) {
      for (final MapEntry(:key, :value) in mpvProperties.entries) {
        unawaited(native.setProperty(key, value));
      }
      unawaited(_samplePositions(native));
    }
    _positionForward = _player.stream.position.listen(_positions.add);
  }

  /// Audio-only libmpv: an 8 MB demuxer cache instead of media_kit's 32 MB
  /// (sized for video), and no video output. Video decoding stays off too:
  /// media_kit opens with `vid=no` until a video view attaches, and none
  /// does, so Douyin / TikTok MP4s play their audio track only.
  static const configuration = PlayerConfiguration(
    bufferSize: 8 * 1024 * 1024,
    vo: 'null',
  );

  /// Set right after the player is created. media_kit keeps as much behind
  /// the playhead as ahead of it; a music player seeks back rarely, so 2 MB
  /// is plenty. `vid=no` is stated here as well rather than left to
  /// media_kit's default.
  static const mpvProperties = {
    'demuxer-max-back-bytes': '${2 * 1024 * 1024}',
    'vid': 'no',
  };

  final Player _player;
  var _disposed = false;

  /// Positions from media_kit (until `time-pos` is unobserved, then only its
  /// reset to 0 when a source is released) and from [_sampler].
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  late final StreamSubscription<Duration> _positionForward;
  PositionSampler? _sampler;
  StreamSubscription<Duration>? _sampleForward;

  /// media_kit observes libmpv's `time-pos`, which fires on every audio tick
  /// (10-50 times a second), each one a trip into Dart. Stop that at the
  /// source and read the position a few times a second while playing.
  Future<void> _samplePositions(NativePlayer native) async {
    await native.waitForPlayerInitialization;
    if (_disposed) return;
    // media_kit registers each observed property with its name's hashCode.
    native.mpv.mpv_unobserve_property(native.ctx, 'time-pos'.hashCode);
    final sampler = PositionSampler(
      read: () => _readPosition(native),
      playing: _player.stream.playing,
      initiallyPlaying: _player.state.playing,
    );
    _sampler = sampler;
    _sampleForward = sampler.positions.listen(_positions.add);
  }

  Future<Duration?> _readPosition(NativePlayer native) async {
    if (_disposed) return null;
    final seconds = double.tryParse(await native.getProperty('time-pos'));
    if (seconds == null || _disposed) return null;
    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  @override
  Stream<void> get completed =>
      _player.stream.completed.where((done) => done).map((_) {});

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<Duration> get durations => _player.stream.duration;

  /// The OS audio output devices, updated live by libmpv's `audio-device-list`.
  /// Used on desktop to detect a Bluetooth/headphone connect or disconnect.
  Stream<List<AudioDevice>> get audioDeviceList => _player.stream.audioDevices;

  @override
  Future<void> setReleaseMode(AudioReleaseMode mode) =>
      _player.setPlaylistMode(switch (mode) {
        AudioReleaseMode.loop => PlaylistMode.single,
        AudioReleaseMode.stop => PlaylistMode.none,
      });

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
    await _sampleForward?.cancel();
    _sampler?.dispose();
    await _positionForward.cancel();
    await _positions.close();
    await _player.dispose();
  }

  void _ensureLive() {
    if (_disposed) throw StateError(AppStrings.t('stream.err.backendReleased'));
  }
}
