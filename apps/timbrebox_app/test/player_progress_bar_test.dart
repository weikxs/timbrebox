import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/widgets/player_progress_bar.dart';

import 'support/test_player_engine.dart';

void main() {
  testWidgets('shows elapsed and total time for the current track', (
    tester,
  ) async {
    final controller = AppController(engine: TestPlayerEngine());
    await controller.play(_track('x'));

    await _pump(tester, controller);

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('03:00'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('renders an idle bar with no track selected', (tester) async {
    final controller = AppController(engine: TestPlayerEngine());

    await _pump(tester, controller);

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('--:--'), findsWidgets);
    controller.dispose();
  });
}

Future<void> _pump(WidgetTester tester, AppController controller) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => PlayerProgressBar(controller: controller),
          ),
        ),
      ),
    );

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: '公开流',
);
