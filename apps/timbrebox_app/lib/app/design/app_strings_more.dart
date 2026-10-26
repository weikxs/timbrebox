/// The second half of the [AppStrings] tables, kept in its own file so
/// neither grows past the size limit. Same keys in both languages.
library;

const moreZhStrings = <String, String>{
  // plugins
  'plugin.skippedFmt': '有插件无法加载，已跳过：{ids}。文件可能已损坏，请从原链接重新安装。',
  'plugin.updatedSomeFailedFmt': '更新了 {n} 个插件；以下插件检查失败：{names}',
  'plugin.runtime.timeout': '插件脚本运行过久，已被终止。',
};

const moreEnStrings = <String, String>{
  // plugins
  'plugin.skippedFmt':
      'Some plugins could not be loaded and were skipped: {ids}. Their files '
      'may be damaged — reinstall them from their original link.',
  'plugin.updatedSomeFailedFmt':
      'Updated {n} plugin(s); these could not be checked: {names}',
  'plugin.runtime.timeout': 'The plugin script ran too long and was stopped.',
};
