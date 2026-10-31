import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/media_extractor_process.dart';
import 'package:timbrebox_app/app/plugins/media_stream_probe.dart';
import 'package:timbrebox_app/app/plugins/platform_media_backend.dart';
import 'package:timbrebox_app/app/plugins/platform_media_data.dart';
import 'package:timbrebox_app/app/plugins/platform_media_reference.dart';

// Unit protocol tests deliberately do not contact media CDNs. Real guarded
// transport and native playback are covered by separate probe/integration tests.
class _Probe implements MediaStreamProbe {
  _Probe({this.failures = const [], this.afterAttempt});
  final List<MediaExtractionException> failures;
  final void Function(int)? afterAttempt;
  var attempts = 0;
  @override
  Future<Map<String, Object?>> select(
    List<Map<String, Object?>> candidates,
  ) async {
    final index = attempts++;
    afterAttempt?.call(index);
    if (index < failures.length) throw failures[index];
    return candidates.first;
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _Runner implements MediaExtractionRunner {
  final calls = <List<String>>[];
  Object response = <String, Object?>{};
  bool disposed = false;
  bool cancelled = false;
  @override
  Future<String> run(List<String> arguments) async {
    calls.add(arguments);
    return response is String ? response as String : jsonEncode(response);
  }

  @override
  void cancel() => cancelled = true;
  @override
  void dispose() => disposed = true;
}

class _WaitingRunner extends _Runner {
  final pending = Completer<String>();
  @override
  Future<String> run(List<String> arguments) {
    calls.add(arguments);
    return pending.future;
  }
}

Map<String, Object?> _video({
  String id = 'abcdefghijk',
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'webpage_url': 'https://www.youtube.com/watch?v=$id',
  'title': 'Demo public-domain performance',
  'uploader': 'Demo Artist',
  'duration': 120,
  'availability': 'public',
  'is_paid': false,
  'is_preview': false,
  'formats': [
    {
      'url': 'https://media.example/audio.m4a?token=demo',
      'vcodec': 'none',
      'acodec': 'aac',
      'protocol': 'https',
      'ext': 'm4a',
      'abr': 128,
    },
    {
      'url': 'https://media.example/video.mp4',
      'vcodec': 'h264',
      'acodec': 'aac',
      'protocol': 'https',
      'ext': 'mp4',
      'abr': 256,
    },
  ],
  ...extra,
};

Matcher _code(String value) =>
    isA<MediaExtractionException>().having((e) => e.code, 'code', value);

void main() {
  group('stable references', () {
    test('normalizes YouTube links and drops tracking', () {
      for (final url in [
        'https://youtu.be/abcdefghijk?tracking=demo',
        'https://www.youtube.com/shorts/abcdefghijk',
      ]) {
        final ref = PlatformMediaReference.parse('youtube', 'Share $url 查看');
        expect(ref.id, 'abcdefghijk');
        expect(
          ref.url.toString(),
          'https://www.youtube.com/watch?v=abcdefghijk',
        );
      }
    });
    test('accepts Bilibili parts and trailing slash', () {
      final ref = PlatformMediaReference.parse(
        'bilibili',
        'https://www.bilibili.com/video/BV1234567890/?p=2&tracking=demo',
      );
      expect(ref.id, 'BV1234567890');
      expect(ref.part, 2);
      expect(ref.url.queryParameters, {'p': '2'});
    });
    test('TikTok handle survives stable item reconstruction', () {
      final ref = PlatformMediaReference.fromItem('tiktok', {
        'id': '1234567890123456789',
        'handle': 'demo.artist',
      });
      expect(
        ref.url.toString(),
        'https://www.tiktok.com/@demo.artist/video/1234567890123456789',
      );
    });
    test('Douyin share/video normalizes to canonical identity', () {
      final ref = PlatformMediaReference.parse(
        'douyin',
        'https://www.iesdouyin.com/share/video/1234567890123456789/',
      );
      expect(
        ref.url.toString(),
        'https://www.douyin.com/video/1234567890123456789',
      );
    });
    test('allows only known short-link forms', () {
      for (final pair in [
        ['youtube', 'https://youtu.be/abcdefghijk'],
        ['bilibili', 'https://b23.tv/Demo'],
        ['douyin', 'https://v.douyin.com/Demo/'],
        ['tiktok', 'https://vm.tiktok.com/Demo/'],
      ]) {
        expect(
          () => PlatformMediaReference.parse(pair[0], pair[1]),
          returnsNormally,
        );
      }
    });
    for (final url in [
      'http://www.youtube.com/watch?v=abcdefghijk',
      'https://www.youtube.com.evil.example/watch?v=abcdefghijk',
      'https://demo:secret@www.youtube.com/watch?v=abcdefghijk',
      'https://www.youtube.com:8443/watch?v=abcdefghijk',
      'https://127.0.0.1/watch?v=abcdefghijk',
      'https://www.youtube.com/redirect?q=https://music.example/',
    ]) {
      test('rejects unsafe page reference', () {
        expect(
          () => PlatformMediaReference.parse('youtube', url),
          throwsA(_code('invalid_media_reference')),
        );
      });
    }
    test('crafted item ID cannot inject query parameters', () {
      expect(
        () => PlatformMediaReference.fromItem('youtube', {
          'id': 'abcdefghijk&v=other',
        }),
        throwsA(_code('invalid_media_reference')),
      );
    });
  });

  group('content filtering', () {
    test('only explicit public/free/non-preview evidence allows playback', () {
      expect(mediaAccess(_video()), MediaAccess.allowed);
      final unknown = _video()
        ..remove('is_paid')
        ..remove('is_preview');
      expect(mediaAccess(unknown), MediaAccess.unknown);
      expect(
        () => playableMedia(unknown),
        throwsA(_code('content_unverified')),
      );
    });
    for (final flag in [
      'is_paid',
      'is_vip',
      'is_preview',
      'is_trial',
      'is_private',
      'privateItem',
      'subscriber_only',
    ]) {
      test('excludes $flag', () {
        final raw = _video(extra: {flag: true});
        expect(mediaAccess(raw), MediaAccess.excluded);
        expect(() => playableMedia(raw), throwsA(_code('content_excluded')));
      });
    }
    for (final availability in [
      'premium_only',
      'subscriber_only',
      'needs_auth',
      'private',
    ]) {
      test(
        'excludes $availability',
        () => expect(
          mediaAccess(_video(extra: {'availability': availability})),
          MediaAccess.excluded,
        ),
      );
    }
    test('unknown entitlement objects and flag values are not free', () {
      expect(
        mediaAccess(_video(extra: {'is_paid': 'unknown'})),
        MediaAccess.unknown,
      );
      for (final field in [
        'pay_info',
        'payment_info',
        'paidContentInfo',
        'series',
        'series_info',
      ]) {
        expect(mediaAccess(_video(extra: {field: {}})), MediaAccess.unknown);
      }
      for (final field in [
        'isPaid',
        'is_pay',
        'isPay',
        'isVip',
        'vip_only',
        'isPreview',
        'isTrial',
        'trial_only',
        'preview_only',
        'secret',
        'isPrivate',
        'isProhibited',
        'takeDown',
        'forFriend',
      ]) {
        expect(mediaAccess(_video(extra: {field: true})), MediaAccess.excluded);
      }
      expect(
        mediaAccess(_video(extra: {'section_start': 5})),
        MediaAccess.excluded,
      );
    });
    test(
      'audio only, MIME and safe headers are preserved without credentials',
      () {
        final media = playableMedia(
          _video(
            extra: {
              'http_headers': {
                'Referer': 'https://www.youtube.com/',
                'Cookie': 'secret',
                'Authorization': 'secret',
                'Host': 'private.example',
                'Origin': 'bad\r\nheader',
              },
            },
          ),
        );
        expect(media['url'], contains('/audio.m4a'));
        expect(media['mimeType'], 'audio/mp4');
        expect(media['headers'], {'referer': 'https://www.youtube.com/'});
      },
    );
    test('rejects trial, DRM, private URLs and manifest-only formats', () {
      for (final change in [
        {'is_trial': true},
        {'has_drm': true},
        {'url': 'file:///private'},
        {'url': 'https://demo:secret@media.example/audio'},
        {'protocol': 'm3u8_native'},
      ]) {
        final raw = _video(
          extra: {
            'formats': [
              {
                'url': 'https://media.example/audio.m4a',
                'vcodec': 'none',
                'acodec': 'aac',
                'protocol': 'https',
                ...change,
              },
            ],
          },
        );
        expect(() => playableMedia(raw), throwsA(_code('media_unavailable')));
      }
    });
    test('does not fall back to muxed video', () {
      expect(
        () => playableMedia(
          _video(
            extra: {
              'formats': [
                {
                  'url': 'https://media.example/video.mp4',
                  'vcodec': 'h264',
                  'acodec': 'aac',
                },
              ],
            },
          ),
        ),
        throwsA(_code('media_unavailable')),
      );
    });
    test('Bilibili parts have distinct saved identities', () {
      final item = mediaItem('bilibili', {
        ..._video(),
        'webpage_url': 'https://www.bilibili.com/video/BV1234567890?p=2',
      });
      expect(item['id'], 'BV1234567890:p2');
      final ref = PlatformMediaReference.fromItem('bilibili', item);
      expect(ref.id, 'BV1234567890');
      expect(ref.part, 2);
    });
  });

  group('fixed host operations', () {
    late _Runner runner;
    late DesktopPlatformMediaBackend backend;
    setUp(() {
      runner = _Runner();
      backend = DesktopPlatformMediaBackend(runner: runner, probe: _Probe());
    });
    tearDown(() => backend.dispose());
    test(
      'search paginates, filters paid entries and keeps unknown entries marked',
      () async {
        final unknown = _video(id: 'bcdefghijkl')
          ..remove('is_paid')
          ..remove('is_preview');
        runner.response = {
          'entries': [
            _video(),
            _video(extra: {'is_paid': true}),
            unknown,
          ],
        };
        final result = await backend.call({
          'platform': 'youtube',
          'operation': 'search',
          'query': '--exec demo',
          'page': 2,
        });
        expect((result['data'] as List).length, 2);
        expect(
          ((result['data'] as List).last as Map)['accessState'],
          'unknown',
        );
        expect(result['excludedCount'], 1);
        final args = runner.calls.single;
        expect(
          args,
          containsAll([
            '--ignore-config',
            '--no-plugin-dirs',
            '--no-cache-dir',
            '--no-js-runtimes',
            '--no-remote-components',
            '--skip-download',
          ]),
        );
        expect(args[args.indexOf('--playlist-start') + 1], '11');
        expect(args[args.indexOf('--playlist-end') + 1], '20');
        expect(args.last, 'ytsearch20:--exec demo');
        expect(args[args.length - 2], '--');
      },
    );
    test('Bilibili uses its own search operation', () async {
      runner.response = {'entries': []};
      await backend.call({
        'platform': 'bilibili',
        'operation': 'search',
        'query': 'demo',
        'page': 1,
      });
      expect(runner.calls.single.last, 'bilisearch10:demo');
    });
    test(
      'unsupported short-video search is an error, not empty success',
      () async {
        for (final platform in ['douyin', 'tiktok']) {
          await expectLater(
            backend.call({
              'platform': platform,
              'operation': 'search',
              'query': 'demo',
              'page': 1,
            }),
            throwsA(_code('platform_search_unavailable')),
          );
        }
        expect(runner.calls, isEmpty);
      },
    );
    test('invalid operations and input do not launch a process', () async {
      for (final request in [
        {'platform': 'other', 'operation': 'resolve'},
        {'platform': 'youtube', 'operation': 'exec'},
        {'platform': 'youtube', 'operation': 'search', 'query': '', 'page': 1},
        {
          'platform': 'youtube',
          'operation': 'search',
          'query': 'demo',
          'page': 6,
        },
        {
          'platform': 'youtube',
          'operation': 'resolve',
          'url': 'https://127.0.0.1/',
        },
      ]) {
        await expectLater(
          backend.call(request),
          throwsA(isA<MediaExtractionException>()),
        );
      }
      expect(runner.calls, isEmpty);
    });
    test(
      'resolve re-fetches stable reference and never trusts a saved stream URL',
      () async {
        runner.response = _video();
        final result = await backend.call({
          'platform': 'youtube',
          'operation': 'resolve',
          'item': {
            'id': 'abcdefghijk',
            'url': 'https://private.example/ignored',
            'accessState': 'allowed',
          },
        });
        expect(
          runner.calls.single.last,
          'https://www.youtube.com/watch?v=abcdefghijk',
        );
        expect((result['media'] as Map)['mimeType'], 'audio/mp4');
        expect((result['item'] as Map).containsKey('url'), false);
        runner.response = _video(extra: {'is_paid': true});
        await expectLater(
          backend.call({
            'platform': 'youtube',
            'operation': 'resolve',
            'item': {'id': 'abcdefghijk'},
          }),
          throwsA(_code('content_excluded')),
        );
        expect(runner.calls.length, 2);
      },
    );
    test('identity mismatches are rejected before playback', () async {
      runner.response = _video(id: 'bcdefghijkl');
      await expectLater(
        backend.call({
          'platform': 'youtube',
          'operation': 'resolve',
          'url': 'https://youtu.be/abcdefghijk',
        }),
        throwsA(_code('extractor_invalid_data')),
      );
    });
    test('Bilibili part mismatch cannot play the wrong part', () async {
      runner.response = {
        ..._video(),
        'webpage_url': 'https://www.bilibili.com/video/BV1234567890?p=1',
      };
      await expectLater(
        backend.call({
          'platform': 'bilibili',
          'operation': 'resolve',
          'url': 'https://www.bilibili.com/video/BV1234567890?p=2',
        }),
        throwsA(_code('extractor_invalid_data')),
      );
    });
    test(
      'raw output and invalid search schemas are not leaked or treated as empty',
      () async {
        runner.response = 'token=demo secret';
        await expectLater(
          backend.call({
            'platform': 'youtube',
            'operation': 'search',
            'query': 'demo',
            'page': 1,
          }),
          throwsA(_code('extractor_invalid_data')),
        );
        runner.response = {
          'entries': [
            {'title': 'invalid', 'url': 'https://music.example/'},
          ],
        };
        await expectLater(
          backend.call({
            'platform': 'youtube',
            'operation': 'search',
            'query': 'demo',
            'page': 1,
          }),
          throwsA(_code('extractor_invalid_data')),
        );
      },
    );
    test(
      'a refused CDN address triggers at most one official metadata refresh',
      () async {
        const denied = MediaExtractionException(
          'media_access_denied',
          'Synthetic CDN refusal',
        );
        runner.response = _video();
        final probe = _Probe(failures: [denied]);
        final recovering = DesktopPlatformMediaBackend(
          runner: runner,
          probe: probe,
        );
        addTearDown(recovering.dispose);
        final result = await recovering.call({
          'platform': 'youtube',
          'operation': 'resolve',
          'url': 'https://youtu.be/abcdefghijk',
        });
        expect(result['media'], isA<Map>());
        expect(runner.calls, hasLength(2));
        expect(runner.calls[0], runner.calls[1]);
        expect(probe.attempts, 2);
      },
    );

    test(
      'a second CDN refusal is returned without unbounded refreshes',
      () async {
        const denied = MediaExtractionException(
          'media_access_denied',
          'Synthetic CDN refusal',
        );
        runner.response = _video();
        final probe = _Probe(failures: [denied, denied]);
        final recovering = DesktopPlatformMediaBackend(
          runner: runner,
          probe: probe,
        );
        addTearDown(recovering.dispose);
        await expectLater(
          recovering.call({
            'platform': 'youtube',
            'operation': 'resolve',
            'url': 'https://youtu.be/abcdefghijk',
          }),
          throwsA(_code('media_access_denied')),
        );
        expect(runner.calls, hasLength(2));
        expect(probe.attempts, 2);
      },
    );

    test(
      'refreshed official metadata must pass paid and identity checks again',
      () async {
        for (final replacement in [
          _video(extra: {'is_paid': true}),
          _video(id: 'different01'),
        ]) {
          final local = _Runner()..response = _video();
          const denied = MediaExtractionException(
            'media_access_denied',
            'Synthetic CDN refusal',
          );
          final probe = _Probe(
            failures: [denied],
            afterAttempt: (_) => local.response = replacement,
          );
          final recovering = DesktopPlatformMediaBackend(
            runner: local,
            probe: probe,
          );
          await expectLater(
            recovering.call({
              'platform': 'youtube',
              'operation': 'resolve',
              'url': 'https://youtu.be/abcdefghijk',
            }),
            throwsA(isA<MediaExtractionException>()),
          );
          expect(local.calls, hasLength(2));
          expect(probe.attempts, 1);
          recovering.dispose();
        }
      },
    );

    test(
      'unverified content and generic network failures are not refreshed',
      () async {
        for (final failure in [
          const MediaExtractionException(
            'media_unavailable',
            'Synthetic network failure',
          ),
          const MediaExtractionException(
            'content_unverified',
            'Synthetic access failure',
          ),
        ]) {
          final local = _Runner()..response = _video();
          final probe = _Probe(failures: [failure]);
          final recovering = DesktopPlatformMediaBackend(
            runner: local,
            probe: probe,
          );
          await expectLater(
            recovering.call({
              'platform': 'youtube',
              'operation': 'resolve',
              'url': 'https://youtu.be/abcdefghijk',
            }),
            throwsA(_code(failure.code)),
          );
          expect(local.calls, hasLength(1));
          recovering.dispose();
        }
      },
    );

    test(
      'the whole resolution budget cancels unfinished metadata work',
      () async {
        final local = _WaitingRunner();
        final recovering = DesktopPlatformMediaBackend(
          runner: local,
          probe: _Probe(),
          resolutionBudget: const Duration(milliseconds: 10),
        );
        addTearDown(recovering.dispose);
        await expectLater(
          recovering.call({
            'platform': 'youtube',
            'operation': 'resolve',
            'url': 'https://youtu.be/abcdefghijk',
          }),
          throwsA(_code('extractor_timeout')),
        );
        expect(local.cancelled, isTrue);
        expect(local.calls, hasLength(1));
        local.pending.complete(jsonEncode(_video()));
        await pumpEventQueue();
      },
    );

    test('cancel and dispose reach the backend', () async {
      backend.cancel();
      expect(runner.cancelled, true);
      backend.dispose();
      expect(runner.disposed, true);
      await expectLater(
        backend.call({
          'platform': 'youtube',
          'operation': 'search',
          'query': 'demo',
          'page': 1,
        }),
        throwsA(_code('extractor_disposed')),
      );
    });
  });
}
