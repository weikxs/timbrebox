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
  static String? _cached;

  static const _libraries = <String, String>{
    '__lib_cryptojs': 'assets/plugin_shims/crypto-js.js',
    '__lib_he': 'assets/plugin_shims/he.js',
    '__lib_dayjs': 'assets/plugin_shims/dayjs.js',
    '__lib_qs': 'assets/plugin_shims/qs.js',
    '__lib_cheerio': 'assets/plugin_shims/cheerio.js',
    '__lib_bigint': 'assets/plugin_shims/big-integer.js',
  };

  /// Returns the combined shim JS, loaded from assets once and cached.
  static Future<String> bundle() async {
    final cached = _cached;
    if (cached != null) return cached;
    final buffer = StringBuffer();
    for (final entry in _libraries.entries) {
      final code = await rootBundle.loadString(entry.value);
      buffer
        ..writeln('(function(){')
        ..writeln('var module={exports:{}};var exports=module.exports;')
        ..writeln(code)
        ..writeln('globalThis.${entry.key}=module.exports;')
        ..writeln('})();');
    }
    return _cached = buffer.toString();
  }
}
