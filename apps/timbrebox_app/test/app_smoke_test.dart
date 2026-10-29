import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/timbrebox_app.dart';
import 'package:timbrebox_app/app/widgets/track_list.dart';

import 'support/test_player_engine.dart';

void main() {
  void useDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(974, 614);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget testApp() => TimbreBoxApp(
    controller: AppController(engine: TestPlayerEngine(), catalog: _Catalog()),
  );

  testWidgets('desktop shell presents the primary listening workflow', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(testApp());

    expect(find.text('TimbreBox'), findsOneWidget);
    expect(find.text('接下来'), findsOneWidget);
    expect(find.text('为你策展'), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);

    expect(find.text('播放'), findsOneWidget);
  });

  testWidgets('settings remain available from the desktop navigation', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(testApp());

    await tester.tap(find.text('设置'));
    await tester.pump();

    await tester.tap(find.text('音源'));
    await tester.pump();
    expect(find.text('内置音源'), findsOneWidget);
    expect(find.text('Audius'), findsOneWidget);
  });

  testWidgets('compact layouts expose navigation without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(testApp());

    await tester.tap(find.byTooltip('切换页面'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('我的音乐'), findsOneWidget);
  });

  testWidgets('global search opens source tabs without mixing results', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(testApp());

    await tester.enterText(find.byType(EditableText).first, '夜窗');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(find.text('“夜窗”'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SliverTrackList),
        matching: find.text('夜窗'),
      ),
      findsOneWidget,
    );
    expect(find.text('Timbre Study · Audius'), findsOneWidget);
    expect(find.text('Radio Browser'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SliverTrackList),
        matching: find.text('Night Radio'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Radio Browser'));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(SliverTrackList),
        matching: find.text('Night Radio'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SliverTrackList),
        matching: find.text('夜窗'),
      ),
      findsNothing,
    );
  });

  testWidgets('a source result can be selected and starts playback', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: _Catalog(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(TimbreBoxApp(controller: controller));

    await tester.enterText(find.byType(EditableText).first, '夜窗');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    await tester.tap(find.text('夜窗').last);
    await tester.pump();

    expect(controller.currentTrack?.title, '夜窗');
    expect(controller.isPlaying, isTrue);
  });

  testWidgets('section labels follow the Chinese interface on every page', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(testApp());
    const english = [
      'BROWSE',
      'YOUR SPACE',
      'LOCAL LIBRARY',
      'TRENDING',
      'YOUR LIBRARY',
      'OFFLINE',
      'UP NEXT',
      'SETTINGS',
    ];
    void expectNoEnglishLabels() {
      for (final label in english) {
        expect(find.text(label), findsNothing, reason: label);
      }
    }

    expect(find.text('浏览'), findsOneWidget);
    expect(find.text('本地曲库'), findsOneWidget);
    expectNoEnglishLabels();
    for (final page in ['热门库', '我的音乐', '本地音乐', '最近播放', '设置']) {
      await tester.tap(find.text(page).first);
      await tester.pump();
      expectNoEnglishLabels();
    }
  });
}

class _Catalog implements MusicCatalog {
  var enabled = true;

  @override
  Iterable<SourceDescriptor> get sources => [
    SourceDescriptor(
      id: 'audius',
      name: 'Audius',
      capabilities: [SourceCapability.search, SourceCapability.streaming],
    ),
    SourceDescriptor(
      id: 'radio_browser',
      name: 'Radio Browser',
      capabilities: [SourceCapability.search, SourceCapability.streaming],
    ),
  ];

  @override
  bool isEnabled(String sourceId) => sourceId == 'audius' && enabled;

  @override
  void setEnabled(String sourceId, bool value) => enabled = value;

  @override
  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  }) async => [
    const CatalogTrack(
      id: 'night-window',
      title: '夜窗',
      artist: 'Timbre Study',
      sourceId: 'audius',
      sourceName: 'Audius',
      duration: Duration(minutes: 3, seconds: 31),
      quality: '公开流',
    ),
    const CatalogTrack(
      id: 'night-radio',
      title: 'Night Radio',
      artist: 'Global FM',
      sourceId: 'radio_browser',
      sourceName: 'Radio Browser',
      duration: Duration.zero,
      quality: '直播电台',
    ),
  ];
}
