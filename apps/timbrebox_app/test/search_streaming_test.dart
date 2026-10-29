import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

/// Search shows each source's results as soon as that source answers instead
/// of waiting for the slowest one, and keeps the sources in a stable order.
void main() {
  test('a fast source shows before a slow one finishes', () async {
    final slow = _GatedSource('slow');
    final fast = _GatedSource('fast');
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: BuiltInMusicCatalog([slow, fast]),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final search = controller.search('night');
    fast.answer();
    await pumpEventQueue();

    expect(controller.isSearching, isTrue);
    expect(controller.searchResultsFor('fast').single.title, 'fast night');
    expect(controller.searchResultsFor('slow'), isEmpty);
    expect(controller.isSearchingSource('slow'), isTrue);
    expect(controller.isSearchingSource('fast'), isFalse);
    expect(notifications, greaterThanOrEqualTo(2)); // started + fast arrived

    slow.answer();
    await search;

    expect(controller.isSearching, isFalse);
    expect(controller.searchResults.map((track) => track.sourceId), [
      'slow',
      'fast',
    ]);
    expect(controller.searchError, isNull);
  });

  test('a newer search drops a slower answer to the old one', () async {
    final slow = _GatedSource('slow');
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: BuiltInMusicCatalog([slow]),
    );
    addTearDown(controller.dispose);

    final first = controller.search('old');
    final second = controller.search('new');
    slow.answer();
    await Future.wait([first, second]);

    expect(controller.searchResults.single.title, 'slow new');
  });
}

final class _GatedSource implements CatalogSource {
  _GatedSource(this.id);

  final String id;
  final _gate = Completer<void>();

  void answer() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: id,
    name: id,
    capabilities: const [SourceCapability.search],
  );

  @override
  Future<SearchPage> search(SearchRequest request) async {
    await _gate.future;
    return SearchPage(
      items: [
        TrackSummary(
          ref: MediaRef(sourceId: id, itemId: request.query),
          title: '$id ${request.query}',
          artist: 'Artist',
        ),
      ],
    );
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) => CatalogTrack(
    id: summary.ref.itemId,
    title: summary.title,
    artist: summary.artist,
    sourceId: id,
    sourceName: id,
    duration: Duration.zero,
    quality: 'test',
  );

  @override
  Future<ResolvedStream> resolve(StreamRequest request) =>
      throw UnimplementedError();
}
