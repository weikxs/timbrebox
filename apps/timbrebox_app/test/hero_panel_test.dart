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

  testWidgets('the spinning record repaints only its own layer', (
    tester,
  ) async {
    await pumpPlaying(tester);
    await tester.pump(const Duration(milliseconds: 16));
    final page = _boundaryAbove(tester.renderObject(find.byType(HeroPanel)));
    final pagePaints = _paints(page);

    for (var frame = 0; frame < _frames; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // The page holding the frosted panel is not repainted while the record
    // turns; only the record's own layer is.
    final pageRepaints = _paints(page) - pagePaints;
    final recordPaints = _paints(
      tester.renderObject<RenderRepaintBoundary>(record().first),
    );
    debugPrint(
      'repaints over $_frames frames: page=$pageRepaints record=$recordPaints',
    );
    expect(pageRepaints, 0);
    expect(recordPaints, greaterThanOrEqualTo(_frames));
  });

  testWidgets('the record stops spinning while the app is in the background', (
    tester,
  ) async {
    await pumpPlaying(tester);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });
}

const _frames = 30;

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
