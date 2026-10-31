import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/media_extractor_process.dart';
import 'package:timbrebox_app/app/plugins/platform_media_data.dart';

Map<String, Object?> publicVideo() => {
  '_type': 'video',
  'extractor_key': 'Youtube',
  'availability': 'public',
  'age_limit': 0,
  'is_live': false,
  'was_live': false,
  'live_status': 'not_live',
  'duration': 120,
  'has_drm': false,
  'formats': [muxed()],
};
Map<String, Object?> muxed({
  int width = 320,
  int height = 240,
  num tbr = 300,
}) => {
  'url': 'https://media.example/demo.mp4',
  'vcodec': 'avc1',
  'acodec': 'mp4a.40.2',
  'ext': 'mp4',
  'protocol': 'https',
  'has_drm': false,
  'width': width,
  'height': height,
  'tbr': tbr,
};
Matcher code(String value) =>
    isA<MediaExtractionException>().having((e) => e.code, 'code', value);

void main() {
  test('real-schema public proof does not invent paid or preview fields', () {
    final raw = publicVideo();
    expect(raw.containsKey('is_paid'), false);
    expect(raw.containsKey('is_preview'), false);
    expect(mediaAccess(raw, platform: 'youtube'), MediaAccess.allowed);
    expect(mediaAccess(raw), MediaAccess.unknown);
    expect(mediaAccess(raw, platform: 'tiktok'), MediaAccess.unknown);
  });
  for (final key in [
    '_type',
    'extractor_key',
    'availability',
    'age_limit',
    'is_live',
    'was_live',
    'live_status',
    'duration',
    'has_drm',
    'formats',
  ]) {
    test('missing provider evidence stays unknown: $key', () {
      final raw = publicVideo()..remove(key);
      expect(mediaAccess(raw, platform: 'youtube'), MediaAccess.unknown);
    });
  }
  for (final key in [
    'is_paid',
    'is_vip',
    'is_preview',
    'is_trial',
    'is_private',
  ]) {
    test('explicit exclusion wins over a public provider response: $key', () {
      final raw = publicVideo()..[key] = true;
      expect(mediaAccess(raw, platform: 'youtube'), MediaAccess.excluded);
    });
    test('malformed access information remains unknown: $key', () {
      final raw = publicVideo()..[key] = 'unexpected';
      expect(mediaAccess(raw, platform: 'youtube'), MediaAccess.unknown);
    });
  }
  test(
    'live, private, partial and uninterpreted entitlement responses fail closed',
    () {
      for (final fields in [
        {'availability': 'premium_only'},
        {'_type': 'url'},
        {'is_live': true},
        {'age_limit': 18},
        {'section_start': 0},
        {'paidContentInfo': <String, Object?>{}},
      ]) {
        expect(
          mediaAccess({...publicVideo(), ...fields}, platform: 'youtube'),
          isNot(MediaAccess.allowed),
        );
      }
    },
  );
  test(
    'muxed fallback is explicit, bounded and reports the true container MIME',
    () {
      final raw = publicVideo();
      expect(
        () => playableMedia(raw, platform: 'youtube'),
        throwsA(code('media_unavailable')),
      );
      final selected = playableMedia(
        raw,
        platform: 'youtube',
        allowMuxedAudio: true,
      );
      expect(selected['mimeType'], 'video/mp4');
      expect(selected['audioOnlyPlayback'], true);
    },
  );
  test('unbounded or large video is not silently selected', () {
    for (final format in [
      muxed(width: 1920, height: 1080),
      muxed(tbr: 1501),
      muxed()..remove('tbr'),
      muxed()..['tbr'] = double.nan,
      muxed()..['has_drm'] = true,
      muxed()..['protocol'] = 'm3u8_native',
    ]) {
      final raw = publicVideo()..['formats'] = [format];
      expect(
        () => playableMedia(raw, platform: 'youtube', allowMuxedAudio: true),
        throwsA(code('media_unavailable')),
      );
    }
  });
  test('a real audio-only format always wins over a muxed format', () {
    final raw = publicVideo()
      ..['formats'] = [
        muxed(),
        {
          'url': 'https://media.example/demo.m4a',
          'vcodec': 'none',
          'acodec': 'aac',
          'ext': 'm4a',
          'protocol': 'https',
          'has_drm': false,
          'abr': 64,
        },
      ];
    final selected = playableMedia(
      raw,
      platform: 'youtube',
      allowMuxedAudio: true,
    );
    expect(selected['mimeType'], 'audio/mp4');
    expect(selected.containsKey('audioOnlyPlayback'), false);
  });
}
