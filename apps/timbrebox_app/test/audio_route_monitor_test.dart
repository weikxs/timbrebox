import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/audio_route_monitor.dart';

import 'support/test_player_engine.dart';

class _FakeRouteMonitor implements AudioRouteMonitor {
  final _controller = StreamController<AudioRouteEvent>.broadcast();

  void emit(AudioRouteEvent event) => _controller.add(event);

  @override
  Future<void> start() async {}
  @override
  Stream<AudioRouteEvent> get events => _controller.stream;
  @override
  Future<void> dispose() async => _controller.close();
}

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: '待解析',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('pauses on disconnect and resumes on reconnect', () async {
    final monitor = _FakeRouteMonitor();
    final controller =
        AppController(engine: TestPlayerEngine(), routeMonitor: monitor);
    addTearDown(controller.dispose);
    await controller.play(_track('alpha'));
    expect(controller.isPlaying, isTrue);

    monitor.emit(AudioRouteEvent.outputDisconnected);
    await _settle();
    expect(controller.isPlaying, isFalse, reason: 'disconnect should pause');

    monitor.emit(AudioRouteEvent.outputConnected);
    await _settle();
    expect(controller.isPlaying, isTrue, reason: 'reconnect should resume');
  });

  test('does not auto-resume playback the user paused after a disconnect',
      () async {
    final monitor = _FakeRouteMonitor();
    final controller =
        AppController(engine: TestPlayerEngine(), routeMonitor: monitor);
    addTearDown(controller.dispose);
    await controller.play(_track('alpha'));

    monitor.emit(AudioRouteEvent.outputDisconnected);
    await _settle();
    expect(controller.isPlaying, isFalse);

    // The user takes over: resume, then pause again — clears the auto flag.
    await controller.togglePlayback(); // resume
    await controller.togglePlayback(); // pause
    expect(controller.isPlaying, isFalse);

    monitor.emit(AudioRouteEvent.outputConnected);
    await _settle();
    expect(controller.isPlaying, isFalse, reason: 'must not fight the user');
  });

  test('does not resume when nothing was playing at disconnect', () async {
    final monitor = _FakeRouteMonitor();
    final controller =
        AppController(engine: TestPlayerEngine(), routeMonitor: monitor);
    addTearDown(controller.dispose);

    monitor.emit(AudioRouteEvent.outputDisconnected);
    await _settle();
    monitor.emit(AudioRouteEvent.outputConnected);
    await _settle();
    expect(controller.isPlaying, isFalse);
  });
}
