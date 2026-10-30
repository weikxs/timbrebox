import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/views/hot_view.dart';

import 'support/test_player_engine.dart';

const _stations = '''
[{"stationuuid":"station-1","name":"Demo Radio","countrycode":"TW",
  "url_resolved":"https://radio.example/demo"}]
''';

void main() {
  late List<Uri> asked;

  AppController makeController() {
    asked = [];
    return AppController(
      engine: TestPlayerEngine(),
      catalog: BuiltInMusicCatalog([
        RadioBrowserCatalogSource(
          readJson: (uri, _) async {
            asked.add(uri);
            return _stations;
          },
        ),
      ]),
    );
  }

  test('a radio category lists the top stations of its region', () async {
    final controller = makeController();

    await controller.loadCategory('radio_tw', radioCountry: 'TW');

    expect(asked.single.queryParameters['countrycode'], 'TW');
    expect(controller.categoryTracks('radio_tw').single.title, 'Demo Radio');
  });

  test('the worldwide radio category asks for no region', () async {
    final controller = makeController();

    await controller.loadCategory('radio_world', radioCountry: '');

    expect(asked.single.queryParameters.containsKey('countrycode'), isFalse);
    expect(controller.categoryTracks('radio_world'), hasLength(1));
  });

  testWidgets('the hot library offers Chinese radio by region', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = makeController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HotView(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.text('中文电台 · Radio Browser'), findsOneWidget);
    await tester.tap(find.text('台湾'));
    await tester.pumpAndSettle();

    expect(asked.single.queryParameters['countrycode'], 'TW');
    expect(find.text('Demo Radio'), findsOneWidget);
  });
}
