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
  'plugin.src.videoAudioFmt': '视频音轨 · {p}',
  'plugin.skippedFmt': '有插件无法加载，已跳过：{ids}。文件可能已损坏，请从原链接重新安装。',
  'plugin.updatedSomeFailedFmt': '更新了 {n} 个插件；以下插件检查失败：{names}',
  'plugin.runtime.timeout': '插件脚本运行过久，已被终止。',
  'plugin.runtime.cancelled': '插件请求已取消。',
  'plugin.media.extractor_unconfigured': '尚未配置并校验桌面媒体解析工具。',
  'plugin.media.extractor_unsupported': '此媒体解析后端目前仅支持桌面端。',
  'plugin.media.extractor_unavailable': '无法访问已配置的媒体解析工具，请检查路径和沙箱权限。',
  'plugin.media.extractor_start_failed': '媒体解析工具无法启动，请检查依赖、签名和沙箱权限。',
  'plugin.media.extractor_integrity': '媒体解析工具校验失败，请检查构建配置。',
  'plugin.media.extractor_busy': '媒体解析繁忙，请稍后重试。',
  'plugin.media.extractor_timeout': '媒体解析超时，请重试。',
  'plugin.media.extractor_cancelled': '媒体解析已取消。',
  'plugin.media.extractor_disposed': '媒体解析服务已经关闭。',
  'plugin.media.extractor_output_limit': '媒体解析结果超过大小限制。',
  'plugin.media.extractor_failed': '暂时无法匿名解析此内容，请检查网络或来源状态。',
  'plugin.media.extractor_invalid_data': '来源返回了无效或不匹配的媒体信息。',
  'plugin.media.invalid_media_reference': '请提供所选平台支持的视频链接。',
  'plugin.media.invalid_media_request': '媒体请求的参数无效。',
  'plugin.media.platform_search_unavailable': '此构建尚未启用该平台的关键词搜索。',
  'plugin.media.guest_search_busy': '官方访客搜索繁忙，请稍后重试。',
  'plugin.media.guest_search_cancelled': '官方访客搜索已取消。',
  'plugin.media.guest_search_unavailable': '此平台或构建未提供官方访客搜索。',
  'plugin.media.guest_search_access_required': '官方访客页面未返回搜索结果，可能需要手动验证或登录。',
  'plugin.media.search_access_required': '官方搜索拒绝了请求，可能需要手动验证。',
  'plugin.media.guest_search_timeout': '官方访客搜索超时，请重试。',
  'plugin.media.guest_search_network_error': '官方访客搜索暂时无法连接。',
  'plugin.media.guest_search_failed': '官方访客搜索未能完成。',
  'plugin.media.guest_search_incomplete': '官方搜索未返回所需的下一页，请重试。',
  'plugin.media.search_request_mismatch': '搜索响应与当前关键词或分页不匹配。',
  'plugin.media.invalid_search_response': '官方搜索返回了无效的数据。',
  'plugin.media.search_limit_reached': '已达到本次搜索的结果上限。',
  'plugin.media.content_excluded': '已排除 VIP、付费、订阅专享或试听内容。',
  'plugin.media.content_unverified': '无法确认内容免费且非试听，已停止自动播放。',
  'plugin.media.media_unavailable': '此内容没有符合传输和资源限制的可用音轨。',
  'plugin.media.media_access_denied': '平台拒绝了当前匿名音频地址（HTTP 401/403），可重试或选择其他结果。',
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
  'stream.err.nativePlaybackFailed': '原生播放器无法打开或继续播放音频，请重试或切换来源。',
  'player.resolvingAudio': '正在解析播放地址…',
  'player.openingAudio': '解析完成，正在打开音频…',
  'player.cancelLoading': '取消加载',
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
  'plugin.src.videoAudioFmt': 'Video audio · {p}',
  'plugin.skippedFmt':
      'Some plugins could not be loaded and were skipped: {ids}. Their files '
      'may be damaged — reinstall them from their original link.',
  'plugin.updatedSomeFailedFmt':
      'Updated {n} plugin(s); these could not be checked: {names}',
  'plugin.runtime.timeout': 'The plugin script ran too long and was stopped.',
  'plugin.runtime.cancelled': 'The plugin request was cancelled.',
  'plugin.media.extractor_unconfigured':
      'The desktop media backend is not configured and pinned.',
  'plugin.media.extractor_unsupported':
      'This media backend currently supports desktop only.',
  'plugin.media.extractor_unavailable':
      'The configured media backend cannot be accessed; check its path and sandbox permissions.',
  'plugin.media.extractor_start_failed':
      'The media backend cannot start; check dependencies, signing and sandbox permissions.',
  'plugin.media.extractor_integrity':
      'The media backend checksum does not match this build.',
  'plugin.media.extractor_busy': 'Media extraction is busy; retry shortly.',
  'plugin.media.extractor_timeout': 'Media extraction timed out; retry.',
  'plugin.media.extractor_cancelled': 'Media extraction was cancelled.',
  'plugin.media.extractor_disposed': 'The media backend is closed.',
  'plugin.media.extractor_output_limit':
      'The media response exceeded its size limit.',
  'plugin.media.extractor_failed':
      'This content could not be resolved anonymously; check the network or source.',
  'plugin.media.extractor_invalid_data':
      'The source returned invalid or mismatched media data.',
  'plugin.media.invalid_media_reference':
      'Provide a supported video link for the selected platform.',
  'plugin.media.invalid_media_request':
      'The media request parameters are invalid.',
  'plugin.media.platform_search_unavailable':
      'Keyword search for this platform is not enabled in this build.',
  'plugin.media.guest_search_busy':
      'Official guest search is busy. Retry shortly.',
  'plugin.media.guest_search_cancelled': 'Official guest search was cancelled.',
  'plugin.media.guest_search_unavailable':
      'Official guest search is unavailable on this platform or build.',
  'plugin.media.guest_search_access_required':
      'The official guest page returned no search results. Manual verification or login may be required.',
  'plugin.media.search_access_required':
      'The official search request was refused. Manual verification may be required.',
  'plugin.media.guest_search_timeout':
      'Official guest search timed out. Retry.',
  'plugin.media.guest_search_network_error':
      'Official guest search could not connect.',
  'plugin.media.guest_search_failed': 'Official guest search did not complete.',
  'plugin.media.guest_search_incomplete':
      'Official search did not return the requested next page. Retry.',
  'plugin.media.search_request_mismatch':
      'The response does not match the current keyword or page.',
  'plugin.media.invalid_search_response':
      'Official search returned invalid data.',
  'plugin.media.search_limit_reached':
      'The result limit for this search was reached.',
  'plugin.media.content_excluded':
      'VIP, paid, subscriber-only or trial content was excluded.',
  'plugin.media.content_unverified':
      'Free, non-preview access could not be verified; playback was stopped.',
  'plugin.media.media_unavailable':
      'No audio track fits the supported transport and resource limits.',
  'plugin.media.media_access_denied':
      'The platform refused the anonymous audio URLs (HTTP 401/403). Retry or select another result.',
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
  'stream.err.nativePlaybackFailed':
      'The native player could not open or continue the audio. Retry or choose another source.',
  'player.resolvingAudio': 'Resolving the audio address…',
  'player.openingAudio': 'Resolved; opening audio…',
  'player.cancelLoading': 'Cancel loading',
  'stream.err.engineReleased': 'The audio engine has been released.',
};
