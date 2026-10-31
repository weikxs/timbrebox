import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_js/javascriptcore/flutter_jscore.dart';
import 'package:flutter_js/javascriptcore/jscore_bindings.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';

// JavaScriptCore's documented C callback ABI, independently routed by ctx.
typedef _Message =
    Pointer<Void> Function(
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      UintPtr,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Void>>,
    );
typedef _MakeNative =
    Pointer<Void> Function(
      Pointer<Void>,
      Pointer<Void>,
      Pointer<NativeFunction<_Message>>,
    );
typedef _Make =
    Pointer<Void> Function(
      Pointer<Void>,
      Pointer<Void>,
      Pointer<NativeFunction<_Message>>,
    );

/// Replaces the dependency's process-global "last runtime" callback. No plugin
/// can select another context: the native engine supplies that pointer.
final class JscContextBridge {
  JscContextBridge._(this._runtime) {
    final Pointer<Void> context = _runtime.context.pointer.cast<Void>();
    _address = context.address;
    _channels = JavascriptRuntime
        .channelFunctionsRegistered[_runtime.getEngineInstanceId()]!;
    final name = JSString.fromString('sendMessage');
    try {
      final function = JscFfi.lib.lookupFunction<_MakeNative, _Make>(
        'JSObjectMakeFunctionWithCallback',
      )(context, nullptr, Pointer.fromFunction<_Message>(_dispatch));
      jSObjectSetProperty(
        context,
        jSContextGetGlobalObject(context),
        name.pointer,
        function,
        0,
        nullptr,
      );
      _contexts[_address] = this;
    } finally {
      name.release();
    }
  }

  static JscContextBridge? attach(JavascriptRuntime runtime) =>
      runtime is JavascriptCoreRuntime ? JscContextBridge._(runtime) : null;

  final JavascriptCoreRuntime _runtime;
  late final int _address;
  late final Map<String, dynamic Function(dynamic)> _channels;
  final _timers = <String, Timer>{};
  bool _disposed = false;
  static final _contexts = <int, JscContextBridge>{};

  static Pointer<Void> _dispatch(
    Pointer<Void> context,
    Pointer<Void> function,
    Pointer<Void> receiver,
    int count,
    Pointer<Pointer<Void>> arguments,
    Pointer<Pointer<Void>> exception,
  ) {
    final owner = _contexts[context.address];
    if (owner == null || owner._disposed) return nullptr;
    try {
      if (count >= 2) {
        final channel = JSValue(owner._runtime.context, arguments[0]).string;
        final text = JSValue(owner._runtime.context, arguments[1]).string;
        if (channel != null && text != null) {
          final payload = jsonDecode(text);
          if (channel == 'SetTimeout') {
            owner._setTimeout(payload);
          } else {
            // The existing host bridge is explicitly fire-and-forget.
            owner._channels[channel]?.call(payload);
          }
        }
      }
    } catch (_) {
      // No Dart exception may escape an FFI callback. Invalid messages settle
      // nothing; the owning call's existing deadline still bounds its wait.
    }
    return jSValueMakeUndefined(context).cast<Void>();
  }

  void _setTimeout(dynamic payload) {
    if (payload is! Map) return;
    final index = payload['timeoutIndex'], delay = payload['timeout'] ?? 0;
    if (index is! String ||
        !RegExp(r'^\d{1,16}$').hasMatch(index) ||
        delay is! num ||
        !delay.isFinite ||
        _timers.length >= 128) {
      return;
    }
    _timers.remove(index)?.cancel();
    _timers[index] = Timer(
      Duration(milliseconds: delay.clamp(0, 3600000).toInt()),
      () {
        _timers.remove(index);
        if (_disposed) return;
        _runtime.evaluate('''
        (function(){
          var callbacks = globalThis.__NATIVE_FLUTTER_JS__setTimeoutCallbacks;
          var callback = callbacks && callbacks["$index"];
          if (callbacks) delete callbacks["$index"];
          if (typeof callback === 'function') callback();
        })();
      ''');
      },
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (identical(_contexts[_address], this)) _contexts.remove(_address);
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    final id = _runtime.getEngineInstanceId();
    if (identical(
      JavascriptRuntime.channelFunctionsRegistered[id],
      _channels,
    )) {
      JavascriptRuntime.channelFunctionsRegistered.remove(id);
    }
    _channels.clear();
  }
}
