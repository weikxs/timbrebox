import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/timbrebox_app.dart';
import 'package:timbrebox_app/app/widgets/hero_panel.dart';

import 'support/test_player_engine.dart';

const _track = CatalogTrack(
  id: 'a',
  title: 'Track a',
  artist: 'Artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: Duration(minutes: 3),
  quality: 'public',
);

void main() {
  Future<AppController> pumpPlaying(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(engine: TestPlayerEngine());
    addTearDown(controller.dispose);
    await controller.play(_track);
    await tester.pumpWidget(TimbreBoxApp(controller: controller));
    expect(controller.isPlaying, isTrue);
    return controller;
  }

  Finder record() => find.ancestor(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_VinylPainter',
    ),
    matching: find.byType(RepaintBoundary),
  );

  /// Pumps one second of 60 Hz vsyncs and returns how many times the
  /// record's layer was painted.
  Future<int> recordPaintsOverOneSecond(WidgetTester tester) async {
    final layer = tester.renderObject<RenderRepaintBoundary>(record().first);
    final before = _paints(layer);
    for (var frame = 0; frame < _vsyncsPerSecond; frame++) {
      await tester.pump(_vsync);
    }
    return _paints(layer) - before;
  }

  testWidgets('the spinning record repaints only its own layer', (
    tester,
  ) async {
    await pumpPlaying(tester);
    await tester.pump(_vsync);
    final page = _boundaryAbove(tester.renderObject(find.byType(HeroPanel)));
    final pagePaints = _paints(page);

    final recordPaints = await recordPaintsOverOneSecond(tester);

    // The page holding the frosted panel is not repainted while the record
    // turns; only the record's own layer is.
    final pageRepaints = _paints(page) - pagePaints;
    debugPrint('repaints over 1 s: page=$pageRepaints record=$recordPaints');
    expect(pageRepaints, 0);
    expect(recordPaints, greaterThan(0));
  });

  testWidgets('the record turns at about 6 frames a second, not 60', (
    tester,
  ) async {
    await pumpPlaying(tester);
    await tester.pump(_vsync);

    final recordPaints = await recordPaintsOverOneSecond(tester);

    expect(recordPaints, inInclusiveRange(5, 7));
  });

  testWidgets('no frames are requested between two turns of the record', (
    tester,
  ) async {
    await pumpPlaying(tester);
    await tester.pump(_vsync);
    // Let a turn land, then draw it.
    await tester.pump(const Duration(milliseconds: 170));
    await tester.pump(_vsync);

    // Until the next turn is due, nothing asks the engine for a frame.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the record stops spinning while the app is in the background', (
    tester,
  ) async {
    await pumpPlaying(tester);
    await tester.pump(_vsync);
    expect(await recordPaintsOverOneSecond(tester), greaterThan(0));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(_vsync);
    expect(await recordPaintsOverOneSecond(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_vsync);
    expect(await recordPaintsOverOneSecond(tester), greaterThan(0));
  });

  testWidgets('the record stops spinning when playback pauses', (tester) async {
    final controller = await pumpPlaying(tester);
    await tester.pump(_vsync);

    await controller.togglePlayback();
    await tester.pump(_vsync);
    expect(controller.isPlaying, isFalse);

    expect(await recordPaintsOverOneSecond(tester), 0);
  });
}

const _vsync = Duration(milliseconds: 16);
const _vsyncsPerSecond = 63; // 63 x 16 ms ~ 1 s

RenderObject _boundaryAbove(RenderObject object) {
  var current = object.parent;
  while (current != null && !current.isRepaintBoundary) {
    current = current.parent;
  }
  return current!;
}

int _paints(RenderObject object) {
  if (object is! RenderRepaintBoundary) return -1;
  return object.debugSymmetricPaintCount + object.debugAsymmetricPaintCount;
}
