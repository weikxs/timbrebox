import 'media_extractor_process.dart';
import 'platform_media_reference.dart';

enum MediaAccess { allowed, excluded, unknown }

/// Provider flags are evidence, not defaults. Flat search entries often remain
/// unknown; they can be shown, but must pass a fresh full check before playing.
MediaAccess mediaAccess(Map raw, {String? platform}) {
  bool? flag(Object? value) => switch (value) {
    true || 1 || '1' => true,
    false || 0 || '0' => false,
    _ => null,
  };
  const paidKeys = [
    'is_paid',
    'isPaid',
    'is_pay',
    'isPay',
    'is_vip',
    'isVip',
    'vip_only',
    'subscriber_only',
  ];
  const previewKeys = [
    'is_preview',
    'isPreview',
    'is_trial',
    'isTrial',
    'trial_only',
    'preview_only',
  ];
  const privateKeys = [
    'privateItem',
    'secret',
    'is_private',
    'isPrivate',
    'isProhibited',
    'takeDown',
    'forFriend',
    'is_unplayable',
  ];
  final availability = raw['availability'];
  if ({
    'private',
    'premium_only',
    'subscriber_only',
    'needs_auth',
  }.contains(availability)) {
    return MediaAccess.excluded;
  }
  for (final key in [...paidKeys, ...previewKeys, ...privateKeys]) {
    if (flag(raw[key]) == true) return MediaAccess.excluded;
  }
  if (raw['section_start'] != null || raw['section_end'] != null) {
    return MediaAccess.excluded;
  }
  if (const [
    'pay_info',
    'payment_info',
    'paidContentInfo',
    'series',
    'series_info',
  ].any((key) => raw[key] != null)) {
    return MediaAccess.unknown;
  }
  if ([
    ...paidKeys,
    ...previewKeys,
    ...privateKeys,
  ].any((key) => raw.containsKey(key) && flag(raw[key]) == null)) {
    return MediaAccess.unknown;
  }
  // The trusted extractor maps YouTube's public playability to availability.
  // Normal, complete, anonymous videos do not expose invented price/trial
  // booleans. This provider-specific evidence never applies to flat search,
  // another extractor, live/age-gated content or an encrypted response.
  if (platform == 'youtube' &&
      raw['extractor_key'] == 'Youtube' &&
      raw['_type'] == 'video' &&
      availability == 'public' &&
      raw['age_limit'] == 0 &&
      raw['is_live'] == false &&
      raw['was_live'] == false &&
      raw['live_status'] == 'not_live' &&
      raw['has_drm'] == false &&
      raw['duration'] is num &&
      (raw['duration'] as num).isFinite &&
      (raw['duration'] as num) > 0 &&
      raw['formats'] is List &&
      (raw['formats'] as List).isNotEmpty) {
    return MediaAccess.allowed;
  }
  bool explicitlyClear(List<String> keys) =>
      keys.any((key) => flag(raw[key]) == false) &&
      keys.every((key) => !raw.containsKey(key) || flag(raw[key]) == false);
  if (availability != 'public' ||
      !explicitlyClear(paidKeys) ||
      !explicitlyClear(previewKeys)) {
    return MediaAccess.unknown;
  }
  return MediaAccess.allowed;
}

Map<String, Object?> mediaItem(
  String platform,
  Map raw, {
  PlatformMediaReference? expected,
}) {
  final address = raw['webpage_url'] ?? raw['original_url'] ?? raw['url'];
  if (address is! String) {
    throw const MediaExtractionException(
      'extractor_invalid_data',
      'The platform returned no stable page reference.',
    );
  }
  final reference = PlatformMediaReference.parse(platform, address);
  if (reference.id == null ||
      expected?.id != null && expected!.id != reference.id) {
    throw const MediaExtractionException(
      'extractor_invalid_data',
      'The platform returned a different content identity.',
    );
  }
  if (platform != 'bilibili' &&
      raw['id'] is String &&
      raw['id'] != reference.id) {
    throw const MediaExtractionException(
      'extractor_invalid_data',
      'The returned item ID does not match its page reference.',
    );
  }
  if (platform == 'bilibili' &&
      expected?.part != null &&
      (reference.part ?? 1) != expected!.part) {
    throw const MediaExtractionException(
      'extractor_invalid_data',
      'The returned Bilibili part does not match the requested part.',
    );
  }
  final title = raw['title'];
  if (title is! String || title.trim().isEmpty || title.length > 2000) {
    throw const MediaExtractionException(
      'extractor_invalid_data',
      'The platform returned no valid title.',
    );
  }
  final duration = raw['duration'];
  final artist = raw['artist'] ?? raw['uploader'] ?? raw['channel'];
  final thumbnail = raw['thumbnail'];
  final access = mediaAccess(raw, platform: platform);
  final part = expected?.part ?? reference.part;
  return {
    'id': part != null && part > 1 ? '${reference.id}:p$part' : reference.id,
    if (platform == 'bilibili') 'videoId': reference.id,
    'title': title.trim(),
    'artist': artist is String
        ? artist.substring(0, artist.length.clamp(0, 1000))
        : platform,
    if (duration is num && duration.isFinite && duration > 0)
      'duration': duration,
    if (thumbnail is String && Uri.tryParse(thumbnail)?.scheme == 'https')
      'artwork': thumbnail,
    if (reference.handle != null) 'handle': reference.handle,
    'part': ?part,
    'accessState': access.name,
    'contentKind': 'video_audio',
  };
}

Map<String, Object?> playableMedia(
  Map raw, {
  String? platform,
  bool allowMuxedAudio = false,
}) => playableMediaCandidates(
  raw,
  platform: platform,
  allowMuxedAudio: allowMuxedAudio,
).first;

void requireMediaAccess(Map raw, {String? platform}) {
  final access = mediaAccess(raw, platform: platform);
  if (access != MediaAccess.allowed) {
    throw MediaExtractionException(
      access == MediaAccess.excluded
          ? 'content_excluded'
          : 'content_unverified',
      'Paid, VIP, trial or unverified content cannot be played.',
    );
  }
}

List<Map<String, Object?>> playableMediaCandidates(
  Map raw, {
  String? platform,
  bool allowMuxedAudio = false,
}) {
  requireMediaAccess(raw, platform: platform);
  final formats = raw['formats'];
  final candidates = <Map>[];
  if (formats is List) {
    for (final format in formats) {
      if (format is Map &&
          format['vcodec'] == 'none' &&
          format['acodec'] is String &&
          format['acodec'] != 'none') {
        candidates.add(format);
      }
    }
  }
  if (candidates.isEmpty &&
      raw['vcodec'] == 'none' &&
      raw['acodec'] is String &&
      raw['acodec'] != 'none') {
    candidates.add(raw);
  }
  // Only the fixed desktop bridge opts into muxed fallback. The native player
  // has vid=no; limit network cost to 720p / 1.5 Mbps, never a separate music
  // excerpt. Audio-only formats always win, regardless of video bitrate.
  final muxed = <Map>[];
  if (allowMuxedAudio && formats is List) {
    for (final format in formats.whereType<Map>()) {
      final width = format['width'];
      final height = format['height'];
      final rate = format['tbr'];
      if (format['vcodec'] is String &&
          format['vcodec'] != 'none' &&
          format['acodec'] is String &&
          format['acodec'] != 'none' &&
          {'mp4', 'webm'}.contains(format['ext']) &&
          width is num &&
          width.isFinite &&
          width > 0 &&
          height is num &&
          height.isFinite &&
          height > 0 &&
          width * height <= 1280 * 720 &&
          rate is num &&
          rate.isFinite &&
          rate > 0 &&
          rate <= 1500) {
        muxed.add(format);
      }
    }
  }
  final audioOnly = Set<Map>.identity()..addAll(candidates);
  candidates.addAll(muxed);
  candidates.removeWhere((format) {
    final uri = Uri.tryParse('${format['url'] ?? ''}');
    final protocol = format['protocol'];
    return uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (raw['has_drm'] != null && raw['has_drm'] != false) ||
        (format['has_drm'] != null && format['has_drm'] != false) ||
        mediaAccess({...raw, ...format}, platform: platform) !=
            MediaAccess.allowed ||
        protocol != null && !{'http', 'https'}.contains(protocol);
  });
  num bitrate(Map format) => format['abr'] is num ? format['abr'] as num : 0;
  candidates.sort((a, b) {
    final aAudio = audioOnly.contains(a);
    final bAudio = audioOnly.contains(b);
    if (aAudio != bAudio) return aAudio ? -1 : 1;
    return aAudio
        ? bitrate(b).compareTo(bitrate(a))
        : (a['tbr'] as num).compareTo(b['tbr'] as num);
  });
  if (candidates.isEmpty) {
    throw const MediaExtractionException(
      'media_unavailable',
      'No supported audio stream within the resource budget is available.',
    );
  }
  return [
    for (final selected in candidates)
      _mediaDescription(raw, selected, isMuxed: !audioOnly.contains(selected)),
  ];
}

Map<String, Object?> _mediaDescription(
  Map raw,
  Map selected, {
  required bool isMuxed,
}) {
  final headers = <String, String>{};
  // Only transport headers, not cookies/authentication or hop-by-hop headers.
  for (final source in [raw['http_headers'], selected['http_headers']]) {
    if (source is! Map) continue;
    for (final entry in source.entries) {
      final name = '${entry.key}'.toLowerCase();
      if (!{
        'user-agent',
        'referer',
        'origin',
        'accept',
        'accept-language',
      }.contains(name)) {
        continue;
      }
      if (entry.value is String &&
          !(entry.value as String).contains(RegExp(r'[\r\n]'))) {
        headers[name] = entry.value as String;
      }
    }
  }
  final ext = selected['ext'];
  return {
    'url': selected['url'],
    'headers': headers,
    if ({'m4a', 'mp4'}.contains(ext))
      'mimeType': isMuxed ? 'video/mp4' : 'audio/mp4',
    if (ext == 'webm') 'mimeType': isMuxed ? 'video/webm' : 'audio/webm',
    if (isMuxed) 'audioOnlyPlayback': true,
    if (ext == 'mp3') 'mimeType': 'audio/mpeg',
    if (selected['abr'] is num) 'bitrateKbps': selected['abr'],
  };
}
