/// The second half of the [AppStrings] tables, kept in its own file so
/// neither grows past the size limit. Same keys in both languages.
library;

const moreZhStrings = <String, String>{
  // source, queue and control API errors
  'source.err.unregisteredFmt': '未注册音源：{id}',
  'source.audius.badSearch': 'Audius 返回了无法识别的搜索结果。',
  'source.audius.badChart': 'Audius 返回了无法识别的榜单结果。',
  'source.err.refMismatch': '音源引用与解析器不匹配。',
  'source.radio.expired': '电台流已经失效，请重新搜索。',
  'source.archive.badSearch': 'Internet Archive 返回了无法识别的目录结果。',
  'source.archive.expired': '条目文件信息已过期，请重新搜索。',
  'source.archive.badMetadata': 'Internet Archive 返回了无法识别的条目元数据。',
  'source.archive.noFiles': 'Internet Archive 条目没有可识别的文件列表。',
  'source.archive.noAudio': '该条目没有公开可播放的音频文件。',
  'source.youtube.searchTimeout': 'YouTube 搜索超时，请稍后重试。',
  'source.youtube.searchUnavailable': 'YouTube 搜索暂时不可用。',
  'quality.youtubeAudio': 'YouTube 公开音频',
  'source.youtube.resolveTimeout': 'YouTube 解析超时，请稍后重试。',
  'source.youtube.noAudio': 'YouTube 未返回可播放的公开音频。',
  'source.youtube.noAudioStream': '该视频没有可播放的公开音频流。',
  'source.bilibili.noPart': 'Bilibili 未返回可播放分段。',
  'source.bilibili.noSecureStream': 'Bilibili 未返回安全音频流。',
  'source.video.noResults': '该音源当前没有返回可播放的公开搜索结果。',
  'source.video.noStream': '该音源未返回可直接播放的公开音频流。',
  'queue.err.unavailable': '队列项目已不可用。',
  'control.err.badIndex': 'i 参数无效',
  'control.err.indexRange': '队列索引超范围',
  'control.err.missingSource': '缺少 id/enabled 参数',
  'control.err.badMs': 'ms 参数无效',
  'control.err.badLevel': 'level 参数无效',
  'control.err.emptyQuery': 'q 参数为空',
  'control.err.missingRef': '缺少 source/item 参数',
  'control.err.unknownTrack': '未找到该曲目，请先 /search',
  'control.err.badLoopFmt': 'loop 需为 {modes}',
  'plugin.js.moduleNotLoaded': '插件模块未加载：',
  'plugin.js.moduleNotAllowed': '插件请求了不允许的模块：',
  // storage
  'storage.writeFailed': '有设置或曲库数据没能保存（磁盘已满或没有写入权限？）。',
  // hot library
  'hot.pluginChartsFailedFmt': '这些插件的榜单没能加载：{names}',
  // player
  'player.searchAgain': '重新搜索',
  'player.lyricsUnsynced': '这份歌词没有时间轴，无法跟随播放。',
  // agent control
  'agent.startFailed': '控制接口未能启动（无法安全写入令牌文件或没有可用端口）。',
  // plugins
  'plugin.skippedFmt': '有插件无法加载，已跳过：{ids}。文件可能已损坏，请从原链接重新安装。',
  'plugin.updatedSomeFailedFmt': '更新了 {n} 个插件；以下插件检查失败：{names}',
  'plugin.runtime.timeout': '插件脚本运行过久，已被终止。',
  // downloads
  'download.errStalled': '下载中断：音源长时间没有传来数据。',
  'download.errDisk': '无法写入下载目录，请检查磁盘空间和权限。',
  'download.errNetwork': '网络连接中断，请稍后重试。',
  'download.cancel': '取消下载',
  'download.progressFmt': '正在下载… {p}%',
  // sources
  'source.radio.badResponse': 'Radio Browser 返回了无法识别的目录结果。',
  // playback engine
  'stream.err.resolveTimeout': '获取播放地址超时，请重试。',
  'stream.err.notLoaded': '播放前必须先解析音频流。',
  'stream.err.engineReleased': '音频引擎已经释放。',
  'stream.err.backendReleased': '音频后端已经释放。',
};

const moreEnStrings = <String, String>{
  // source, queue and control API errors
  'source.err.unregisteredFmt': 'Source not registered: {id}',
  'source.audius.badSearch':
      'Audius returned search results it could not read.',
  'source.audius.badChart': 'Audius returned a chart it could not read.',
  'source.err.refMismatch': 'The media reference does not match the resolver.',
  'source.radio.expired':
      'The station stream is no longer valid — search again.',
  'source.archive.badSearch':
      'Internet Archive returned search results it could not read.',
  'source.archive.expired': 'The item file info has expired — search again.',
  'source.archive.badMetadata':
      'Internet Archive returned item metadata it could not read.',
  'source.archive.noFiles':
      'The Internet Archive item has no file list it could read.',
  'source.archive.noAudio': 'This item has no public playable audio file.',
  'source.youtube.searchTimeout': 'YouTube search timed out — try again later.',
  'source.youtube.searchUnavailable':
      'YouTube search is temporarily unavailable.',
  'quality.youtubeAudio': 'YouTube public audio',
  'source.youtube.resolveTimeout':
      'Resolving the YouTube stream timed out — try again later.',
  'source.youtube.noAudio': 'YouTube returned no playable public audio.',
  'source.youtube.noAudioStream':
      'This video has no playable public audio stream.',
  'source.bilibili.noPart': 'Bilibili returned no playable part.',
  'source.bilibili.noSecureStream': 'Bilibili returned no secure audio stream.',
  'source.video.noResults':
      'This source returned no playable public search results.',
  'source.video.noStream':
      'This source returned no directly playable public audio stream.',
  'queue.err.unavailable': 'This queue item is no longer available.',
  'control.err.badIndex': 'Invalid i parameter',
  'control.err.indexRange': 'Queue index out of range',
  'control.err.missingSource': 'Missing id/enabled parameter',
  'control.err.badMs': 'Invalid ms parameter',
  'control.err.badLevel': 'Invalid level parameter',
  'control.err.emptyQuery': 'The q parameter is empty',
  'control.err.missingRef': 'Missing source/item parameter',
  'control.err.unknownTrack': 'Track not found — call /search first',
  'control.err.badLoopFmt': 'loop must be one of {modes}',
  'plugin.js.moduleNotLoaded': 'Plugin module not loaded: ',
  'plugin.js.moduleNotAllowed':
      'The plugin asked for a module that is not allowed: ',
  // hot library
  'hot.pluginChartsFailedFmt':
      'Charts from these plugins did not load: {names}',
  // storage
  'storage.writeFailed':
      'Some settings or library data could not be saved (is the disk full, '
      'or is writing not allowed?).',
  // player
  'player.searchAgain': 'Search again',
  'player.lyricsUnsynced':
      'These lyrics have no timings, so they cannot follow playback.',
  // agent control
  'agent.startFailed':
      'The control interface did not start (the token file could not be '
      'written privately, or no port was free).',
  // plugins
  'plugin.skippedFmt':
      'Some plugins could not be loaded and were skipped: {ids}. Their files '
      'may be damaged — reinstall them from their original link.',
  'plugin.updatedSomeFailedFmt':
      'Updated {n} plugin(s); these could not be checked: {names}',
  'plugin.runtime.timeout': 'The plugin script ran too long and was stopped.',
  // downloads
  'download.errStalled':
      'Download stopped: the source sent nothing for too long.',
  'download.errDisk':
      'Could not write to the download folder — check disk space and permissions.',
  'download.errNetwork': 'The network connection dropped — try again later.',
  'download.cancel': 'Cancel download',
  'download.progressFmt': 'Downloading… {p}%',
  // sources
  'source.radio.badResponse':
      'Radio Browser returned a directory response it could not read.',
  // playback engine
  'stream.err.resolveTimeout': 'Getting the stream took too long — try again.',
  'stream.err.notLoaded': 'The audio stream must be resolved before playing.',
  'stream.err.engineReleased': 'The audio engine has been released.',
  'stream.err.backendReleased': 'The audio backend has been released.',
};
