import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'audio_route_monitor.dart';

/// Desktop (Windows / Linux) audio-route monitor driven by media_kit's live
/// `audio-device-list` (libmpv observes it): a device appearing → connected,
/// one leaving → disconnected.
///
/// Less selective than a default-output listener — it reacts to any output
/// device change, not only the active one — which is an acceptable trade-off on
/// platforms without a lightweight default-device API. macOS uses the precise
/// CoreAudio path instead.
class MediaKitAudioRouteMonitor implements AudioRouteMonitor {
  MediaKitAudioRouteMonitor(this._deviceList);

  final Stream<List<AudioDevice>> _deviceList;

  final StreamController<AudioRouteEvent> _controller =
      StreamController<AudioRouteEvent>.broadcast();
  StreamSubscription<List<AudioDevice>>? _subscription;
  int? _lastCount;

  @override
  Future<void> start() async {
    _subscription = _deviceList.listen((devices) {
      final count = devices.length;
      final previous = _lastCount;
      _lastCount = count;
      if (previous == null) return; // First snapshot is just the baseline.
      if (count > previous) {
        _controller.add(AudioRouteEvent.outputConnected);
      } else if (count < previous) {
        _controller.add(AudioRouteEvent.outputDisconnected);
      }
    });
  }

  @override
  Stream<AudioRouteEvent> get events => _controller.stream;

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}
