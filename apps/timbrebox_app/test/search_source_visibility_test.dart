import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/views/search_view.dart';

import 'support/test_player_engine.dart';

void main() {
  late _Catalog catalog;
  late AppController controller;
  setUp(() {
    catalog = _Catalog();
    controller = AppController(engine: TestPlayerEngine(), catalog: catalog);
  });
  tearDown(() async {
    await catalog.close();
    controller.dispose();
  });
  List<String> visible() => controller.visibleSearchSources
      .map((s) => s.id.replaceFirst('fixture_', ''))
      .toList();

  test(
    'only completed empty sources hide; pending and successful sources remain',
    () async {
      final pending = controller.search('first');
      expect(visible(), ['a', 'b']);
      catalog.emit('first', [group('a')]);
      await pumpEventQueue();
      expect(visible(), ['b']);
      expect(controller.isSearchingSource('fixture_b'), isTrue);
      catalog.emit('first', [group('a'), group('b', result: true)]);
      await catalog.finish('first');
      await pending;
      expect(visible(), ['b']);
      expect(controller.searchableSources, hasLength(2));
      expect(controller.sourceEnabled('fixture_a'), isTrue);
    },
  );

  test(
    'new query restores hidden sources and clears old results before notifying',
    () async {
      final first = controller.search('first');
      catalog.emit('first', [group('a'), group('b', result: true)]);
      await catalog.finish('first');
      await first;
      final snapshots = <List<String>>[];
      final counts = <int>[];
      controller.addListener(() {
        snapshots.add(visible());
        counts.add(controller.searchResults.length);
      });
      final next = controller.search('next');
      expect(snapshots.first, ['a', 'b']);
      expect(counts.first, 0);
      catalog.emit('next', [group('a', result: true), group('b')]);
      await catalog.finish('next');
      await next;
      expect(visible(), ['a']);
      await controller.search('');
      expect(visible(), ['a', 'b']);
    },
  );

  test(
    'failed source stays visible rather than being classified as empty',
    () async {
      final pending = controller.search('first');
      catalog.emit('first', [
        group('a', failure: true),
        group('b', result: true),
      ]);
      await catalog.finish('first');
      await pending;
      expect(visible(), ['a', 'b']);
      expect(controller.searchFailureFor('fixture_a'), isNotNull);
    },
  );

  test(
    'empty source still hides when another source failed and no source matched',
    () async {
      final pending = controller.search('first');
      catalog.emit('first', [group('a'), group('b', failure: true)]);
      await catalog.finish('first');
      await pending;
      expect(visible(), ['b']);
      expect(controller.searchError, isNotNull);
    },
  );

  test('ungrouped empty results hide tabs without disabling sources', () async {
    final flat = AppController(
      engine: TestPlayerEngine(),
      catalog: _FlatCatalog(),
    );
    addTearDown(flat.dispose);
    await flat.search('nothing');
    expect(flat.visibleSearchSources, isEmpty);
    expect(flat.searchableSources, hasLength(2));
    await flat.search('');
    expect(flat.visibleSearchSources, hasLength(2));
  });

  test('an ungrouped request failure does not hide sources as empty', () async {
    final flat = AppController(
      engine: TestPlayerEngine(),
      catalog: _FlatCatalog(fail: true),
    );
    addTearDown(flat.dispose);
    await flat.search('offline');
    expect(flat.searchError, isNotNull);
    expect(flat.visibleSearchSources, hasLength(2));
  });

  testWidgets('selected empty tab falls back to the source with results', (
    tester,
  ) async {
    final pending = controller.search('first');
    await tester.pumpWidget(_view(controller));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Source a'));
    await tester.pump();
    catalog.emit('first', [group('a'), group('b', result: true)]);
    unawaited(catalog.finish('first'));
    await tester.pump();
    await pending;
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, 'Source a'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Source b'), findsOneWidget);
    expect(find.text('Track b'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all empty displays no matches, not disabled-source instructions',
    (tester) async {
      await tester.pumpWidget(_view(controller));
      final pending = controller.search('first');
      catalog.emit('first', [group('a'), group('b')]);
      unawaited(catalog.finish('first'));
      await tester.pump();
      await pending;
      expect(find.widgetWithText(OutlinedButton, 'Source a'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Source b'), findsNothing);
      expect(find.text('没有找到匹配内容'), findsWidgets);
      expect(find.text('已启用的音源均未找到匹配内容，请换个关键词。'), findsOneWidget);
      expect(find.text('没有可用的搜索来源'), findsNothing);
      expect(find.text('选择可用音源'), findsNothing);
    },
  );

  testWidgets(
    'a failed source keeps its error notice alongside a successful source',
    (tester) async {
      await tester.pumpWidget(_view(controller));
      final pending = controller.search('first');
      catalog.emit('first', [
        group('a', failure: true),
        group('b', result: true),
      ]);
      unawaited(catalog.finish('first'));
      await tester.pump();
      await pending;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Source a'));
      await tester.pump();
      expect(find.text('Source a 暂时不可用'), findsOneWidget);
      expect(find.text('Offline fixture'), findsOneWidget);
    },
  );
}

Widget _view(AppController controller) => MaterialApp(
  home: Scaffold(
    body: AnimatedBuilder(
      animation: controller,
      builder: (_, _) => SearchView(controller: controller),
    ),
  ),
);

CatalogSearchGroup group(
  String id, {
  bool result = false,
  bool failure = false,
}) => CatalogSearchGroup(
  sourceId: 'fixture_$id',
  sourceName: 'Source $id',
  status: failure
      ? SourceSearchStatus.failure
      : result
      ? SourceSearchStatus.success
      : SourceSearchStatus.empty,
  failure: failure
      ? const SourceFailure('Offline fixture', retryable: true)
      : null,
  tracks: result
      ? [
          CatalogTrack(
            id: 'track-$id',
            title: 'Track $id',
            artist: 'Fixture',
            sourceId: 'fixture_$id',
            sourceName: 'Source $id',
            duration: const Duration(seconds: 120),
            quality: 'test',
          ),
        ]
      : const [],
);

class _FlatCatalog implements MusicCatalog {
  _FlatCatalog({this.fail = false});
  final bool fail;
  final _delegate = _Catalog();
  @override
  Iterable<SourceDescriptor> get sources => _delegate.sources;
  @override
  bool isEnabled(String sourceId) => true;
  @override
  void setEnabled(String sourceId, bool enabled) {}
  @override
  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  }) async {
    if (fail) throw StateError('Synthetic protocol failure');
    return [];
  }
}

class _Catalog implements MusicCatalog, GroupedMusicCatalog {
  final streams = <String, StreamController<CatalogSearchBatch>>{};
  @override
  Iterable<SourceDescriptor> get sources => [
    for (final id in ['a', 'b'])
      SourceDescriptor(
        id: 'fixture_$id',
        name: 'Source $id',
        capabilities: const [SourceCapability.search],
      ),
  ];
  @override
  bool isEnabled(String sourceId) => true;
  @override
  void setEnabled(String sourceId, bool enabled) {}
  @override
  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  }) async => [];
  @override
  Stream<CatalogSearchBatch> searchGrouped(
    String query, {
    required CancellationToken cancellation,
  }) => (streams[query] ??= StreamController<CatalogSearchBatch>()).stream;
  void emit(String query, List<CatalogSearchGroup> groups) =>
      streams[query]!.add(CatalogSearchBatch(query: query, groups: groups));
  Future<void> finish(String query) => streams[query]!.close();
  Future<void> close() async {
    for (final stream in streams.values) {
      if (!stream.isClosed) await stream.close();
    }
  }
}
