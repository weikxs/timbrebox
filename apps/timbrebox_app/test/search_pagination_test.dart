import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

const _full = BuiltInSourceConfig.pageSize;

void main() {
  test('infinite scroll appends pages until a source is exhausted', () async {
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: _PagedCatalog([
        _page('p1', _full),
        _page('p2', _full),
        _page('p3', 3),
      ]),
    );

    await controller.search('x');
    expect(controller.searchResultsFor('audius'), hasLength(_full));
    expect(controller.hasMoreResults('audius'), isTrue);

    await controller.loadMore('audius');
    expect(controller.searchResultsFor('audius'), hasLength(_full * 2));
    expect(controller.hasMoreResults('audius'), isTrue);

    // Short (non-empty) page — a partial page still allows trying the next one.
    await controller.loadMore('audius');
    expect(controller.searchResultsFor('audius'), hasLength(_full * 2 + 3));
    expect(controller.hasMoreResults('audius'), isTrue);

    // The next page is empty → the source is now exhausted and stops.
    await controller.loadMore('audius');
    expect(controller.searchResultsFor('audius'), hasLength(_full * 2 + 3));
    expect(
      controller.hasMoreResults('audius'),
      isFalse,
      reason: 'an empty page exhausts the source',
    );

    await controller.loadMore('audius');
    expect(
      controller.searchResultsFor('audius'),
      hasLength(_full * 2 + 3),
      reason: 'an exhausted source stops requesting more',
    );
    controller.dispose();
  });

  test('a source without real pagination stops after one empty page', () async {
    // Only page one exists; the next page comes back empty.
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: _PagedCatalog([_page('only', _full)]),
    );

    await controller.search('x');
    expect(controller.hasMoreResults('audius'), isTrue);

    await controller.loadMore('audius');
    expect(controller.searchResultsFor('audius'), hasLength(_full));
    expect(controller.hasMoreResults('audius'), isFalse);
    controller.dispose();
  });

  test('duplicate refs across pages are appended only once', () async {
    final first = _page('d', _full);
    final second = [first.first, ..._page('e', _full - 1)];
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: _PagedCatalog([first, second, const []]),
    );

    await controller.search('x');
    await controller.loadMore('audius');
    expect(
      controller.searchResultsFor('audius'),
      hasLength(_full * 2 - 1),
      reason: 'a full page + (full-1) fresh, the duplicate is dropped',
    );
    controller.dispose();
  });

  test('a failed page is not requested again right away', () async {
    final catalog = _FailingMoreCatalog([_page('p1', _full)], retryable: true);
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: catalog,
    );
    addTearDown(controller.dispose);
    await controller.search('x');

    await controller.loadMore('audius');
    await controller.loadMore('audius');
    await controller.loadMore('audius');

    expect(catalog.moreCalls, 1);
    expect(controller.hasMoreResults('audius'), isTrue);
  });

  test('a page that cannot be retried ends the list', () async {
    final catalog = _FailingMoreCatalog([_page('p1', _full)], retryable: false);
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: catalog,
    );
    addTearDown(controller.dispose);
    await controller.search('x');

    await controller.loadMore('audius');

    expect(catalog.moreCalls, 1);
    expect(controller.hasMoreResults('audius'), isFalse);
  });
}

List<CatalogTrack> _page(String prefix, int count) => [
  for (var i = 0; i < count; i++) _track('$prefix$i'),
];

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: '公开流',
);

/// A grouped + paged catalog whose pages are supplied directly, so the
/// controller's pagination and dedup logic can be exercised without a network.
class _PagedCatalog
    implements MusicCatalog, GroupedMusicCatalog, PagedMusicCatalog {
  _PagedCatalog(this.pages);

  final List<List<CatalogTrack>> pages;

  @override
  Iterable<SourceDescriptor> get sources => [
    SourceDescriptor(
      id: 'audius',
      name: 'Audius',
      capabilities: const [SourceCapability.search, SourceCapability.streaming],
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
  }) async => pages.isEmpty ? const [] : pages.first;

  @override
  Stream<CatalogSearchBatch> searchGrouped(
    String query, {
    required CancellationToken cancellation,
  }) async* {
    yield CatalogSearchBatch(
      query: query,
      groups: [
        CatalogSearchGroup(
          sourceId: 'audius',
          sourceName: 'Audius',
          status: SourceSearchStatus.success,
          tracks: pages.isEmpty ? const [] : pages.first,
        ),
      ],
    );
  }

  @override
  Future<CatalogSearchGroup> searchMore(
    String sourceId,
    String query, {
    required int page,
    required CancellationToken cancellation,
  }) async {
    final index = page - 1;
    final tracks = index >= 0 && index < pages.length
        ? pages[index]
        : const <CatalogTrack>[];
    return CatalogSearchGroup(
      sourceId: sourceId,
      sourceName: 'Audius',
      status: tracks.isEmpty
          ? SourceSearchStatus.empty
          : SourceSearchStatus.success,
      tracks: tracks,
    );
  }
}

class _FailingMoreCatalog extends _PagedCatalog {
  _FailingMoreCatalog(super.pages, {required this.retryable});

  final bool retryable;
  var moreCalls = 0;

  @override
  Future<CatalogSearchGroup> searchMore(
    String sourceId,
    String query, {
    required int page,
    required CancellationToken cancellation,
  }) async {
    moreCalls++;
    return CatalogSearchGroup(
      sourceId: sourceId,
      sourceName: 'Audius',
      status: SourceSearchStatus.failure,
      tracks: const [],
      failure: SourceFailure('offline', retryable: retryable),
    );
  }
}
