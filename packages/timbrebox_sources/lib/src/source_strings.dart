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
    'quality.publicDomain': '公有领域',
    'quality.publicStream': '公开流',
    'source.archive.badMetadata': 'Internet Archive 返回了无法识别的条目元数据。',
    'source.archive.badSearch': 'Internet Archive 返回了无法识别的目录结果。',
    'source.archive.expired': '条目文件信息已过期，请重新搜索。',
    'source.archive.noAudio': '该条目没有公开可播放的音频文件。',
    'source.archive.noFiles': 'Internet Archive 条目没有可识别的文件列表。',
    'source.audius.badChart': 'Audius 返回了无法识别的榜单结果。',
    'source.audius.badSearch': 'Audius 返回了无法识别的搜索结果。',
    'source.err.refMismatch': '音源引用与解析器不匹配。',
    'source.err.retiredFmt': 'TimbreBox 不再内置 {id}，可以安装插件来添加它，或者重新搜索这首歌。',
    'source.err.unregisteredFmt': '未注册音源：{id}',
    'source.errBadSearch': '音源返回了无法识别的搜索结果。',
    'source.errLoadMore': '加载更多失败，请稍后重试。',
    'source.errNetworkRetry': '网络不可用，请检查连接后重试。',
    'source.errRateLimited': '这个音源的请求太频繁了，请过一会儿再试。',
    'source.errRespTimeout': '音源响应超时，请稍后重试。',
    'source.errRespTooLarge': '音源响应过大，已停止读取。',
    'source.errUnavailableRetry': '音源暂时不可用，请稍后重试。',
    'source.openverse.badResponse': 'Openverse 返回了无法识别的结果。',
    'source.openverse.expired': '这首歌在 Openverse 上已经不能播放，请重新搜索。',
    'source.radio.badResponse': 'Radio Browser 返回了无法识别的目录结果。',
    'source.radio.expired': '电台流已经失效，请重新搜索。',
    'stream.err.backendReleased': '音频后端已经释放。',
  };

  static const _en = <String, String>{
    'net.blockedHost': 'Blocked for safety: {h} is a local or private address.',
    'net.blockedScheme': 'Blocked for safety: the {s} scheme is not allowed.',
    'quality.liveRadio': 'Live radio',
    'quality.publicAudio': 'Public audio',
    'quality.publicDomain': 'Public domain',
    'quality.publicStream': 'Public stream',
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
    'source.err.refMismatch':
        'The media reference does not match the resolver.',
    'source.err.retiredFmt':
        '{id} is no longer built in. Install a plugin to add it, or search for this track again.',
    'source.err.unregisteredFmt': 'Source not registered: {id}',
    'source.errBadSearch': 'The source returned unrecognized search results.',
    'source.errLoadMore': 'Failed to load more, try again later.',
    'source.errNetworkRetry':
        'Network unavailable — check your connection and retry.',
    'source.errRateLimited':
        'Too many requests to this source — try again in a while.',
    'source.errRespTimeout': 'The source response timed out, try again later.',
    'source.errRespTooLarge':
        'The source response is too large; stopped reading.',
    'source.errUnavailableRetry':
        'The source is temporarily unavailable, try again later.',
    'source.openverse.badResponse':
        'Openverse returned results it could not read.',
    'source.openverse.expired':
        'This track can no longer be played from Openverse — search again.',
    'source.radio.badResponse':
        'Radio Browser returned a directory response it could not read.',
    'source.radio.expired':
        'The station stream is no longer valid — search again.',
    'stream.err.backendReleased': 'The audio backend has been released.',
  };
}
