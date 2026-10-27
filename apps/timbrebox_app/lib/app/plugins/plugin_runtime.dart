import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

import '../design/app_strings.dart';
import 'plugin_http.dart';
import 'plugin_shims.dart';
import 'script_time_limit.dart';

/// Runs one plugin's JavaScript in a sandboxed engine (QuickJS on
/// Android/Windows/Linux, JavaScriptCore on Apple). The only capability crossing
/// into the sandbox is HTTP, wired through a pending-promise bridge: JS calls
/// `axios` → `__hostHttp` (fire-and-forget `sendMessage`), Dart performs the
/// request off the JS thread, then settles the JS promise via `__resolveHost`.
final class PluginRuntime {
  PluginRuntime({PluginHttpClient? http})
    : _http = http ?? PluginHttpClient(),
      // No fetch / XMLHttpRequest from flutter_js (they would bypass
      // PluginHttpClient's egress policy), and a time limit on each run.
      _rt = createTimeLimitedRuntime();

  final PluginHttpClient _http;
  final JavascriptRuntime _rt;
  var _disposed = false;
  Future<void> _queue = Future<void>.value();

  /// Loads a plugin module and exposes its `module.exports` as `__plugin`.
  Future<void> load(String pluginSource) async {
    final shims = await PluginShims.forSource(pluginSource);
    _rt.onMessage('__hostHttp', (dynamic args) {
      _dispatchHttp(args);
      return '';
    });
    _rt.onMessage('__log', (dynamic args) {
      debugPrint('[plugin] $args');
      return '';
    });
    _rt.evaluate(_localizedPrelude());
    if (shims.isNotEmpty) _rt.evaluate(shims);
    _rt.evaluate('var module={exports:{}};var exports=module.exports;');
    _rt.evaluate(pluginSource);
    _rt.evaluate('globalThis.__plugin = module.exports;');
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

  /// [_prelude] with its error messages in the app's language (as JS string
  /// literals).
  static String _localizedPrelude() => _prelude
      .replaceAll(
        '__MSG_NOT_LOADED__',
        _jsLiteral(AppStrings.t('plugin.js.moduleNotLoaded')),
      )
      .replaceAll(
        '__MSG_NOT_ALLOWED__',
        _jsLiteral(AppStrings.t('plugin.js.moduleNotAllowed')),
      );

  static const _prelude = r'''
    // HTTP must go through __hostHttp, never a built-in network API.
    delete globalThis.fetch;
    delete globalThis.XMLHttpRequest;
    var module = { exports: {} };
    var exports = module.exports;
    var console = {
      log: function(){ sendMessage('__log', Array.prototype.join.call(arguments, ' ')); },
      warn: function(){ sendMessage('__log', Array.prototype.join.call(arguments, ' ')); },
      error: function(){ sendMessage('__log', Array.prototype.join.call(arguments, ' ')); }
    };

    var __pending = {};
    var __reqId = 0;
    function __hostHttp(config) {
      return new Promise(function(resolve, reject) {
        var id = ++__reqId;
        __pending[id] = { resolve: resolve, reject: reject };
        sendMessage('__hostHttp', JSON.stringify({
          id: id,
          url: config.url,
          method: config.method || 'GET',
          headers: config.headers || {},
          params: config.params || null,
          data: config.data != null ? config.data : null
        }));
      });
    }
    globalThis.__resolveHost = function(id, ok, payload) {
      var p = __pending[id];
      if (!p) return;
      delete __pending[id];
      if (ok) p.resolve(payload); else p.reject(new Error(payload && payload.message || 'request failed'));
    };

    function axios(config) {
      if (typeof config === 'string') config = { url: config };
      return __hostHttp(config).then(function(res) {
        // Mimic axios: JSON-parse the body by default, keep raw text only when
        // the caller explicitly asked for text/binary.
        var rt = config.responseType;
        var raw = rt === 'text' || rt === 'arraybuffer' || rt === 'blob';
        if (!raw && typeof res.data === 'string') {
          try { res.data = JSON.parse(res.data); } catch (e) {}
        }
        return res;
      });
    }
    axios.get = function(url, config) { config = config || {}; config.url = url; config.method = 'GET'; return axios(config); };
    axios.post = function(url, data, config) { config = config || {}; config.url = url; config.data = data; config.method = 'POST'; return axios(config); };
    axios.default = axios;

    // Only the libraries a plugin names are evaluated (see PluginShims).
    function __shim(name, lib) {
      if (lib === undefined) throw new Error(__MSG_NOT_LOADED__ + name);
      return lib;
    }
    function require(name) {
      switch (name) {
        case 'axios': return axios;
        case 'crypto-js': return __shim(name, globalThis.__lib_cryptojs);
        case 'he': return __shim(name, globalThis.__lib_he);
        case 'dayjs': return __shim(name, globalThis.__lib_dayjs);
        case 'qs': return __shim(name, globalThis.__lib_qs);
        case 'cheerio': return __shim(name, globalThis.__lib_cheerio);
        case 'big-integer': return __shim(name, globalThis.__lib_bigint);
        default: throw new Error(__MSG_NOT_ALLOWED__ + name);
      }
    }
  ''';
}

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
