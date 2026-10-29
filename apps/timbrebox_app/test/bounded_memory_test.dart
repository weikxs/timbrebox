import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/known_tracks.dart';

import 'support/test_player_engine.dart';

/// Every search used to add its results to maps that were never trimmed,
/// so a long session kept every track it had ever seen.
void main() {
  test('a bounded cache drops the least recently used entry', () {
    final cache = BoundedCache<String, int>(capacity: 3);
    cache['a'] = 1;
    cache['b'] = 2;
    cache['c'] = 3;
    expect(cache['a'], 1); // a is now the most recent.

    cache['d'] = 4;

    expect(cache.containsKey('b'), isFalse);
    expect([cache['a'], cache['c'], cache['d']], [1, 3, 4]);
    expect(cache.length, 3);
  });

  test('known tracks keep pinned ones and only a few others', () {
    final pinned = <String>{'tb://audius/keep'};
    final known = KnownTracks(spare: 10, pinned: () => pinned);
    known['tb://audius/keep'] = _track('keep');
    for (var index = 0; index < 100; index++) {
      known['tb://audius/t$index'] = _track('t$index');
    }

    expect(known['tb://audius/keep']?.id, 'keep');
    expect(known['tb://audius/t99']?.id, 't99');
    expect(known['tb://audius/t0'], isNull);
    expect(known.length, lessThanOrEqualTo(1 + 2 * 10));
  });

  test(
    'a long session keeps its queue and favorites, not every result',
    () async {
      final controller = AppController(
        engine: TestPlayerEngine(),
        catalog: _ManyResults(),
      );
      addTearDown(controller.dispose);

      await controller.search('first');
      final first = controller.searchResults;
      await controller.play(first[0]);
      controller.addNext(first[1]);
      controller.toggleFavorite(first[2]);
      for (var round = 0; round < 60; round++) {
        await controller.search('query $round');
      }

      expect(controller.knownTrackCount, lessThan(60 * 40));
      expect(controller.queue.map((track) => track.id), [
        first[0].id,
        first[1].id,
      ]);
      expect(controller.favorites.single.id, first[2].id);
      await controller.next();
      expect(controller.currentTrack?.id, first[1].id);
      // The latest results can still be played by reference (control API).
      final latest = controller.searchResults.last;
      expect(await controller.playByRef(latest.sourceId, latest.id), isTrue);
    },
  );
}

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: 'public',
);

final class _ManyResults implements MusicCatalog {
  @override
  Iterable<SourceDescriptor> get sources => [
    SourceDescriptor(
      id: 'audius',
      name: 'Audius',
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
  }) async => [
    for (var index = 0; index < 40; index++) _track('$query-$index'),
  ];
}
