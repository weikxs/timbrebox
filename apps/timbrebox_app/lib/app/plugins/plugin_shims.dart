import 'package:flutter/services.dart';

/// Bundles the pure-JS libraries that plugins commonly `require`
/// (axios is provided separately by the runtime): crypto-js, he, dayjs, qs,
/// cheerio (a self-contained bundle, so HTML-scraping plugins work),
/// and big-integer.
///
/// Each library is wrapped in an IIFE with its own `module`/`exports` so its
/// UMD/CJS build exports into a private global (`__lib_*`) instead of clobbering
/// the plugin's own `module.exports`.
abstract final class PluginShims {
  static final Map<String, String> _cached = {};

  /// Module name (as passed to `require`) → global + asset.
  static const _libraries = <String, (String, String)>{
    'crypto-js': ('__lib_cryptojs', 'assets/plugin_shims/crypto-js.js'),
    'he': ('__lib_he', 'assets/plugin_shims/he.js'),
    'dayjs': ('__lib_dayjs', 'assets/plugin_shims/dayjs.js'),
    'qs': ('__lib_qs', 'assets/plugin_shims/qs.js'),
    'cheerio': ('__lib_cheerio', 'assets/plugin_shims/cheerio.js'),
    'big-integer': ('__lib_bigint', 'assets/plugin_shims/big-integer.js'),
  };

  /// The shim JS [pluginSource] may need: only libraries whose module name
  /// appears in it as a quoted string literal (`require('cheerio')`), so a
  /// plugin that requires nothing evaluates none of the ~1.1 MB of shims.
  static Future<String> forSource(String pluginSource) async {
    final buffer = StringBuffer();
    for (final entry in _libraries.entries) {
      if (!mentions(pluginSource, entry.key)) continue;
      buffer.writeln(await _load(entry.value.$1, entry.value.$2));
    }
    return buffer.toString();
  }

  /// Whether [source] names [module] in a quoted string literal.
  static bool mentions(String source, String module) =>
      source.contains("'$module'") ||
      source.contains('"$module"') ||
      source.contains('`$module`');

  /// One library wrapped to export into [global]; loaded once and cached.
  static Future<String> _load(String global, String asset) async {
    final cached = _cached[asset];
    if (cached != null) return cached;
    final code = await rootBundle.loadString(asset);
    final wrapped =
        (StringBuffer()
              ..writeln('(function(){')
              ..writeln('var module={exports:{}};var exports=module.exports;')
              ..writeln(code)
              ..writeln('globalThis.$global=module.exports;')
              ..writeln('})();'))
            .toString();
    return _cached[asset] = wrapped;
  }
}
