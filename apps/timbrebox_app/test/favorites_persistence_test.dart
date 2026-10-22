import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/favorites_store.dart';

import 'support/test_player_engine.dart';

class _MemoryFavoritesStore implements FavoritesStore {
  List<CatalogTrack> saved = const [];

  @override
  Future<List<CatalogTrack>> load() async => saved;

  @override
  Future<void> save(List<CatalogTrack> favorites) async => saved = favorites;
}

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: '待解析',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('favorites are saved and restored across controllers', () async {
    final store = _MemoryFavoritesStore();

    final first =
        AppController(engine: TestPlayerEngine(), favoritesStore: store);
    first.toggleFavorite(_track('alpha'));
    first.toggleFavorite(_track('bravo'));
    await _settle();
    expect(store.saved.map((t) => t.id), containsAll(['alpha', 'bravo']));
    first.dispose();

    // A fresh controller with the same store rebuilds the favorites list.
    final second =
        AppController(engine: TestPlayerEngine(), favoritesStore: store);
    await _settle();
    expect(second.favorites.map((t) => t.id), containsAll(['alpha', 'bravo']));
    second.dispose();
  });

  test('un-favoriting persists the removal', () async {
    final store = _MemoryFavoritesStore();
    final controller =
        AppController(engine: TestPlayerEngine(), favoritesStore: store);
    addTearDown(controller.dispose);

    final track = _track('alpha');
    controller.toggleFavorite(track); // add
    await _settle();
    controller.toggleFavorite(track); // remove
    await _settle();
    expect(store.saved, isEmpty);
  });
}
