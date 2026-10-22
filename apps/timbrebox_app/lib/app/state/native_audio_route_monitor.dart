import 'dart:async';

import 'package:flutter/services.dart';

import 'audio_route_monitor.dart';

/// Desktop audio-route monitor backed by native code over an [EventChannel].
///
/// The native side (macOS CoreAudio / Windows IMMDevice / Linux) emits the
/// strings `"connected"` / `"disconnected"` when the default output device
/// switches to or from an external device (Bluetooth / headphones).
class NativeAudioRouteMonitor implements AudioRouteMonitor {
  static const EventChannel _channel = EventChannel('timbrebox/audio_route');

  StreamController<AudioRouteEvent>? _controller;
  StreamSubscription<dynamic>? _subscription;

  @override
  Future<void> start() async {
    final controller = _controller ??=
        StreamController<AudioRouteEvent>.broadcast();
    _subscription = _channel.receiveBroadcastStream().listen(
      (event) {
        final mapped = _map(event);
        if (mapped != null) controller.add(mapped);
      },
      onError: (_) {}, // Best-effort: a channel error just disables the feature.
    );
  }

  AudioRouteEvent? _map(Object? event) => switch (event) {
    'connected' => AudioRouteEvent.outputConnected,
    'disconnected' => AudioRouteEvent.outputDisconnected,
    _ => null,
  };

  @override
  Stream<AudioRouteEvent> get events =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller?.close();
    _controller = null;
  }
}
