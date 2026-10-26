import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../design/app_strings.dart';
import 'audio_source.dart';
import 'player_backend.dart';
import 'position_sampler.dart';

/// libmpv-backed audio backend (media_kit). mpv streams DASH/fragmented audio
/// (YouTube) and remote URLs with request headers natively.
///
/// libmpv is loaded and started on the first source, not at launch: an idle
/// app that has not played anything yet saves its ~50 MB (libmpv and its
/// ffmpeg libraries, mpv's core and Lua script threads). Volume, rate and
/// loop mode set before then are applied when it starts.
final class MediaKitBackend
    implements
        AudioBackend,
        ProgressAudioBackend,
        RateAudioBackend,
        StartPositionAudioBackend {
  /// [createPlayer] makes the libmpv player when it is first needed.
  MediaKitBackend({Player Function()? createPlayer})
    : _createPlayer = createPlayer ?? _createLibmpvPlayer;

  /// Loads libmpv (media_kit's `ensureInitialized` opens the library) and
  /// starts a player.
  static Player _createLibmpvPlayer() {
    MediaKit.ensureInitialized();
    return Player(configuration: configuration);
  }

  final Player Function() _createPlayer;
  Player? _started;

  /// The player, started now if this is the first use.
  Player get _player => _started ?? _start();

  Player _start() {
    final player = _started = _createPlayer();
    final native = player.platform;
    if (native is NativePlayer) {
      for (final MapEntry(:key, :value) in mpvProperties.entries) {
        unawaited(native.setProperty(key, value));
      }
      unawaited(_samplePositions(native, player));
    }
    _forwards.addAll([
      player.stream.position.listen(_positions.add),
      player.stream.completed.where((done) => done).listen(_completed.add),
      player.stream.duration.listen(_durations.add),
      player.stream.audioDevices.listen(_audioDevices.add),
    ]);
    unawaited(player.setVolume(_volume));
    unawaited(player.setRate(_rate));
    unawaited(player.setPlaylistMode(_playlistMode));
    return player;
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

  var _disposed = false;

  /// Applied when the player starts; kept current after that as well.
  var _volume = 100.0;
  var _rate = 1.0;
  var _playlistMode = PlaylistMode.none;

  /// Positions from media_kit (until `time-pos` is unobserved, then only its
  /// reset to 0 when a source is released) and from [_sampler].
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completed = StreamController<void>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<List<AudioDevice>> _audioDevices =
      StreamController<List<AudioDevice>>.broadcast();
  final List<StreamSubscription<Object?>> _forwards = [];
  PositionSampler? _sampler;
  StreamSubscription<Duration>? _sampleForward;

  /// media_kit observes libmpv's `time-pos`, which fires on every audio tick
  /// (10-50 times a second), each one a trip into Dart. Stop that at the
  /// source and read the position a few times a second while playing.
  Future<void> _samplePositions(NativePlayer native, Player player) async {
    await native.waitForPlayerInitialization;
    if (_disposed) return;
    // media_kit registers each observed property with its name's hashCode.
    native.mpv.mpv_unobserve_property(native.ctx, 'time-pos'.hashCode);
    final sampler = PositionSampler(
      read: () => _readPosition(native),
      playing: player.stream.playing,
      initiallyPlaying: player.state.playing,
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
  Stream<void> get completed => _completed.stream;

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<Duration> get durations => _durations.stream;

  /// The OS audio output devices, updated live by libmpv's `audio-device-list`.
  /// Used on desktop to detect a Bluetooth/headphone connect or disconnect.
  Stream<List<AudioDevice>> get audioDeviceList => _audioDevices.stream;

  @override
  Future<void> setReleaseMode(AudioReleaseMode mode) async {
    _playlistMode = switch (mode) {
      AudioReleaseMode.loop => PlaylistMode.single,
      AudioReleaseMode.stop => PlaylistMode.none,
    };
    await _started?.setPlaylistMode(_playlistMode);
  }

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
  Future<void> resume() async => _started?.play();

  // Before the first source there is nothing to pause, stop or seek: these
  // do not start libmpv.
  @override
  Future<void> pause() async => _started?.pause();

  @override
  Future<void> stop() async => _started?.stop();

  @override
  Future<void> releaseSource() async => _started?.stop();

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 1) * 100;
    await _started?.setVolume(_volume);
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.25, 3.0);
    await _started?.setRate(_rate);
  }

  @override
  Future<void> seek(Duration position) async => _started?.seek(position);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sampleForward?.cancel();
    _sampler?.dispose();
    for (final forward in _forwards) {
      await forward.cancel();
    }
    await _positions.close();
    await _completed.close();
    await _durations.close();
    await _audioDevices.close();
    await _started?.dispose();
  }

  void _ensureLive() {
    if (_disposed) throw StateError(AppStrings.t('stream.err.backendReleased'));
  }
}
