/// Texts of the messages the shared packages show: source errors, stream
/// quality labels and network refusals, in Simplified Chinese and English.
///
/// [english] selects the language; an app keeps it in step with its own
/// language setting. A key without an English text falls back to Chinese,
/// and an unknown key to itself. Strings with dynamic parts use a `{token}`
/// placeholder the caller replaces.
abstract final class SourceStrings {
  static bool english = false;

  static String t(String key) => lookup(key, english: english) ?? key;

  /// The text of [key] in the given language, or null when no shared package
  /// defines it.
  static String? lookup(String key, {required bool english}) =>
      (english ? _en[key] : null) ?? _zh[key];

  static const _zh = <String, String>{
    'net.blockedHost': '出于安全，禁止访问本机或内网地址：{h}',
    'net.blockedScheme': '出于安全，不允许使用该协议：{s}',
    'quality.liveRadio': '直播电台',
    'quality.publicAudio': '公开音频',
    'quality.publicStream': '公开流',
    'quality.youtubeAudio': 'YouTube 公开音频',
    'source.archive.badMetadata': 'Internet Archive 返回了无法识别的条目元数据。',
    'source.archive.badSearch': 'Internet Archive 返回了无法识别的目录结果。',
    'source.archive.expired': '条目文件信息已过期，请重新搜索。',
    'source.archive.noAudio': '该条目没有公开可播放的音频文件。',
    'source.archive.noFiles': 'Internet Archive 条目没有可识别的文件列表。',
    'source.audius.badChart': 'Audius 返回了无法识别的榜单结果。',
    'source.audius.badSearch': 'Audius 返回了无法识别的搜索结果。',
    'source.bilibili.noPart': 'Bilibili 未返回可播放分段。',
    'source.bilibili.noSecureStream': 'Bilibili 未返回安全音频流。',
    'source.err.refMismatch': '音源引用与解析器不匹配。',
    'source.err.unregisteredFmt': '未注册音源：{id}',
    'source.errBadSearch': '音源返回了无法识别的搜索结果。',
    'source.errLoadMore': '加载更多失败，请稍后重试。',
    'source.errNetwork': '网络不可用。',
    'source.errNetworkRetry': '网络不可用，请检查连接后重试。',
    'source.errRespTimeout': '音源响应超时，请稍后重试。',
    'source.errRespTooLarge': '音源响应过大，已停止读取。',
    'source.errTimeout': '来源响应超时。',
    'source.errTooLarge': '来源响应过大。',
    'source.errUnavailable': '来源暂时不可用（HTTP {code}）。',
    'source.errUnavailableRetry': '音源暂时不可用，请稍后重试。',
    'source.radio.badResponse': 'Radio Browser 返回了无法识别的目录结果。',
    'source.radio.expired': '电台流已经失效，请重新搜索。',
    'source.video.noResults': '该音源当前没有返回可播放的公开搜索结果。',
    'source.video.noStream': '该音源未返回可直接播放的公开音频流。',
    'source.youtube.noAudio': 'YouTube 未返回可播放的公开音频。',
    'source.youtube.noAudioStream': '该视频没有可播放的公开音频流。',
    'source.youtube.resolveTimeout': 'YouTube 解析超时，请稍后重试。',
    'source.youtube.searchTimeout': 'YouTube 搜索超时，请稍后重试。',
    'source.youtube.searchUnavailable': 'YouTube 搜索暂时不可用。',
    'stream.err.backendReleased': '音频后端已经释放。',
  };

  static const _en = <String, String>{
    'net.blockedHost': 'Blocked for safety: {h} is a local or private address.',
    'net.blockedScheme': 'Blocked for safety: the {s} scheme is not allowed.',
    'quality.liveRadio': 'Live radio',
    'quality.publicAudio': 'Public audio',
    'quality.publicStream': 'Public stream',
    'quality.youtubeAudio': 'YouTube public audio',
    'source.archive.badMetadata':
        'Internet Archive returned item metadata it could not read.',
    'source.archive.badSearch':
        'Internet Archive returned search results it could not read.',
    'source.archive.expired': 'The item file info has expired — search again.',
    'source.archive.noAudio': 'This item has no public playable audio file.',
    'source.archive.noFiles':
        'The Internet Archive item has no file list it could read.',
    'source.audius.badChart': 'Audius returned a chart it could not read.',
    'source.audius.badSearch':
        'Audius returned search results it could not read.',
    'source.bilibili.noPart': 'Bilibili returned no playable part.',
    'source.bilibili.noSecureStream':
        'Bilibili returned no secure audio stream.',
    'source.err.refMismatch':
        'The media reference does not match the resolver.',
    'source.err.unregisteredFmt': 'Source not registered: {id}',
    'source.errBadSearch': 'The source returned unrecognized search results.',
    'source.errLoadMore': 'Failed to load more, try again later.',
    'source.errNetwork': 'Network unavailable.',
    'source.errNetworkRetry':
        'Network unavailable — check your connection and retry.',
    'source.errRespTimeout': 'The source response timed out, try again later.',
    'source.errRespTooLarge':
        'The source response is too large; stopped reading.',
    'source.errTimeout': 'The source response timed out.',
    'source.errTooLarge': 'The source response is too large.',
    'source.errUnavailable':
        'The source is temporarily unavailable (HTTP {code}).',
    'source.errUnavailableRetry':
        'The source is temporarily unavailable, try again later.',
    'source.radio.badResponse':
        'Radio Browser returned a directory response it could not read.',
    'source.radio.expired':
        'The station stream is no longer valid — search again.',
    'source.video.noResults':
        'This source returned no playable public search results.',
    'source.video.noStream':
        'This source returned no directly playable public audio stream.',
    'source.youtube.noAudio': 'YouTube returned no playable public audio.',
    'source.youtube.noAudioStream':
        'This video has no playable public audio stream.',
    'source.youtube.resolveTimeout':
        'Resolving the YouTube stream timed out — try again later.',
    'source.youtube.searchTimeout':
        'YouTube search timed out — try again later.',
    'source.youtube.searchUnavailable':
        'YouTube search is temporarily unavailable.',
    'stream.err.backendReleased': 'The audio backend has been released.',
  };
}
