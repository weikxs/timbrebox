import 'dart:async';

import 'package:audio_session/audio_session.dart';

import 'audio_route_monitor.dart';

/// Mobile (iOS / Android) audio-route monitor via the `audio_session` plugin.
///
/// "Becoming noisy" means the active output was removed (Bluetooth/headphones
/// unplugged) → disconnected; an output device appearing → connected.
class SessionAudioRouteMonitor implements AudioRouteMonitor {
  final StreamController<AudioRouteEvent> _controller =
      StreamController<AudioRouteEvent>.broadcast();
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;

  @override
  Future<void> start() async {
    final session = await AudioSession.instance;
    _noisySub = session.becomingNoisyEventStream.listen(
      (_) => _controller.add(AudioRouteEvent.outputDisconnected),
    );
    _devicesSub = session.devicesChangedEventStream.listen((event) {
      if (event.devicesAdded.any((device) => device.isOutput)) {
        _controller.add(AudioRouteEvent.outputConnected);
      }
    });
  }

  @override
  Stream<AudioRouteEvent> get events => _controller.stream;

  @override
  Future<void> dispose() async {
    await _noisySub?.cancel();
    await _devicesSub?.cancel();
    await _controller.close();
  }
}
