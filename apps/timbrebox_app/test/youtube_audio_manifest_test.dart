import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/media_extraction_error.dart';
import 'package:timbrebox_app/app/plugins/youtube_audio_manifest.dart';

// Synthetic unit protocol fixtures, separate from real app playback acceptance.
void main() {
  Matcher code(String expected) =>
      isA<MediaExtractionException>().having((e) => e.code, 'code', expected);
  test(
    'client is lazy and closes after manifest; AAC remains preferred to higher bitrate WebM',
    () async {
      var created = 0;
      final client = _Client([
        stream(container: 'webm', bitrate: 160000),
        stream(bitrate: 64000),
        stream(bitrate: 128000),
      ]);
      final provider = DartYouTubeAudioManifest(
        createClient: () {
          created++;
          return client;
        },
      );
      addTearDown(provider.dispose);
      expect(created, 0);
      final audio = await provider.resolve('abcdefghijk', 120);
      expect(created, 1);
      expect(client.closed, greaterThan(0));
      expect(audio.map((a) => a['mimeType']), [
        'audio/mp4',
        'audio/mp4',
        'audio/webm',
      ]);
      expect(audio.map((a) => a['bitrateKbps']), [128, 64, 160]);
      expect(audio.first, isNot(contains('is_paid')));
      expect(audio.first, isNot(contains('availability')));
    },
  );
  test(
    'identity, scheme, host, credentials, resource and full duration checks fail closed',
    () async {
      for (final bad in [
        stream(id: 'different01'),
        stream(url: 'http://media.googlevideo.com/v?dur=120'),
        stream(url: 'https://media.googlevideo.com.attacker.example/v?dur=120'),
        stream(url: 'https://user:secret@media.googlevideo.com/v?dur=120'),
        stream(url: 'https://media.googlevideo.com:444/v?dur=120'),
        stream(url: 'https://media.googlevideo.com/v?dur=15'),
        stream(url: 'https://media.googlevideo.com/v?dur=invalid'),
        stream(bitrate: 999999),
        stream(size: 0),
        stream(container: 'm3u8'),
      ]) {
        final provider = DartYouTubeAudioManifest(
          createClient: () => _Client([bad]),
        );
        await expectLater(
          provider.resolve('abcdefghijk', 120),
          throwsA(code('media_unavailable')),
        );
        provider.dispose();
      }
    },
  );
  test('unknown full duration cannot create a library request', () async {
    var calls = 0;
    final provider = DartYouTubeAudioManifest(
      createClient: () {
        calls++;
        return _Client([]);
      },
    );
    addTearDown(provider.dispose);
    await expectLater(
      provider.resolve('abcdefghijk', 0),
      throwsA(code('invalid_media_request')),
    );
    expect(calls, 0);
  });
  test(
    'timeout closes pending HTTP client and remains a typed failure',
    () async {
      final client = _Client.pending();
      final provider = DartYouTubeAudioManifest(
        createClient: () => client,
        timeout: const Duration(milliseconds: 10),
      );
      addTearDown(provider.dispose);
      await expectLater(
        provider.resolve('abcdefghijk', 120),
        throwsA(code('extractor_timeout')),
      );
      expect(client.closed, greaterThan(0));
      client.pending!.complete([]);
    },
  );
  test(
    'cancel closes the old client and a late result cannot affect the next operation',
    () async {
      final old = _Client.pending(), next = _Client([stream()]);
      var count = 0;
      final provider = DartYouTubeAudioManifest(
        createClient: () => count++ == 0 ? old : next,
      );
      addTearDown(provider.dispose);
      final result = provider.resolve('abcdefghijk', 120);
      final rejected = expectLater(
        result,
        throwsA(code('extractor_cancelled')),
      );
      provider.cancel();
      await rejected;
      final fresh = await provider.resolve('abcdefghijk', 120);
      old.pending!.complete([stream(id: 'different01')]);
      expect(fresh.single['mimeType'], 'audio/mp4');
      expect(old.closed, greaterThan(0));
    },
  );
  test(
    'dependency errors do not disclose signed addresses or raw details',
    () async {
      final provider = DartYouTubeAudioManifest(
        createClient: () => _Client.error(),
      );
      addTearDown(provider.dispose);
      await expectLater(
        provider.resolve('abcdefghijk', 120),
        throwsA(code('extractor_failed')),
      );
    },
  );
}

YouTubeAudioStream stream({
  String id = 'abcdefghijk',
  String url = 'https://media.googlevideo.com/v?dur=120',
  String container = 'mp4',
  int bitrate = 128000,
  int size = 2000000,
}) => YouTubeAudioStream(
  videoId: id,
  url: Uri.parse(url),
  container: container,
  bitrate: bitrate,
  size: size,
);

class _Client implements YouTubeAudioClient {
  _Client(this.streams) : pending = null, fail = false;
  _Client.pending()
    : streams = [],
      pending = Completer<List<YouTubeAudioStream>>(),
      fail = false;
  _Client.error() : streams = [], pending = null, fail = true;
  final List<YouTubeAudioStream> streams;
  final Completer<List<YouTubeAudioStream>>? pending;
  final bool fail;
  int closed = 0;
  @override
  Future<List<YouTubeAudioStream>> manifest(String id) async {
    if (fail) throw StateError('Synthetic sensitive transport error');
    return pending?.future ?? streams;
  }

  @override
  void close() {
    closed++;
  }
}
