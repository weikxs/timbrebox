import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:timbrebox_playback/timbrebox_playback.dart';

/// libmpv costs ~50 MB once started, so it starts on the first source only.
void main() {
  late List<_FakePlayer> created;
  late MediaKitBackend backend;

  setUp(() {
    created = [];
    backend = MediaKitBackend(
      createPlayer: () {
        final player = _FakePlayer();
        created.add(player);
        return player;
      },
    );
  });
  tearDown(() => backend.dispose());

  test('does not start libmpv for settings, listeners or controls', () async {
    final subscriptions = [
      backend.completed.listen((_) {}),
      backend.positions.listen((_) {}),
      backend.durations.listen((_) {}),
      backend.audioDeviceList.listen((_) {}),
    ];
    await backend.setVolume(.5);
    await backend.setRate(1.5);
    await backend.setReleaseMode(AudioReleaseMode.loop);
    await backend.pause();
    await backend.resume();
    await backend.seek(const Duration(seconds: 3));
    await backend.stop();
    await backend.releaseSource();

    expect(created, isEmpty);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });

  test('starts once on the first source, with the settings so far', () async {
    await backend.setVolume(.5);
    await backend.setRate(9);
    await backend.setReleaseMode(AudioReleaseMode.loop);

    await backend.setSource(LocalAudioSource('/music/a.mp3'));
    await backend.setSource(LocalAudioSource('/music/b.mp3'));

    expect(created, hasLength(1));
    final player = created.single;
    expect(player.volume, 50);
    expect(player.rate, 3.0);
    expect(player.mode, PlaylistMode.single);
    expect(player.opened, ['/music/a.mp3', '/music/b.mp3']);
  });

  test('forwards the player streams subscribed before it started', () async {
    final completions = <void>[];
    final durations = <Duration>[];
    final positions = <Duration>[];
    backend.completed.listen(completions.add);
    backend.durations.listen(durations.add);
    backend.positions.listen(positions.add);

    await backend.setSource(LocalAudioSource('/music/a.mp3'));
    final player = created.single;
    player.durations.add(const Duration(minutes: 3));
    player.positions.add(const Duration(seconds: 1));
    player.completions
      ..add(false)
      ..add(true);
    await pumpEventQueue();

    expect(durations, [const Duration(minutes: 3)]);
    expect(positions, [const Duration(seconds: 1)]);
    expect(completions, hasLength(1));
  });

  test('controls reach the player once it has started', () async {
    await backend.setSource(LocalAudioSource('/music/a.mp3'));
    await backend.resume();
    await backend.setVolume(.25);

    expect(created.single.calls, containsAllInOrder(['open', 'play']));
    expect(created.single.volume, 25);
  });
}

final class _FakePlayer extends Fake implements Player {
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final completions = StreamController<bool>.broadcast();
  final devices = StreamController<List<AudioDevice>>.broadcast();
  final calls = <String>[];
  final opened = <String>[];
  double? volume;
  double? rate;
  PlaylistMode? mode;

  @override
  PlatformPlayer? get platform => null;

  @override
  PlayerStream get stream => _FakeStream(this);

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Future<void> setRate(double rate) async => this.rate = rate;

  @override
  Future<void> setPlaylistMode(PlaylistMode playlistMode) async =>
      mode = playlistMode;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    calls.add('open');
    opened.add((playable as Media).uri);
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> dispose() async {
    await positions.close();
    await durations.close();
    await completions.close();
    await devices.close();
  }
}

final class _FakeStream extends Fake implements PlayerStream {
  _FakeStream(this._player);

  final _FakePlayer _player;

  @override
  Stream<Duration> get position => _player.positions.stream;

  @override
  Stream<Duration> get duration => _player.durations.stream;

  @override
  Stream<bool> get completed => _player.completions.stream;

  @override
  Stream<List<AudioDevice>> get audioDevices => _player.devices.stream;
}
