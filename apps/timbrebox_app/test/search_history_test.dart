import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/data/music_catalog.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/search_history_store.dart';

import 'support/test_player_engine.dart';

class _MemorySearchHistoryStore implements SearchHistoryStore {
  List<String> saved = const [];

  @override
  Future<List<String>> load() async => saved;

  @override
  Future<void> save(List<String> queries) async => saved = List.of(queries);
}

class _EmptyCatalog implements MusicCatalog {
  @override
  Iterable<SourceDescriptor> get sources => [
    SourceDescriptor(
      id: 'audius',
      name: 'Audius',
      capabilities: [SourceCapability.search],
    ),
  ];

  @override
  bool isEnabled(String sourceId) => true;

  @override
  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  }) async => const [];

  @override
  void setEnabled(String sourceId, bool value) {}
}

AppController _controller(SearchHistoryStore store) => AppController(
  engine: TestPlayerEngine(),
  catalog: _EmptyCatalog(),
  searchHistoryStore: store,
);

void main() {
  test('records searches, de-dupes, most-recent-first', () async {
    final store = _MemorySearchHistoryStore();
    final controller = _controller(store);
    addTearDown(controller.dispose);

    await controller.search('alpha');
    await controller.search('bravo');
    await controller.search('ALPHA'); // same query (case-insensitive) → front

    expect(controller.searchHistory, ['ALPHA', 'bravo']);
    expect(store.saved, ['ALPHA', 'bravo']);
  });

  test('clearSearchHistory empties and persists', () async {
    final store = _MemorySearchHistoryStore();
    final controller = _controller(store);
    addTearDown(controller.dispose);

    await controller.search('alpha');
    controller.clearSearchHistory();

    expect(controller.searchHistory, isEmpty);
    expect(store.saved, isEmpty);
  });

  test('restores history from the store on launch', () async {
    final store = _MemorySearchHistoryStore()..saved = ['x', 'y'];
    final controller = _controller(store);
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(controller.searchHistory, ['x', 'y']);
  });
}
