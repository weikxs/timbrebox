import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_js/javascriptcore/binding/jsc_ffi.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/quickjs/ffi.dart' show runtimeOpaques;

import '../native/libc.dart';

/// The longest one synchronous run of plugin code may take.
///
/// flutter_js evaluates on the UI isolate, so while a script runs nothing
/// else does: a plugin stuck in `while (true) {}` would freeze the app. Each
/// entry into the engine (a call, a resolved request, a timer) is cut off
/// after this long. Real plugin work (parsing a page, signing a request)
/// takes milliseconds.
const pluginScriptTimeLimit = Duration(seconds: 3);

/// A JS engine for one plugin, with [pluginScriptTimeLimit] enforced where
/// the engine allows it: JavaScriptCore's execution time limit on Apple
/// platforms, QuickJS's interrupt handler where the bundled QuickJS exports
/// it (Linux; the Windows build does not). Without either the engine still
/// works, unguarded.
JavascriptRuntime createTimeLimitedRuntime() {
  if (Platform.isWindows || Platform.isLinux) {
    return _TimeLimitedQuickJs.create();
  }
  _usePollingTrapsOnce();
  final runtime = getJavascriptRuntime(xhr: false);
  if (runtime is JavascriptCoreRuntime) _limitJavascriptCore(runtime);
  return runtime;
}

var _pollingTrapsSet = false;

/// JavaScriptCore stops JIT-compiled code at its time limit with a signal,
/// which does not reach code running under the Dart VM: only top-level
/// loops were ever cut off. With polling traps the compiled code checks for
/// the stop itself. JavaScriptCore reads its options once, when the first
/// engine is created, so this runs before any plugin engine starts.
void _usePollingTrapsOnce() {
  if (_pollingTrapsSet) return;
  _pollingTrapsSet = true;
  try {
    Libc.setenv('JSC_usePollingTraps', 'true');
  } catch (error) {
    debugPrint('plugin time limit unavailable: $error');
  }
}

typedef _ContextGetGroup = Pointer<Void> Function(Pointer<Void> context);
typedef _SetTimeLimitNative =
    Void Function(
      Pointer<Void> group,
      Double seconds,
      Pointer<Void> callback,
      Pointer<Void> context,
    );
typedef _SetTimeLimit =
    void Function(
      Pointer<Void> group,
      double seconds,
      Pointer<Void> callback,
      Pointer<Void> context,
    );

/// `JSContextGroupSetExecutionTimeLimit` (exported by JavaScriptCore; with
/// no callback the script is terminated once the limit is reached).
void _limitJavascriptCore(JavascriptCoreRuntime runtime) {
  try {
    final library = JscFfi.lib;
    final group = library.lookupFunction<_ContextGetGroup, _ContextGetGroup>(
      'JSContextGetGroup',
    )(runtime.context.pointer.cast());
    final setLimit = library.lookupFunction<_SetTimeLimitNative, _SetTimeLimit>(
      'JSContextGroupSetExecutionTimeLimit',
    );
    setLimit(
      group,
      pluginScriptTimeLimit.inMilliseconds / 1000,
      nullptr,
      nullptr,
    );
  } catch (error) {
    debugPrint('plugin time limit unavailable: $error');
  }
}

typedef _InterruptHandler = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _SetInterruptNative =
    Void Function(
      Pointer<Void> runtime,
      Pointer<NativeFunction<_InterruptHandler>> handler,
      Pointer<Void> opaque,
    );
typedef _SetInterrupt =
    void Function(
      Pointer<Void> runtime,
      Pointer<NativeFunction<_InterruptHandler>> handler,
      Pointer<Void> opaque,
    );

/// When the running entry into each QuickJS runtime must end (by runtime
/// address); absent while the runtime is idle.
final _quickJsDeadlines = <int, DateTime>{};

/// QuickJS asks this every few thousand instructions; non-zero aborts the
/// script with an uncatchable "interrupted" error.
int _interruptQuickJs(Pointer<Void> runtime, Pointer<Void> _) {
  final deadline = _quickJsDeadlines[runtime.address];
  return deadline != null && DateTime.now().isAfter(deadline) ? 1 : 0;
}

/// QuickJS with a deadline armed around every synchronous entry. flutter_js's
/// own timers and promise handling enter through [evaluate] and
/// [executePendingJob] as well, so plugin code has no unguarded way in.
class _TimeLimitedQuickJs extends QuickJsRuntime2 {
  _TimeLimitedQuickJs._();

  int? _address;

  static _TimeLimitedQuickJs create() {
    final before = runtimeOpaques.keys.toSet();
    final runtime = _TimeLimitedQuickJs._()..enableHandlePromises();
    final created = runtimeOpaques.keys.where((key) => !before.contains(key));
    if (created.length == 1) runtime._install(created.single.cast());
    return runtime;
  }

  void _install(Pointer<Void> native) {
    try {
      final library = Platform.isWindows
          ? DynamicLibrary.open('quickjs_c_bridge.dll')
          : DynamicLibrary.open('libquickjs_c_bridge_plugin.so');
      library.lookupFunction<_SetInterruptNative, _SetInterrupt>(
        'JS_SetInterruptHandler',
      )(
        native,
        Pointer.fromFunction<_InterruptHandler>(_interruptQuickJs, 0),
        nullptr,
      );
      _address = native.address;
    } catch (error) {
      debugPrint('plugin time limit unavailable: $error');
    }
  }

  T _limited<T>(T Function() run) {
    final address = _address;
    if (address == null || _quickJsDeadlines.containsKey(address)) {
      return run(); // Unguarded, or nested inside a guarded entry.
    }
    _quickJsDeadlines[address] = DateTime.now().add(pluginScriptTimeLimit);
    try {
      return run();
    } finally {
      _quickJsDeadlines.remove(address);
    }
  }

  @override
  JsEvalResult evaluate(
    String command, {
    String? name,
    int? evalFlags,
    String? sourceUrl,
  }) => _limited(
    () => super.evaluate(
      command,
      name: name,
      evalFlags: evalFlags,
      sourceUrl: sourceUrl,
    ),
  );

  @override
  int executePendingJob() => _limited(super.executePendingJob);

  // Closing the engine drains its pending jobs, so it is guarded too.
  @override
  void dispose() => _limited(super.dispose);
}
