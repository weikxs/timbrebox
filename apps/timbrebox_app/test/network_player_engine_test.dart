import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/state/audio_source.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/state/player_backend.dart';
import 'package:timbrebox_app/app/state/player_source_resolver.dart';

void main() {
  const candidate = StreamCandidate(
    ref: MediaRef(sourceId: 'youtube', itemId: 'video-1'),
    id: 'tb://youtube/video-1',
    label: 'high',
  );

  test(
    'passes resolved headers through the engine without dropping them',
    () async {
      final source = AudioSourceSpec.remote(
        Uri.parse('https://cdn.example.test/audio.m4a'),
        headers: const {'Referer': 'https://example.test'},
      );
      final backend = _FakeAudioBackend();
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _FixedResolver(source),
      );

      await engine.load(candidate);

      expect(backend.source, same(source));
      expect((backend.source! as RemoteAudioSource).headers, {
        'Referer': 'https://example.test',
      });
      await engine.release();
    },
  );

  test(
    'loads a local file source through the same PlayerEngine contract',
    () async {
      final backend = _FakeAudioBackend();
      final engine = NetworkPlayerEngine(
        backend: backend,
        resolver: _FixedResolver(AudioSourceSpec.localFile('/tmp/track.m4a')),
      );

      await engine.load(candidate);

      expect(backend.source, isA<LocalAudioSource>());
      expect((backend.source! as LocalAudioSource).path, '/tmp/track.m4a');
      await engine.release();
    },
  );

  test('default resolver accepts HTTPS and local file URIs only', () async {
    const resolver = DefaultPlayerSourceResolver();
    final remote = await resolver.resolve(
      const StreamCandidate(
        ref: MediaRef(sourceId: 'youtube', itemId: 'x'),
        id: 'https://cdn.example.test/x.m4a',
        label: 'standard',
      ),
    );
    final local = await resolver.resolve(
      const StreamCandidate(
        ref: MediaRef(sourceId: 'local', itemId: 'x'),
        id: 'file:///tmp/x.m4a',
        label: 'offline',
      ),
    );

    expect(remote, isA<RemoteAudioSource>());
    expect(local, isA<LocalAudioSource>());
    await expectLater(
      resolver.resolve(
        const StreamCandidate(
          ref: MediaRef(sourceId: 'youtube', itemId: 'x'),
          id: 'http://cdn.example.test/x.m4a',
          label: 'standard',
        ),
      ),
      throwsStateError,
    );
  });
}

class _FixedResolver implements PlayerSourceResolver {
  const _FixedResolver(this.source);

  final AudioSourceSpec source;

  @override
  Future<AudioSourceSpec> resolve(StreamCandidate candidate) async => source;
}

class _FakeAudioBackend implements AudioBackend {
  final StreamController<void> _completed = StreamController.broadcast();
  AudioSourceSpec? source;
  final List<String> calls = [];

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> setReleaseMode(AudioReleaseMode mode) async {
    calls.add('releaseMode');
  }

  @override
  Future<void> setSource(AudioSourceSpec value) async {
    source = value;
    calls.add('source');
  }

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> releaseSource() async => calls.add('releaseSource');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume');

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _completed.close();
  }
}
