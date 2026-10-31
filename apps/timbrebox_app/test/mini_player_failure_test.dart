import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/widgets/mini_player.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';

const track = CatalogTrack(
  id: 'fixture',
  title: 'Fixture',
  artist: 'Fixture',
  sourceId: 'fixture',
  sourceName: 'Fixture',
  duration: Duration(seconds: 120),
  quality: 'standard',
);
void main() {
  Future<void> mount(WidgetTester tester, AppController controller) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (_, _) => MiniPlayer(controller: controller),
            ),
          ),
        ),
      );
  testWidgets(
    'mini player shows loading and exposes cancellation instead of an ordinary play button',
    (tester) async {
      final engine = _Engine();
      final controller = AppController(engine: engine);
      addTearDown(controller.dispose);
      await mount(tester, controller);
      final load = controller.play(track);
      await tester.pump();
      expect(find.byKey(const ValueKey('mini-player-loading')), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.cancel_outlined));
      await tester.pump();
      engine.gate.complete();
      await load;
      await tester.pump();
      expect(controller.isPlaying, false);
      expect(find.byKey(const ValueKey('mini-player-loading')), findsNothing);
    },
  );
  testWidgets(
    'mini player keeps a failed source message visible beside the controls',
    (tester) async {
      final engine = _Engine()..fail = true;
      final controller = AppController(engine: engine);
      addTearDown(controller.dispose);
      await mount(tester, controller);
      final load = controller.play(track);
      engine.gate.complete();
      await load;
      await tester.pump();
      expect(find.byKey(const ValueKey('mini-player-error')), findsOneWidget);
      expect(find.text('Synthetic safe source failure'), findsOneWidget);
      expect(controller.playbackDiagnostics['errorCode'], 'content_unverified');
      expect(controller.isPlaying, false);
    },
  );
}

class _Engine implements PlayerEngine {
  final gate = Completer<void>();
  bool fail = false;
  @override
  Future<void> load(StreamCandidate candidate) async {
    await gate.future;
    if (fail) {
      throw const SourceException(
        'Synthetic safe source failure',
        retryable: false,
        code: 'content_unverified',
      );
    }
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> release() async {}
}
