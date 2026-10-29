import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';

import '../design/app_strings.dart';
import 'plugin_environment.dart';
import 'plugin_http.dart';
import 'plugin_shims.dart';
import 'script_time_limit.dart';

/// Runs one plugin's JavaScript in a sandboxed engine (QuickJS on
/// Android/Windows/Linux, JavaScriptCore on Apple). The only capability crossing
/// into the sandbox is HTTP, wired through a pending-promise bridge: JS calls
/// `axios` → `__hostHttp` (fire-and-forget `sendMessage`), Dart performs the
/// request off the JS thread, then settles the JS promise via `__resolveHost`.
///
/// The sandbox's JavaScript lives in `assets/plugin_runtime/`: the prelude
/// (bridge, `env`, `process`, `require`), `URL` and an axios-compatible
/// client, so plugins written for other players in the same format run as is.
final class PluginRuntime {
  PluginRuntime({PluginHttpClient? http, PluginEnvironment? environment})
    : _http = http ?? PluginHttpClient(),
      _environment = environment ?? PluginEnvironment.current(),
      // No fetch / XMLHttpRequest from flutter_js (they would bypass
      // PluginHttpClient's egress policy), and a time limit on each run.
      _rt = createTimeLimitedRuntime();

  final PluginHttpClient _http;
  final PluginEnvironment _environment;
  final JavascriptRuntime _rt;
  var _disposed = false;
  Future<void> _queue = Future<void>.value();

  /// Loads a plugin module and exposes what it exported as `__plugin`:
  /// `module.exports`, or its `default` when the plugin was built from an ES
  /// module.
  Future<void> load(String pluginSource) async {
    final shims = await PluginShims.forSource(pluginSource);
    final sandbox = await _sandboxScripts();
    _rt.onMessage('__hostHttp', (dynamic args) {
      _dispatchHttp(args);
      return '';
    });
    _rt.onMessage('__log', (dynamic args) {
      debugPrint('[plugin] $args');
      return '';
    });
    _rt.evaluate(_withValues(sandbox.prelude));
    _rt.evaluate(sandbox.url);
    _rt.evaluate(sandbox.axios);
    if (shims.isNotEmpty) _rt.evaluate(shims);
    _rt.evaluate('var module={exports:{}};var exports=module.exports;');
    _rt.evaluate(pluginSource);
    _rt.evaluate('globalThis.__plugin = __exportOf(module);');
  }

  /// Reads a top-level metadata string (e.g. `platform`, `version`, `srcUrl`).
  String? meta(String key) {
    final result = _rt.evaluate(
      'typeof __plugin.$key === "string" ? __plugin.$key : ""',
    );
    final value = result.stringResult;
    return value.isEmpty ? null : value;
  }

  bool hasFunction(String name) =>
      _rt.evaluate('typeof __plugin.$name === "function"').stringResult ==
      'true';

  /// Calls an exported async plugin function with JSON-encoded [args] and
  /// returns the decoded result (or null). Calls are serialized so concurrent
  /// search/resolve requests can't interleave on the single JS runtime.
  Future<Object?> call(String function, List<Object?> args) {
    final result = _queue.then((_) => _call(function, args));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Object?> _call(String function, List<Object?> args) async {
    final encoded = args.map(jsonEncode).join(', ');
    // Wrap the call so a JS rejection returns a readable message instead of
    // stringifying an Error to "{}".
    final code =
        '''
      (async () => {
        try {
          const out = await __plugin.$function($encoded);
          return JSON.stringify({ ok: true, value: out === undefined ? null : out });
        } catch (e) {
          return JSON.stringify({ ok: false, error: (e && e.message) ? e.message : String(e) });
        }
      })()
    ''';
    final watch = Stopwatch()..start();
    final async = await _rt.evaluateAsync(code);
    _rt.executePendingJob();
    // A run as long as the limit was cut off by the engine (JavaScriptCore
    // reports no error for it, so the clock is what tells).
    if (watch.elapsed >= pluginScriptTimeLimit) {
      throw PluginScriptTimeout(AppStrings.t('plugin.runtime.timeout'));
    }
    if (async.isError) throw PluginRuntimeException(async.stringResult);
    final resolved = await _rt
        .handlePromise(async)
        .timeout(const Duration(seconds: 25));
    if (resolved.isError) {
      throw PluginRuntimeException(resolved.stringResult);
    }
    final envelope = decodeCallEnvelope(resolved.stringResult);
    if (envelope is Map && envelope['ok'] == false) {
      throw PluginRuntimeException(
        '${envelope['error'] ?? AppStrings.t('plugin.runtime.execFailed')}',
      );
    }
    return envelope is Map ? envelope['value'] : null;
  }

  /// The `{ok, value | error}` envelope a call's promise settled with, or null.
  /// QuickJS hands the envelope back as the JSON text the call returned;
  /// JavaScriptCore (macOS, iOS) runs `JSON.stringify` over that text once
  /// more, so the first decode yields a string to decode again.
  @visibleForTesting
  static Object? decodeCallEnvelope(String text) {
    if (text.isEmpty) return null;
    final decoded = jsonDecode(text);
    return decoded is String && decoded.isNotEmpty
        ? jsonDecode(decoded)
        : decoded;
  }

  void _dispatchHttp(dynamic args) {
    Map<String, Object?> request;
    try {
      // flutter_js may hand back either the raw JSON string or a decoded Map.
      final decoded = args is String ? jsonDecode(args) : args;
      request = Map<String, Object?>.from(decoded as Map);
    } catch (_) {
      return;
    }
    final id = request['id'];
    // Off the JS thread: run the request, then settle the JS promise.
    Future(() async {
      try {
        final response = await _http.send(request);
        _settle(id, true, response);
      } on PluginHttpTimeout catch (error) {
        _settle(id, false, {'message': error.message, 'code': 'timeout'});
      } catch (error) {
        _settle(id, false, {'message': '$error'});
      }
    });
  }

  void _settle(Object? id, bool ok, Object? payload) {
    if (_disposed) return;
    _rt.evaluate('__resolveHost($id, $ok, ${_jsLiteral(payload)});');
    _rt.executePendingJob();
  }

  /// [value] as a JS data literal. JSON is plain data in JS syntax (no code),
  /// so the body is escaped once and the sandbox skips a `JSON.parse` of a
  /// second, doubly escaped copy. U+2028/U+2029 are escaped too: engines
  /// before ES2019 read them as line breaks inside a string literal.
  static String _jsLiteral(Object? value) => jsonEncode(
    value,
  ).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _rt.dispose();
    _http.close();
  }

  /// The prelude with the environment and its error messages, in the app's
  /// language, filled in as JS literals.
  String _withValues(String prelude) => prelude
      .replaceAll('__ENV__', _jsLiteral(_environment.toJson()))
      .replaceAll(
        '__MSG_NOT_LOADED__',
        _jsLiteral(AppStrings.t('plugin.js.moduleNotLoaded')),
      )
      .replaceAll(
        '__MSG_NOT_ALLOWED__',
        _jsLiteral(AppStrings.t('plugin.js.moduleNotAllowed')),
      );

  static _SandboxScripts? _scripts;

  /// The sandbox's own scripts, read from the assets once.
  static Future<_SandboxScripts> _sandboxScripts() async => _scripts ??= (
    prelude: await rootBundle.loadString('assets/plugin_runtime/prelude.js'),
    url: await rootBundle.loadString('assets/plugin_runtime/url.js'),
    axios: await rootBundle.loadString('assets/plugin_runtime/axios.js'),
  );
}

typedef _SandboxScripts = ({String prelude, String url, String axios});

class PluginRuntimeException implements Exception {
  const PluginRuntimeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The plugin ran past [pluginScriptTimeLimit] and was stopped; its engine
/// should not be trusted for further calls.
class PluginScriptTimeout extends PluginRuntimeException {
  const PluginScriptTimeout(super.message);
}
