import 'package:timbrebox_sources/timbrebox_sources.dart';

import 'app_strings_more.dart';

/// Lightweight app-wide localization. `AppStrings.lang` is a global (like the
/// active palette) set from the language preference; widgets read `AppStrings.t`
/// at build time so switching language re-renders. Keys are dotted namespaces;
/// strings with dynamic parts use a `{token}` placeholder the caller replaces.
///
/// The texts of the shared packages (source errors, stream qualities) live in
/// their `SourceStrings`; setting [lang] keeps those in the same language and
/// [t] finds their keys too.
enum AppLang { zh, en }

abstract final class AppStrings {
  static AppLang _lang = AppLang.zh;

  static AppLang get lang => _lang;

  static set lang(AppLang value) {
    _lang = value;
    SourceStrings.english = value == AppLang.en;
  }

  static AppLang fromName(String name) =>
      name.toLowerCase().contains('english') || name.toLowerCase() == 'en'
      ? AppLang.en
      : AppLang.zh;

  static String t(String key) {
    final english = lang == AppLang.en;
    return (english ? _en[key] ?? moreEnStrings[key] : null) ??
        _zh[key] ??
        moreZhStrings[key] ??
        SourceStrings.lookup(key, english: english) ??
        key;
  }

  static const _zh = <String, String>{
    // navigation / chrome
    'nav.home': '首页',
    'nav.search': '搜索',
    'nav.hot': '热门库',
    'nav.myMusic': '我的音乐',
    'nav.localMusic': '本地音乐',
    'nav.recent': '最近播放',
    'nav.settings': '设置',
    'nav.libraryStatsFmt': '{f} 首收藏 · {d} 首本地',
    'nav.browse': '浏览',
    'nav.yourSpace': '你的空间',
    'nav.localLibrary': '本地曲库',
    'kicker.trending': '正在流行',
    'kicker.library': '我的曲库',
    'kicker.offline': '离线收听',
    'kicker.upNext': '接下来',
    'kicker.settings': '偏好设置',
    'top.yourSpace': '你的空间',
    'top.searchHint': '搜索音乐、艺人或歌单',
    'top.switchPage': '切换页面',
    // settings tabs
    'settings.general': '常规',
    'settings.appearance': '主题',
    'settings.sources': '音源',
    'settings.plugins': '插件',
    'settings.downloads': '下载',

    // shared
    'common.back': '返回',
    'common.retry': '重试',
    'common.cancel': '取消',
    'common.clear': '清空',
    'common.copy': '复制',
    'common.close': '关闭',
    'common.favorite': '收藏',
    'common.unfavorite': '取消收藏',
    'count.tracksFmt': '{n} 首',

    // hot library
    'hot.plugin': '插件',
    'hot.subtitle': '选一个曲风或电台，进入它的列表',
    'hot.genresGroup': '曲风 · Audius',
    'hot.radioGroup': '中文电台 · Radio Browser',
    'hot.radio.cn': '中国大陆',
    'hot.radio.tw': '台湾',
    'hot.radio.hk': '香港',
    'hot.radio.world': '全球热门',
    'hot.pluginCharts': '插件榜单',
    'hot.publicTrending': '公开热门',
    'hot.loadingPlaylist': '正在加载歌单…',
    'hot.emptyCategory': '这个分类暂时没有内容。',
    'hot.cat.jazz': '爵士',
    'hot.cat.electronic': '电子',
    'hot.cat.hiphop': '嘻哈',
    'hot.cat.pop': '流行',
    'hot.cat.rock': '摇滚',
    'hot.cat.classical': '古典',
    'hot.cat.ambient': '氛围',
    'hot.cat.soul': '灵魂',

    // library / queue
    'library.favoritesDetail': '收藏与自建歌单已本地持久化，重启后保留。',
    'library.playAll': '全部播放',
    'library.shuffle': '随机播放',
    'library.playlists': '歌单',
    'library.newPlaylist': '新建歌单',
    'library.playlistsEmpty': '还没有歌单，点“新建歌单”，或在任意歌曲上点“加入歌单”。',
    'library.playlistNameHint': '歌单名称',
    'library.playlistCountFmt': '{n} 首',
    'library.addToPlaylist': '加入歌单',
    'library.removeFromPlaylist': '从歌单移除',
    'library.renamePlaylist': '重命名',
    'common.confirm': '确认',
    'common.delete': '删除',
    'common.play': '播放',
    'library.emptyFavoritesTitle': '还没有收藏',
    'library.emptyFavoritesDetail': '点击歌曲右侧的心形按钮，把它留在这里。',
    'library.localDetail': '已下载的音频保存在本机，重启后仍从本地文件直接播放，不再请求音源。',
    'library.emptyLocalTitle': '还没有本地音乐',
    'library.emptyLocalDetail': '在任一歌曲右侧点击下载图标，完成后会出现在这里并可离线播放。',
    'queue.title': '播放队列',
    'queue.detail': '队列是当前会话状态；切歌、插播与移除立即反映到迷你播放器。',
    'queue.clear': '清空列表',
    'queue.countPrefix': '共 ',
    'queue.countSuffix': ' 首',
    'queue.empty': '队列是空的，去搜索或热门库添加音乐吧。',
    'queue.remove': '移出队列',

    // player / hero / mini-player
    'player.playAll': '全部播放',
    'player.listening': '正在聆听',
    'player.nowPlaying': '正在播放',
    'player.pickTrack': '选择一首音乐',
    'player.searchPublic': '搜索公开音乐',
    'player.noSource': '未选择音源',
    'player.resolvingStream': '正在解析公开音频流…',
    'player.readyToListen': '准备好开始聆听。',
    'player.previous': '上一首',
    'player.next': '下一首',
    'player.play': '播放',
    'player.pause': '暂停',
    'player.resolving': '解析中',
    'player.lyrics': '歌词',
    'player.favoriteThis': '收藏此曲',
    'player.upNext': '接下来',
    'player.reorderQueue': '拖动重排队列',
    'player.saveQueue': '把队列存为歌单',
    'player.queueSaved': '已把当前队列存为歌单',
    'player.searchMusic': '搜索音乐',
    'player.inQueueFmt': '{n} 首在当前队列',
    'player.noLyrics': '该曲目暂无歌词。',
    'player.noTrackSelected': '尚未选择音乐',
    'player.chooseFromSearch': '从搜索目录中选择',
    'player.playbackMode': '播放模式：',

    // search
    'search.noSourcesTitle': '没有可用的搜索来源',
    'search.noSourcesDetail': '请在设置中启用至少一个内置音源。',
    'search.sourceLabel': '音乐来源',
    'search.startTitle': '从一个来源开始',
    'search.recent': '最近搜索',
    'search.clearRecent': '清空',
    'search.noSources': '没有启用可搜索的音源。',
    'search.unavailable': '搜索暂时不可用，请稍后重试。',
    'category.empty': '暂时没有内容，请稍后重试。',
    'category.loadFailed': '加载失败，请稍后重试。',
    'theme.light': '浅色',
    'theme.dark': '深色',
    'theme.system': '跟随系统',
    'theme.black': '纯黑',
    'plugin.err.emptySubscription': '订阅里没有可安装的插件。',
    'plugin.err.subscriptionAllFailed': '订阅内插件全部安装失败：{e}',
    'plugin.err.scriptLoad': '插件脚本无法加载：{e}',
    'plugin.err.missingPlatform': '这不是有效的插件（缺少 platform 字段）。',
    'plugin.err.missingSearch': '插件缺少 search 功能，无法作为音源。',
    'plugin.err.invalidUrl': '请输入有效的 https 地址。',
    'plugin.err.downloadHttp': '下载失败：HTTP {code}',
    'plugin.err.tooLarge': '插件文件过大。',
    'plugin.err.network': '网络不可用，请检查连接后重试。',
    'plugin.err.timeout': '下载超时，请稍后重试。',
    'plugin.http.invalidUrl': '插件请求的地址无效。',
    'plugin.http.redirectMissing': '插件请求重定向缺少目标地址。',
    'plugin.http.tooManyRedirects': '插件请求的重定向次数过多。',
    'plugin.http.tooLarge': '插件响应超过大小上限。',
    'plugin.http.timeoutFmt': '插件请求超过 {ms} 毫秒未完成。',
    'plugin.src.searchFailed': '插件搜索失败：{e}',
    'plugin.src.refMismatch': '音源引用与解析器不匹配。',
    'plugin.src.expired': '曲目信息已过期，请重新搜索。',
    'plugin.src.resolveFailed': '插件解析播放地址失败：{e}',
    'plugin.src.noUrl': '插件未返回可播放的地址。',
    'plugin.src.disposed': '插件已移除或已更新。',
    'plugin.src.qualityFmt': '插件 · {p}',
    'plugin.runtime.execFailed': '插件执行失败',
    'stream.err.badLocalPath': '本地音频路径无法识别。',
    'stream.err.noSecureStream': '此来源没有提供安全的可播放音频流。',
    'download.errHttp': '下载源返回 HTTP {code}。',
    'download.errTooLarge': '下载文件超过大小限制。',
    'download.errScheme': '该音源不支持下载。',
    'quality.localFile': '本地文件',
    'plugin.err.unsupportedPlatform': '当前平台不支持插件。',
    'search.sourceDisabled': '音源未启用',
    'search.searchingFmt': '{name} 正在搜索…',
    'search.fromFmt': '来自 {name}',
    'search.errorTitle': '暂时无法搜索',
    'search.pickSourceTitle': '选择可用音源',
    'search.pickSourceDetail': '启用音源后，结果会按来源分别出现。',
    'search.readyTitle': '准备搜索',
    'search.readyDetailFmt': '输入关键词，{name} 的结果会独立呈现。',
    'search.sourceUnavailableFmt': '{name} 暂时不可用',
    'search.noMatchFmt': '{name} 没有找到匹配内容',
    'search.noMatchDetail': '换一个关键词，或切换到其他来源继续搜索。',
    'search.allLoaded': '已加载全部结果',
    'search.loadMore': '加载更多',

    // tracks
    'track.emptyTitle': '这里还没有音乐',
    'track.emptyDetail': '从搜索或首页把喜欢的声音加入这里。',
    'track.resolvingFmt': '正在解析 {name}',
    'track.playFmt': '播放 {name}',
    'track.resolving': '正在解析',
    'track.playNext': '下一首播放',

    // downloads
    'download.downloading': '下载中',
    'download.inProgress': '正在下载…',
    'download.failed': '下载失败',
    'download.remove': '移除下载',
    'download.toLocal': '下载到本地',
    'download.settingsTitle': '下载与本地音乐',
    'download.settingsDetail': '下载的音频保存在下面的目录，重启后从本地文件直接播放，不再请求音源。',
    'download.resolving': '正在解析…',
    'download.downloaded': '已下载',
    'download.clearLocal': '清空本地音乐',
    'download.clearConfirm': '将删除所有已下载的本地音频文件，此操作不可撤销。',
    'download.saveDir': '保存目录',
    'download.copyPath': '复制路径',
    'download.pathCopied': '已复制目录路径',
    'download.openInFileManager': '在文件管理器中打开',

    // plugins
    'plugin.title': '音源插件',
    'plugin.detail': '第三方插件是社区脚本，安装后可搜索/播放其提供的音源。仅安装你信任的来源。',
    'plugin.unsupported':
        '这个系统上不能运行插件。插件可在 Windows、macOS、Linux、iOS 和 Android 上使用。',
    'plugin.urlHint': '粘贴插件 .js 原始链接，或订阅 JSON 地址',
    'plugin.installing': '安装中…',
    'plugin.install': '安装',
    'plugin.checking': '检查中…',
    'plugin.checkUpdates': '检查更新',
    'plugin.installed': '已安装',
    'plugin.none': '还没有安装任何插件。',
    'plugin.uninstall': '卸载',
    'plugin.installedCountFmt': '已安装 {n} 个插件',
    'plugin.installFailedFmt': '安装失败：{e}',
    'plugin.updatedCountFmt': '更新了 {n} 个插件',
    'plugin.upToDate': '插件已是最新',
    'plugin.updateFailedFmt': '检查更新失败：{e}',
    'plugin.updateFailureFmt': '{name}（{reason}）',
    'plugin.err.updateUnexpected': '更新时出现意外错误，原版本保持不变',
    'plugin.confirmTitle': '安装第三方插件',
    'plugin.confirmBody': '插件是社区提供的脚本，会以你的名义发起网络请求来搜索和获取音频。请仅安装你信任的来源。',
    'plugin.confirmInstall': '我信任，安装',

    // settings bodies
    'settings.detail.general': '语言、播放、外观与隐私等常规偏好。',
    'settings.detail.appearance': '更换主题皮肤：上传一张图片作为背景。',
    'settings.detail.sources': '开箱即用的内置来源，可按需停用。',
    'settings.detail.plugins': '粘贴 GitHub 地址安装第三方音源插件。',
    'settings.detail.downloads': '查看本地音乐的保存目录，打开或清理下载。',
    'settings.shortcuts': '快捷键',
    'settings.detail.shortcuts': '查看并自定义桌面播放快捷键。',
    'settings.shortcutsHint': '点右侧按键，然后按下组合键（如 ⌘ / Ctrl + 键）；Esc 取消。',
    'settings.shortcutDesktopOnly': '键盘快捷键仅在桌面端（Windows / macOS / Linux）可用。',
    'settings.shortcutReset': '恢复默认',
    'settings.shortcutPress': '按下组合键…',
    'shortcut.playPause': '播放 / 暂停',
    'shortcut.seekForward': '快进 5 秒',
    'shortcut.seekBackward': '快退 5 秒',
    'shortcut.volumeUp': '音量 +5%',
    'shortcut.volumeDown': '音量 −5%',
    'shortcut.nextTrack': '下一首',
    'shortcut.previousTrack': '上一首',
    'settings.appearanceDetail': '选择一个内置主题，或上传一张图片作为自定义背景。',
    'settings.custom': '自定义',
    'settings.changeBg': '更换背景图片',
    'settings.uploadBg': '上传背景图片',
    'settings.usingCustomBg': '正在使用自定义背景',
    'settings.bgApplied': '已应用自定义背景',
    'settings.bgReadFailed': '无法读取所选图片，请重试。',
    'settings.language': '界面语言',
    'settings.restoreSession': '启动后恢复上次会话',
    'settings.playback': '播放',
    'settings.volume': '音量',
    'settings.loopMode': '循环方式',
    'settings.defaultQuality': '默认音质：',
    'settings.releaseAfterPause': '暂停后释放播放资源',
    'settings.playbackSpeed': '播放速度',
    'settings.speedNormal': '正常',
    'settings.sleepTimer': '睡眠定时',
    'settings.sleepOff': '关闭',
    'settings.minutesFmt': '{m} 分钟',
    'settings.appearancePrivacy': '外观与隐私',
    'settings.reducedEffects': '减少视觉效果',
    'settings.noGpuEffects': '未检测到 GPU，已默认关闭动效与毛玻璃以节省 CPU。',
    'settings.diagnosticLogging': '本地诊断日志',
    'settings.diagnosticSubtitle': '默认关闭；仅用于导出本地排障信息。',
    'settings.viewDiagnostics': '查看诊断日志',
    'settings.agentControl': 'Agent 控制',
    'settings.diagnosticsTitle': '诊断日志',
    'settings.noLogs': '暂无日志。',
    'settings.builtinSources': '内置音源',
    'settings.sourcesDetail': '停用的来源不会参与后续搜索与发现。',

    // agent control
    'agent.localInterface': '本机控制接口',
    'agent.interfaceSubtitle':
        '默认开启：在本机（仅回环）开放 HTTP 接口，供本地 agent/脚本控制播放器。每个请求都要带上本次运行的令牌（只有你的账户能读取的令牌文件）。',
    'agent.starting': '正在启动…',
    'agent.address': '地址',
    'agent.token': '令牌',
    'agent.exampleLabel': '示例：',
    'agent.endpointsLabel': '端点：',
    'agent.copiedUrl': '已复制示例地址',

    // source descriptions
    'source.audiusDetail': '公开点播音乐 · HTTPS · 无账户',
    'source.openverseDetail':
        '开放授权音乐（Jamendo、Freesound、维基共享资源、ccMixter）· HTTPS · 无账户',
    'source.radioDetail': '公开电台目录与直播 · HTTP(S) · 无账户',
    'source.builtinDetail': '内置来源',

    // loop modes
    'loop.queue': '列表循环',
    'loop.track': '单曲循环',
    'loop.off': '顺序播放',
    'loop.shuffle': '随机播放',

    // quality presets
    'quality.standard': '标准',
    'quality.high': '高品质',
    'quality.lossless': '无损',
    'quality.hires': 'Hi-Res',
  };

  static const _en = <String, String>{
    // navigation / chrome
    'nav.home': 'Home',
    'nav.search': 'Search',
    'nav.hot': 'Charts',
    'nav.myMusic': 'My Music',
    'nav.localMusic': 'Local',
    'nav.recent': 'Recent',
    'nav.settings': 'Settings',
    'nav.libraryStatsFmt': '{f} saved · {d} local',
    'nav.browse': 'BROWSE',
    'nav.yourSpace': 'YOUR SPACE',
    'nav.localLibrary': 'LOCAL LIBRARY',
    'kicker.trending': 'TRENDING',
    'kicker.library': 'YOUR LIBRARY',
    'kicker.offline': 'OFFLINE',
    'kicker.upNext': 'UP NEXT',
    'kicker.settings': 'SETTINGS',
    'top.yourSpace': 'Your Space',
    'top.searchHint': 'Search songs, artists or playlists',
    'top.switchPage': 'Switch page',
    // settings tabs
    'settings.general': 'General',
    'settings.appearance': 'Theme',
    'settings.sources': 'Sources',
    'settings.plugins': 'Plugins',
    'settings.downloads': 'Downloads',

    // shared
    'common.back': 'Back',
    'common.retry': 'Retry',
    'common.cancel': 'Cancel',
    'common.clear': 'Clear',
    'common.copy': 'Copy',
    'common.close': 'Close',
    'common.favorite': 'Favorite',
    'common.unfavorite': 'Unfavorite',
    'count.tracksFmt': '{n} tracks',

    // hot library
    'hot.plugin': 'Plugin',
    'hot.subtitle': 'Pick a genre or a radio region to open its list',
    'hot.genresGroup': 'Genres · Audius',
    'hot.radioGroup': 'Chinese radio · Radio Browser',
    'hot.radio.cn': 'Mainland China',
    'hot.radio.tw': 'Taiwan',
    'hot.radio.hk': 'Hong Kong',
    'hot.radio.world': 'Top worldwide',
    'hot.pluginCharts': 'Plugin charts',
    'hot.publicTrending': 'Public trending',
    'hot.loadingPlaylist': 'Loading playlist…',
    'hot.emptyCategory': 'Nothing here yet in this category.',
    'hot.cat.jazz': 'Jazz',
    'hot.cat.electronic': 'Electronic',
    'hot.cat.hiphop': 'Hip-Hop',
    'hot.cat.pop': 'Pop',
    'hot.cat.rock': 'Rock',
    'hot.cat.classical': 'Classical',
    'hot.cat.ambient': 'Ambient',
    'hot.cat.soul': 'Soul',

    // library / queue
    'library.favoritesDetail':
        'Favorites and playlists are stored locally and kept across restarts.',
    'library.playAll': 'Play all',
    'library.shuffle': 'Shuffle',
    'library.playlists': 'Playlists',
    'library.newPlaylist': 'New playlist',
    'library.playlistsEmpty':
        'No playlists yet — tap “New playlist”, or “Add to playlist” on any track.',
    'library.playlistNameHint': 'Playlist name',
    'library.playlistCountFmt': '{n} tracks',
    'library.addToPlaylist': 'Add to playlist',
    'library.removeFromPlaylist': 'Remove from playlist',
    'library.renamePlaylist': 'Rename',
    'common.confirm': 'Confirm',
    'common.delete': 'Delete',
    'common.play': 'Play',
    'library.emptyFavoritesTitle': 'No favorites yet',
    'library.emptyFavoritesDetail':
        'Tap the heart on any track to keep it here.',
    'library.localDetail':
        'Downloaded audio is stored on this device and plays straight from local files after a restart — no source request.',
    'library.emptyLocalTitle': 'No local music yet',
    'library.emptyLocalDetail':
        'Tap the download icon on any track; once finished it appears here and plays offline.',
    'queue.title': 'Play queue',
    'queue.detail':
        'The queue is current-session state; skips, insertions and removals update the mini player instantly.',
    'queue.clear': 'Clear',
    'queue.countPrefix': '',
    'queue.countSuffix': ' tracks',
    'queue.empty': 'The queue is empty — add music from Search or Charts.',
    'queue.remove': 'Remove from queue',

    // player / hero / mini-player
    'player.playAll': 'Play all',
    'player.listening': 'Listening',
    'player.nowPlaying': 'Now playing',
    'player.pickTrack': 'Pick a track',
    'player.searchPublic': 'Search public music',
    'player.noSource': 'No source selected',
    'player.resolvingStream': 'Resolving public audio stream…',
    'player.readyToListen': 'Ready to start listening.',
    'player.previous': 'Previous',
    'player.next': 'Next',
    'player.play': 'Play',
    'player.pause': 'Pause',
    'player.resolving': 'Resolving',
    'player.lyrics': 'Lyrics',
    'player.favoriteThis': 'Save to favorites',
    'player.upNext': 'Up next',
    'player.reorderQueue': 'Drag to reorder the queue',
    'player.saveQueue': 'Save queue as a playlist',
    'player.queueSaved': 'Saved the current queue as a playlist',
    'player.searchMusic': 'Search music',
    'player.inQueueFmt': '{n} in this queue',
    'player.noLyrics': 'No lyrics for this track.',
    'player.noTrackSelected': 'No track selected',
    'player.chooseFromSearch': 'Choose from search',
    'player.playbackMode': 'Playback mode: ',

    // search
    'search.noSourcesTitle': 'No search sources available',
    'search.noSourcesDetail':
        'Enable at least one built-in source in Settings.',
    'search.sourceLabel': 'Music sources',
    'search.startTitle': 'Start from a source',
    'search.recent': 'Recent searches',
    'search.clearRecent': 'Clear',
    'search.noSources': 'No searchable source is enabled.',
    'search.unavailable': 'Search is temporarily unavailable, try again later.',
    'category.empty': 'Nothing here yet, try again later.',
    'category.loadFailed': 'Failed to load, try again later.',
    'theme.light': 'Light',
    'theme.dark': 'Dark',
    'theme.system': 'System',
    'theme.black': 'Black',
    'plugin.err.emptySubscription':
        'The subscription has no installable plugins.',
    'plugin.err.subscriptionAllFailed':
        'All plugins in the subscription failed to install: {e}',
    'plugin.err.scriptLoad': 'The plugin script failed to load: {e}',
    'plugin.err.missingPlatform':
        'Not a valid plugin (missing the platform field).',
    'plugin.err.missingSearch':
        'The plugin has no search capability and cannot be a source.',
    'plugin.err.invalidUrl': 'Enter a valid https URL.',
    'plugin.err.downloadHttp': 'Download failed: HTTP {code}',
    'plugin.err.tooLarge': 'The plugin file is too large.',
    'plugin.err.network':
        'Network unavailable — check your connection and retry.',
    'plugin.err.timeout': 'Download timed out, try again later.',
    'plugin.http.invalidUrl': 'The plugin requested an invalid URL.',
    'plugin.http.redirectMissing':
        'The plugin request redirect is missing a target.',
    'plugin.http.tooManyRedirects':
        'The plugin request was redirected too many times.',
    'plugin.http.tooLarge': 'The plugin response exceeds the size limit.',
    'plugin.http.timeoutFmt':
        'The plugin request did not finish within {ms} ms.',
    'plugin.src.searchFailed': 'Plugin search failed: {e}',
    'plugin.src.refMismatch':
        'The media reference does not match the resolver.',
    'plugin.src.expired': 'Track info expired — search again.',
    'plugin.src.resolveFailed':
        'The plugin failed to resolve a playback URL: {e}',
    'plugin.src.noUrl': 'The plugin returned no playable URL.',
    'plugin.src.disposed': 'The plugin was removed or updated.',
    'plugin.src.qualityFmt': 'Plugin · {p}',
    'plugin.runtime.execFailed': 'Plugin execution failed',
    'stream.err.badLocalPath': 'The local audio path is unrecognized.',
    'stream.err.noSecureStream':
        'This source did not provide a secure, playable stream.',
    'download.errHttp': 'The download source returned HTTP {code}.',
    'download.errTooLarge': 'The download exceeds the size limit.',
    'download.errScheme': 'This source cannot be downloaded.',
    'quality.localFile': 'Local file',
    'plugin.err.unsupportedPlatform':
        'Plugins are not supported on this platform.',
    'search.sourceDisabled': 'Source not enabled',
    'search.searchingFmt': 'Searching {name}…',
    'search.fromFmt': 'From {name}',
    'search.errorTitle': 'Search is unavailable',
    'search.pickSourceTitle': 'Pick an available source',
    'search.pickSourceDetail':
        'Once sources are enabled, results appear per source.',
    'search.readyTitle': 'Ready to search',
    'search.readyDetailFmt':
        'Enter a keyword — {name} results appear on their own.',
    'search.sourceUnavailableFmt': '{name} is unavailable',
    'search.noMatchFmt': 'No matches on {name}',
    'search.noMatchDetail':
        'Try another keyword, or switch to a different source.',
    'search.allLoaded': 'All results loaded',
    'search.loadMore': 'Load more',

    // tracks
    'track.emptyTitle': 'No music here yet',
    'track.emptyDetail': 'Add sounds you like from Search or the home page.',
    'track.resolvingFmt': 'Resolving {name}',
    'track.playFmt': 'Play {name}',
    'track.resolving': 'Resolving',
    'track.playNext': 'Play next',

    // downloads
    'download.downloading': 'Downloading',
    'download.inProgress': 'Downloading…',
    'download.failed': 'Download failed',
    'download.remove': 'Remove download',
    'download.toLocal': 'Download',
    'download.settingsTitle': 'Downloads & local music',
    'download.settingsDetail':
        'Downloaded audio is stored in the folder below and plays straight from local files after a restart — no source request.',
    'download.resolving': 'Resolving…',
    'download.downloaded': 'Downloaded',
    'download.clearLocal': 'Clear local music',
    'download.clearConfirm':
        'This deletes all downloaded local audio files and cannot be undone.',
    'download.saveDir': 'Save folder',
    'download.copyPath': 'Copy path',
    'download.pathCopied': 'Folder path copied',
    'download.openInFileManager': 'Open in file manager',

    // plugins
    'plugin.title': 'Source plugins',
    'plugin.detail':
        'Third-party plugins are community scripts; once installed they let you search and play the sources they provide. Only install sources you trust.',
    'plugin.unsupported':
        'Plugins cannot run on this system. They are available on Windows, '
        'macOS, Linux, iOS and Android.',
    'plugin.urlHint': 'Paste a plugin .js raw link, or a subscription JSON URL',
    'plugin.installing': 'Installing…',
    'plugin.install': 'Install',
    'plugin.checking': 'Checking…',
    'plugin.checkUpdates': 'Check for updates',
    'plugin.installed': 'Installed',
    'plugin.none': 'No plugins installed yet.',
    'plugin.uninstall': 'Uninstall',
    'plugin.installedCountFmt': 'Installed {n} plugin(s)',
    'plugin.installFailedFmt': 'Install failed: {e}',
    'plugin.updatedCountFmt': 'Updated {n} plugin(s)',
    'plugin.upToDate': 'Plugins are up to date',
    'plugin.updateFailedFmt': 'Update check failed: {e}',
    'plugin.updateFailureFmt': '{name} ({reason})',
    'plugin.err.updateUnexpected':
        'An unexpected error stopped the update; the installed version is kept',
    'plugin.confirmTitle': 'Install third-party plugin',
    'plugin.confirmBody':
        'Plugins are community scripts that make network requests on your behalf to search for and fetch audio. Only install sources you trust.',
    'plugin.confirmInstall': 'I trust it, install',

    // settings bodies
    'settings.detail.general':
        'Language, playback, appearance and privacy preferences.',
    'settings.detail.appearance':
        'Change the theme skin: upload an image as the background.',
    'settings.detail.sources':
        'Built-in sources ready to use; disable any as you like.',
    'settings.detail.plugins':
        'Paste a GitHub URL to install third-party source plugins.',
    'settings.detail.downloads':
        'View the local-music folder; open or clear downloads.',
    'settings.shortcuts': 'Shortcuts',
    'settings.detail.shortcuts':
        'View and customize the desktop playback shortcuts.',
    'settings.shortcutsHint':
        'Click a key, then press a modifier combo (e.g. ⌘ / Ctrl + key); Esc cancels.',
    'settings.shortcutDesktopOnly':
        'Keyboard shortcuts are available on desktop only (Windows / macOS / Linux).',
    'settings.shortcutReset': 'Reset to defaults',
    'settings.shortcutPress': 'Press a combo…',
    'shortcut.playPause': 'Play / Pause',
    'shortcut.seekForward': 'Seek +5s',
    'shortcut.seekBackward': 'Seek −5s',
    'shortcut.volumeUp': 'Volume +5%',
    'shortcut.volumeDown': 'Volume −5%',
    'shortcut.nextTrack': 'Next track',
    'shortcut.previousTrack': 'Previous track',
    'settings.appearanceDetail':
        'Choose a built-in theme, or upload an image as a custom background.',
    'settings.custom': 'Custom',
    'settings.changeBg': 'Change background image',
    'settings.uploadBg': 'Upload background image',
    'settings.usingCustomBg': 'Using a custom background',
    'settings.bgApplied': 'Custom background applied',
    'settings.bgReadFailed':
        'Could not read the selected image, please try again.',
    'settings.language': 'Interface language',
    'settings.restoreSession': 'Restore last session on launch',
    'settings.playback': 'Playback',
    'settings.volume': 'Volume',
    'settings.loopMode': 'Loop mode',
    'settings.defaultQuality': 'Default quality: ',
    'settings.releaseAfterPause': 'Release playback resources after pause',
    'settings.playbackSpeed': 'Playback speed',
    'settings.speedNormal': 'Normal',
    'settings.sleepTimer': 'Sleep timer',
    'settings.sleepOff': 'Off',
    'settings.minutesFmt': '{m} min',
    'settings.appearancePrivacy': 'Appearance & privacy',
    'settings.reducedEffects': 'Reduce visual effects',
    'settings.noGpuEffects':
        'No GPU found: spin and frosted glass are off by default to save CPU.',
    'settings.diagnosticLogging': 'Local diagnostic logging',
    'settings.diagnosticSubtitle':
        'Off by default; only for exporting local troubleshooting info.',
    'settings.viewDiagnostics': 'View diagnostic log',
    'settings.agentControl': 'Agent control',
    'settings.diagnosticsTitle': 'Diagnostic log',
    'settings.noLogs': 'No logs yet.',
    'settings.builtinSources': 'Built-in sources',
    'settings.sourcesDetail':
        'Disabled sources are excluded from search and discovery.',

    // agent control
    'agent.localInterface': 'Local control interface',
    'agent.interfaceSubtitle':
        'On by default: exposes a local HTTP interface (loopback only) for local agents/scripts to control the player. Every request must carry this run\'s token, from a file only your account can read.',
    'agent.starting': 'Starting…',
    'agent.address': 'Address',
    'agent.token': 'Token',
    'agent.exampleLabel': 'Example: ',
    'agent.endpointsLabel': 'Endpoints: ',
    'agent.copiedUrl': 'Copied the example URL',

    // source descriptions
    'source.audiusDetail': 'Public on-demand music · HTTPS · No account',
    'source.openverseDetail':
        'Openly licensed music (Jamendo, Freesound, Wikimedia Commons, ccMixter) · HTTPS · No account',
    'source.radioDetail':
        'Public radio directory & live streams · HTTP(S) · No account',
    'source.builtinDetail': 'Built-in source',

    // loop modes
    'loop.queue': 'Repeat queue',
    'loop.track': 'Repeat track',
    'loop.off': 'In order',
    'loop.shuffle': 'Shuffle',

    // quality presets
    'quality.standard': 'Standard',
    'quality.high': 'High',
    'quality.lossless': 'Lossless',
    'quality.hires': 'Hi-Res',
  };
}
