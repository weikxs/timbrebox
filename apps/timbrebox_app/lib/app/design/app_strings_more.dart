/// The second half of the [AppStrings] tables, kept in its own file so
/// neither grows past the size limit. Same keys in both languages.
library;

const moreZhStrings = <String, String>{
  // source, queue and control API errors
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
  // playback engine
  'stream.err.resolveTimeout': '获取播放地址超时，请重试。',
  'stream.err.notLoaded': '播放前必须先解析音频流。',
  'stream.err.engineReleased': '音频引擎已经释放。',
};

const moreEnStrings = <String, String>{
  // source, queue and control API errors
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
  // playback engine
  'stream.err.resolveTimeout': 'Getting the stream took too long — try again.',
  'stream.err.notLoaded': 'The audio stream must be resolved before playing.',
  'stream.err.engineReleased': 'The audio engine has been released.',
};
