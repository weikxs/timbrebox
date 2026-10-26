import 'dart:async';

import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  test('limits all-source search to two active sources', () async {
    var active = 0;
    var peak = 0;
    final registry = SourceRegistry([
      for (final id in ['youtube', 'bilibili', 'douyin'])
        _FakeSource(id, () async {
          active++;
          peak = active > peak ? active : peak;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
        }),
    ]);

    final results = await registry
        .searchAll(
          SearchRequest(query: 'lofi', cancellation: CancellationToken()),
        )
        .toList();

    expect(results, hasLength(3));
    expect(peak, SourceRegistry.maxConcurrentSearches);
    expect(results.every((result) => result.page != null), isTrue);
  });

  test('skips disabled sources and keeps a source failure local', () async {
    final registry = SourceRegistry([
      _FakeSource('youtube', () async {}),
      _FakeSource('bilibili', () => throw TimeoutException('slow upstream')),
      _FakeSource('douyin', () async {}),
    ]);
    registry.setEnabled('douyin', false);

    final results = await registry
        .searchAll(
          SearchRequest(query: 'ambient', cancellation: CancellationToken()),
        )
        .toList();

    expect(
      results.map((result) => result.sourceId),
      containsAll(['youtube', 'bilibili']),
    );
    expect(results.map((result) => result.sourceId), isNot(contains('douyin')));
    expect(
      results
          .singleWhere((result) => result.sourceId == 'bilibili')
          .failure
          ?.retryable,
      isTrue,
    );
  });

  test('does not start a search after cancellation', () async {
    var calls = 0;
    final registry = SourceRegistry([
      _FakeSource('youtube', () async => calls++),
    ]);
    final cancellation = CancellationToken()..cancel();

    final results = await registry
        .searchAll(SearchRequest(query: 'ambient', cancellation: cancellation))
        .toList();

    expect(results, isEmpty);
    expect(calls, 0);
  });

  test('returns one group per source with independent status', () async {
    final registry = SourceRegistry([
      _FakeSource('youtube', () async {}),
      _FakeSource('bilibili', () => throw TimeoutException('slow upstream')),
      _EmptySource('douyin'),
    ]);

    final batch = await registry.searchBatch(
      SearchRequest(query: 'ambient', cancellation: CancellationToken()),
    );

    expect(batch.groups, hasLength(3));
    expect(batch.groupFor('youtube')?.status, SourceSearchStatus.success);
    expect(batch.groupFor('bilibili')?.status, SourceSearchStatus.failure);
    expect(batch.groupFor('douyin')?.status, SourceSearchStatus.empty);
    expect(batch.groupFor('bilibili')?.failure?.retryable, isTrue);
  });

  test('reports each source as it finishes, in registration order', () async {
    final slow = Completer<void>();
    final registry = SourceRegistry([
      _FakeSource('youtube', () => slow.future),
      _FakeSource('bilibili', () async {}),
    ]);

    final snapshots = <List<String>>[];
    final done = registry
        .searchBatches(
          SearchRequest(query: 'ambient', cancellation: CancellationToken()),
        )
        .forEach(
          (batch) =>
              snapshots.add([for (final group in batch.groups) group.sourceId]),
        );
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // The fast source is reported while the slow one is still running.
    expect(snapshots, [
      ['bilibili'],
    ]);
    slow.complete();
    await done;
    expect(snapshots.last, ['youtube', 'bilibili']);
  });

  test('a whole batch lists sources in registration order', () async {
    final slow = Completer<void>();
    final registry = SourceRegistry([
      _FakeSource('youtube', () => slow.future),
      _FakeSource('bilibili', () async {}),
    ]);
    Timer(const Duration(milliseconds: 5), slow.complete);

    final batch = await registry.searchBatch(
      SearchRequest(query: 'ambient', cancellation: CancellationToken()),
    );

    expect(batch.groups.map((group) => group.sourceId), [
      'youtube',
      'bilibili',
    ]);
  });

  test('exposes capability-filtered descriptors without starting sources', () {
    final registry = SourceRegistry([
      _FakeSource('youtube', () async {}),
      _DiscoveryOnlySource('catalog'),
    ]);

    expect(
      registry.descriptorsFor(SourceCapability.search).map((item) => item.id),
      ['youtube'],
    );
    expect(registry.enabledDescriptors.map((item) => item.id), [
      'youtube',
      'catalog',
    ]);
  });
}

class _FakeSource implements MusicSource {
  _FakeSource(this.id, this._onSearch);

  final String id;
  final Future<void> Function() _onSearch;

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: id,
    name: id,
    capabilities: const [SourceCapability.search],
  );

  @override
  Future<SearchPage> search(SearchRequest request) async {
    await _onSearch();
    request.cancellation.throwIfCancelled();
    return SearchPage(
      items: [
        TrackSummary(
          ref: MediaRef(sourceId: id, itemId: request.query),
          title: request.query,
          artist: 'Test artist',
        ),
      ],
    );
  }
}

class _EmptySource extends _FakeSource {
  _EmptySource(String id) : super(id, () async {});

  @override
  Future<SearchPage> search(SearchRequest request) async =>
      const SearchPage(items: []);
}

class _DiscoveryOnlySource implements MusicSource {
  _DiscoveryOnlySource(this.id);
  final String id;

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: id,
    name: id,
    capabilities: const [SourceCapability.discovery],
  );

  @override
  Future<SearchPage> search(SearchRequest request) async =>
      const SearchPage(items: []);
}
