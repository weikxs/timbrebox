import 'dart:io';

import 'native_audio_route_monitor.dart';
import 'session_audio_route_monitor.dart';

/// A change in the audio **output route** — a Bluetooth headset or wired
/// headphones connecting or disconnecting.
enum AudioRouteEvent {
  /// The active output device was removed (Bluetooth/headphones disconnected).
  outputDisconnected,

  /// An output device became available (Bluetooth/headphones connected).
  outputConnected,
}

/// Watches the OS for audio-output route changes so playback can pause when the
/// active device (Bluetooth/headphones) disconnects and resume when it returns.
///
/// Implementations are per-platform (native CoreAudio / IMMDevice / MPRIS-side
/// on desktop, `audio_session` on mobile); the factory picks one.
abstract interface class AudioRouteMonitor {
  Future<void> start();
  Stream<AudioRouteEvent> get events;
  Future<void> dispose();
}

/// No-op monitor for platforms without an implementation.
class NoopAudioRouteMonitor implements AudioRouteMonitor {
  const NoopAudioRouteMonitor();

  @override
  Future<void> start() async {}

  @override
  Stream<AudioRouteEvent> get events => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

/// Picks the audio-route monitor for the current platform. Desktop platforms
/// use a native ([EventChannel]-backed) monitor; mobile and anything else fall
/// back to a no-op (route-aware pause/resume is simply off there for now).
AudioRouteMonitor createAudioRouteMonitor() {
  // macOS uses a precise CoreAudio default-output listener over an EventChannel.
  if (Platform.isMacOS) return NativeAudioRouteMonitor();
  if (Platform.isAndroid || Platform.isIOS) {
    return SessionAudioRouteMonitor();
  }
  // Windows / Linux are wired in TimbreBoxApp via a media_kit device-list
  // monitor (needs the player's stream), so they fall back to no-op here.
  return const NoopAudioRouteMonitor();
}
