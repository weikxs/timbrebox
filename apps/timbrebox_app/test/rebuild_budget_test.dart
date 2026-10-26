import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/data/music_catalog.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/timbrebox_app.dart';

/// Playback position ticks arrive 10-50 times a second. Only the progress bar
/// and the time labels may rebuild for them — not the app, the shell, the
/// player chrome or the result rows.
void main() {
  testWidgets('position ticks rebuild only the progress widgets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = _TickingEngine();
    final controller = AppController(engine: engine, catalog: _Catalog());
    addTearDown(controller.dispose);
    await tester.pumpWidget(TimbreBoxApp(controller: controller));

    await tester.enterText(find.byType(EditableText).first, 'night');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await controller.play(controller.searchResults.first);
    await tester.pump();
    expect(find.text('Track 0'), findsWidgets);

    final builds = <String, int>{};
    debugOnRebuildDirtyWidget = (element, _) {
      final name = element.widget.runtimeType.toString();
      builds[name] = (builds[name] ?? 0) + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    for (var tick = 1; tick <= _ticks; tick++) {
      engine.emit(Duration(milliseconds: tick * 200));
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = null;

    // Reported for the performance log; asserted below.
    debugPrint(
      'builds over $_ticks ticks: '
      'MaterialApp=${builds['MaterialApp'] ?? 0} '
      'Scaffold=${builds['Scaffold'] ?? 0} '
      'MiniPlayer=${builds['MiniPlayer'] ?? 0} '
      '_TrackRow=${builds['_TrackRow'] ?? 0} '
      'PlayerProgressBar=${builds['PlayerProgressBar'] ?? 0} '
      'Slider=${builds['Slider'] ?? 0}',
    );
    expect(builds['MaterialApp'] ?? 0, 0);
    expect(builds['Scaffold'] ?? 0, 0);
    expect(builds['MiniPlayer'] ?? 0, 0);
    expect(builds['_TrackRow'] ?? 0, 0);
    // The progress bar itself still follows every tick.
    expect(builds['Slider'] ?? 0, greaterThanOrEqualTo(_ticks));
    expect(controller.position, const Duration(milliseconds: _ticks * 200));
    expect(find.textContaining('00:10'), findsWidgets);
  });
}

const _ticks = 50;

final class _TickingEngine
    implements PlayerEngine, PlaybackProgressEvents, PauseReleaseConfig {
  final _positions = StreamController<Duration>.broadcast(sync: true);

  void emit(Duration value) => _positions.add(value);

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<Duration> get durations => const Stream.empty();

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> load(StreamCandidate candidate) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> release() async {}

  @override
  Future<void> setReleaseAfterPause(bool enabled) async {}
}

class _Catalog implements MusicCatalog {
  @override
  Iterable<SourceDescriptor> get sources => [
    SourceDescriptor(
      id: 'audius',
      name: 'Audius',
      capabilities: [SourceCapability.search, SourceCapability.streaming],
    ),
  ];

  @override
  bool isEnabled(String sourceId) => true;

  @override
  void setEnabled(String sourceId, bool value) {}

  @override
  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  }) async => [
    for (var index = 0; index < 30; index++)
      CatalogTrack(
        id: 'track-$index',
        title: 'Track $index',
        artist: 'Artist',
        sourceId: 'audius',
        sourceName: 'Audius',
        duration: const Duration(minutes: 3),
        quality: 'public',
      ),
  ];
}
