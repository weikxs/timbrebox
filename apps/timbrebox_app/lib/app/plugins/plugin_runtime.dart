import 'dart:async';
import 'dart:convert';

import 'package:timbrebox_core/timbrebox_core.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';

import '../design/app_strings.dart';
import 'plugin_environment.dart';
import 'plugin_http.dart';
import 'media_extractor_process.dart';
import 'platform_media_backend.dart';
import 'plugin_shims.dart';
import 'script_time_limit.dart';
import 'jsc_context_bridge.dart';

/// Runs one plugin's JavaScript in a sandboxed engine (QuickJS on
/// Android/Windows/Linux, JavaScriptCore on Apple). HTTP and an optional fixed
/// desktop media RPC use pending-promise bridges. For HTTP, JS calls
/// `axios` → `__hostHttp` (fire-and-forget `sendMessage`), Dart performs the
/// request off the JS thread, then settles the JS promise via `__resolveHost`.
///
/// The sandbox's JavaScript lives in `assets/plugin_runtime/`: the prelude
/// (bridge, `env`, `process`, `require`), `URL` and an axios-compatible
/// client, the globals and HTTP API plugins in this format rely on.
final class PluginRuntime {
  PluginRuntime({
    PluginHttpClient? http,
    PluginEnvironment? environment,
    PlatformMediaBackend? media,
  }) : _http = http ?? PluginHttpClient(),
       _media = media ?? DesktopPlatformMediaBackend(),
       _environment = environment ?? PluginEnvironment.current(),
       // No fetch / XMLHttpRequest from flutter_js (they would bypass
       // PluginHttpClient's egress policy), and a time limit on each run.
       _rt = createTimeLimitedRuntime() {
    try {
      _contextBridge = JscContextBridge.attach(_rt);
    } catch (_) {
      _rt.dispose();
      rethrow;
    }
  }

  final PluginHttpClient _http;
  final PlatformMediaBackend _media;
  final PluginEnvironment _environment;
  final JavascriptRuntime _rt;
  late final JscContextBridge? _contextBridge;
  var _disposed = false;
  Future<void> _queue = Future<void>.value();
  CancellationToken? _activeCancellation;
  int _invocation = 0;
  int? _activeInvocation;
  final _results = <int, Completer<Map<String, Object?>>>{};
  Timer? _jobPump;

  /// Loads a plugin module and exposes what it exported as `__plugin`:
  /// `module.exports`, or its `default` when the plugin was built from an ES
  /// module.
  Future<void> load(String pluginSource) async {
    _ensureActive();
    final shims = await PluginShims.forSource(pluginSource);
    final sandbox = await _sandboxScripts();
    _ensureActive();
    _rt.onMessage('__hostHttp', (dynamic args) {
      _dispatchHttp(args);
      return '';
    });
    _rt.onMessage('__hostMedia', (dynamic args) {
      _dispatchMedia(args);
      return '';
    });
    _rt.onMessage('__pluginCallResult', (dynamic args) {
      _completeCall(args);
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
    _ensureActive();
    final result = _rt.evaluate(
      'typeof __plugin.$key === "string" ? __plugin.$key : ""',
    );
    final value = result.stringResult;
    return value.isEmpty ? null : value;
  }

  /// The plugin's declared `userVariables` as plain data (not yet checked),
  /// or an empty list.
  List<Object?> declaredVariables() {
    _ensureActive();
    final result = _rt.evaluate(
      'JSON.stringify(Array.isArray(__plugin.userVariables) ? '
      '__plugin.userVariables : [])',
    );
    try {
      final decoded = decodeCallEnvelope(result.stringResult);
      return decoded is List ? decoded : const [];
    } on FormatException {
      return const [];
    }
  }

  bool hasFunction(String name) {
    _ensureActive();
    return _rt.evaluate('typeof __plugin.$name === "function"').stringResult ==
        'true';
  }

  void _ensureActive() {
    if (_disposed) {
      throw PluginRuntimeException(AppStrings.t('plugin.src.disposed'));
    }
  }

  /// Calls an exported async plugin function with JSON-encoded [args] and
  /// returns the decoded result (or null). Calls are serialized so concurrent
  /// search/resolve requests can't interleave on the single JS runtime.
  Future<Object?> call(
    String function,
    List<Object?> args, {
    CancellationToken? cancellation,
  }) {
    var active = false;
    var finished = false;
    final result = _queue
        .then((_) {
          cancellation?.throwIfCancelled();
          if (_disposed) {
            throw PluginRuntimeException(AppStrings.t('plugin.src.disposed'));
          }
          active = true;
          _activeCancellation = cancellation;
          _activeInvocation = ++_invocation;
          return _call(function, args).whenComplete(() {
            _activeCancellation = null;
            _activeInvocation = null;
            _media.cancel();
          });
        })
        .whenComplete(() => finished = true);
    // Keep serialization until the actual JS invocation ends, even when its
    // caller has already received cancellation.
    _queue = result.then((_) {}, onError: (_) {});
    if (cancellation == null) return result;
    return Future.any([
      result,
      cancellation.whenCancelled.then<Object?>((_) {
        if (active && !finished) {
          _media.cancel();
          // One serialized invocation owns this client's requests. Abort its
          // sockets too, so an obsolete HTTP search cannot block the next one.
          _http.close();
        }
        throw const OperationCancelled();
      }),
    ]);
  }

  Future<Object?> _call(String function, List<Object?> args) async {
    final encoded = args.map(jsonEncode).join(', ');
    final id = _activeInvocation!;
    final completed = Completer<Map<String, Object?>>();
    _results[id] = completed;
    // Own the result bridge and its job pump so no third-party promise polling
    // can outlive disposal of the native engine. JSON serialization is inside
    // the try block: cyclic/non-JSON results become ordinary plugin errors.
    final code =
        '''
      (async () => {
        try {
          const out = await __plugin.$function($encoded);
          sendMessage('__pluginCallResult', JSON.stringify({id: $id, ok: true, value: out === undefined ? null : out}));
        } catch (e) {
          sendMessage('__pluginCallResult', JSON.stringify({id: $id, ok: false, error: (e && e.message) ? e.message : String(e), code: e && e.code}));
        }
      })()
    ''';
    try {
      final watch = Stopwatch()..start();
      final evaluated = _rt.evaluate(code);
      _rt.executePendingJob();
      if (watch.elapsed >= pluginScriptTimeLimit) {
        throw PluginScriptTimeout(AppStrings.t('plugin.runtime.timeout'));
      }
      if (evaluated.isError) {
        throw PluginRuntimeException(evaluated.stringResult);
      }
      if (!completed.isCompleted) {
        _jobPump = Timer.periodic(const Duration(milliseconds: 20), (timer) {
          if (_disposed || completed.isCompleted) {
            timer.cancel();
            return;
          }
          _rt.executePendingJob();
        });
      }
      final envelope = await completed.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          _media.cancel();
          _http.close();
          throw PluginScriptTimeout(AppStrings.t('plugin.runtime.timeout'));
        },
      );
      if (envelope['ok'] == false) {
        final errorCode = envelope['code'];
        throw PluginRuntimeException(
          '${envelope['error'] ?? AppStrings.t('plugin.runtime.execFailed')}',
          code:
              errorCode is String &&
                  RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(errorCode)
              ? errorCode
              : null,
        );
      }
      return envelope['value'];
    } finally {
      _jobPump?.cancel();
      _jobPump = null;
      _results.remove(id);
    }
  }

  void _completeCall(dynamic args) {
    if (_disposed) return;
    try {
      final envelope = args is String ? decodeCallEnvelope(args) : args;
      if (envelope is! Map || envelope['id'] is! int) return;
      final pending = _results[envelope['id']];
      if (pending == null || pending.isCompleted) return;
      pending.complete(Map<String, Object?>.from(envelope));
    } catch (_) {
      // Malformed or unrelated messages never complete another invocation.
    }
  }

  /// Accept plain JSON or one engine-added string wrapper. Used for metadata
  /// and call-result messages without depending on native Promise handles.
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
    if (id is! int || id < 1) return;
    final cancellation = _activeCancellation;
    final invocation = _activeInvocation;
    bool cancelled() =>
        _disposed ||
        cancellation?.isCancelled == true ||
        invocation != null && invocation != _activeInvocation;
    void settleCancelled() => _settle(id, false, {
      'message': AppStrings.t('plugin.runtime.cancelled'),
      'code': 'cancelled',
    });
    // Capture scope before deferring: an old callback must not borrow the next
    // invocation's token or start another request after cancellation.
    Future(() async {
      try {
        if (cancelled()) throw const OperationCancelled();
        final response = await _http.send(request);
        if (cancelled()) throw const OperationCancelled();
        _settle(id, true, response);
      } on OperationCancelled {
        settleCancelled();
      } on PluginHttpTimeout catch (error) {
        if (cancelled()) {
          settleCancelled();
        } else {
          _settle(id, false, {'message': error.message, 'code': 'timeout'});
        }
      } catch (error) {
        if (cancelled()) {
          settleCancelled();
        } else {
          _settle(id, false, {'message': '$error'});
        }
      }
    });
  }

  void _dispatchMedia(dynamic args) {
    if (args is String && args.length > 16 * 1024) return;
    Map<String, Object?> request;
    try {
      final decoded = args is String ? jsonDecode(args) : args;
      request = Map<String, Object?>.from(decoded as Map);
    } catch (_) {
      return;
    }
    final id = request['id'];
    if (id is! int || id < 1) return;
    final cancellation = _activeCancellation;
    final invocation = _activeInvocation;
    Future(() async {
      try {
        if (_disposed ||
            invocation == null ||
            invocation != _activeInvocation ||
            cancellation?.isCancelled == true) {
          throw const MediaExtractionException(
            'extractor_cancelled',
            'Media extraction was cancelled.',
          );
        }
        final result = await _media.call(request);
        _settle(id, true, result);
      } on MediaExtractionException catch (error) {
        _settle(id, false, {
          'message': AppStrings.t('plugin.media.${error.code}'),
          'code': error.code,
        });
      } catch (_) {
        _settle(id, false, {
          'message': AppStrings.t('plugin.media.extractor_failed'),
          'code': 'extractor_failed',
        });
      }
    });
  }

  void _settle(int id, bool ok, Object? payload) {
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
    _jobPump?.cancel();
    _jobPump = null;
    _media.dispose();
    _http.close();
    for (final pending in _results.values) {
      if (!pending.isCompleted) {
        pending.complete({
          'ok': false,
          'error': AppStrings.t('plugin.src.disposed'),
          'code': 'extractor_cancelled',
        });
      }
    }
    _contextBridge?.dispose();
    _rt.dispose();
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
  const PluginRuntimeException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

/// The plugin ran past [pluginScriptTimeLimit] and was stopped; its engine
/// should not be trusted for further calls.
class PluginScriptTimeout extends PluginRuntimeException {
  const PluginScriptTimeout(super.message)
    : super(code: 'plugin_script_timeout');
}
