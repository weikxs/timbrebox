import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/media_extractor_process.dart';
import 'package:timbrebox_app/app/plugins/media_stream_probe.dart';
import 'package:timbrebox_app/app/plugins/platform_media_backend.dart';
import 'package:timbrebox_app/app/plugins/youtube_audio_manifest.dart';

void main() {
  test(
    'original audio manifest replaces media extraction only after fresh access verification',
    () async {
      final provider = _Audio();
      final runner = _Runner();
      final backend = DesktopPlatformMediaBackend(
        runner: runner,
        probe: _Probe(),
        youtubeAudio: provider,
      );
      addTearDown(backend.dispose);
      final result = await backend.call(request);
      expect(provider.requests, [
        ['abcdefghijk', 120],
      ]);
      expect(runner.calls, 1);
      expect(
        (result['media'] as Map)['url'],
        'https://audio.googlevideo.com/original',
      );
      expect((result['media'] as Map)['boundedRanges'], true);
    },
  );
  test(
    'paid, preview, unknown and wrong-ID metadata never reach the original manifest client',
    () async {
      for (final values in [
        {'is_paid': true},
        {'is_preview': true},
        {'is_paid': null},
        {
          'id': 'different01',
          'webpage_url': 'https://www.youtube.com/watch?v=different01',
        },
        {'duration': null},
      ]) {
        final provider = _Audio();
        final runner = _Runner()..extra = values;
        final backend = DesktopPlatformMediaBackend(
          runner: runner,
          probe: _Probe(),
          youtubeAudio: provider,
        );
        await expectLater(
          backend.call(request),
          throwsA(isA<MediaExtractionException>()),
        );
        expect(provider.requests, isEmpty);
        backend.dispose();
      }
    },
  );
  test('original audio must receive a verified ranged response', () async {
    final backend = DesktopPlatformMediaBackend(
      runner: _Runner(),
      probe: _Probe(ranged: false),
      youtubeAudio: _Audio(),
    );
    addTearDown(backend.dispose);
    await expectLater(
      backend.call(request),
      throwsA(
        isA<MediaExtractionException>().having(
          (e) => e.code,
          'code',
          'media_unavailable',
        ),
      ),
    );
  });
  test(
    'total budget cancels a stalled audio phase after access was verified',
    () async {
      final pending = Completer<List<Map<String, Object?>>>();
      final provider = _Audio(pending: pending);
      final backend = DesktopPlatformMediaBackend(
        runner: _Runner(),
        probe: _Probe(),
        youtubeAudio: provider,
        resolutionBudget: const Duration(milliseconds: 20),
      );
      addTearDown(backend.dispose);
      await expectLater(
        backend.call(request),
        throwsA(
          isA<MediaExtractionException>().having(
            (error) => error.code,
            'code',
            'extractor_timeout',
          ),
        ),
      );
      expect(provider.requests, hasLength(1));
      expect(provider.cancelled, true);
      pending.complete([]);
    },
  );
  test('default resolution remains below the plugin async envelope', () {
    final backend = DesktopPlatformMediaBackend(
      runner: _Runner(),
      probe: _Probe(),
      youtubeAudio: _Audio(),
    );
    addTearDown(backend.dispose);
    expect(backend.resolutionBudget, const Duration(seconds: 24));
    expect(backend.resolutionBudget, lessThan(const Duration(seconds: 25)));
  });
  test('cancel and dispose include the original provider', () {
    final provider = _Audio();
    final backend = DesktopPlatformMediaBackend(
      runner: _Runner(),
      probe: _Probe(),
      youtubeAudio: provider,
    );
    backend.cancel();
    expect(provider.cancelled, true);
    backend.dispose();
    expect(provider.disposed, true);
  });
}

const request = {
  'platform': 'youtube',
  'operation': 'resolve',
  'url': 'https://youtu.be/abcdefghijk',
};

class _Audio implements YouTubeAudioManifest {
  _Audio({this.pending});
  final Completer<List<Map<String, Object?>>>? pending;
  final requests = <List<Object>>[];
  bool cancelled = false, disposed = false;
  @override
  Future<List<Map<String, Object?>>> resolve(
    String videoId,
    num duration,
  ) async {
    requests.add([videoId, duration]);
    if (pending != null) return pending!.future;
    return [
      {
        'url': 'https://audio.googlevideo.com/original',
        'mimeType': 'audio/mp4',
      },
    ];
  }

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class _Runner implements MediaExtractionRunner {
  Map<String, Object?> extra = {};
  int calls = 0;
  @override
  Future<String> run(List<String> arguments) async {
    calls++;
    return jsonEncode({
      'id': 'abcdefghijk',
      'webpage_url': 'https://www.youtube.com/watch?v=abcdefghijk',
      'title': 'Protocol fixture',
      'duration': 120,
      'availability': 'public',
      'is_paid': false,
      'is_preview': false,
      'formats': <Object>[],
      ...extra,
    });
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _Probe implements MediaStreamProbe {
  _Probe({this.ranged = true});
  final bool ranged;
  @override
  Future<Map<String, Object?>> select(
    List<Map<String, Object?>> candidates,
  ) async => {...candidates.first, if (ranged) 'boundedRanges': true};
  @override
  void cancel() {}
  @override
  void dispose() {}
}
