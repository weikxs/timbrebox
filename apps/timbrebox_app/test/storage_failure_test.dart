import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/design/app_strings.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/favorites_store.dart';

import 'support/test_player_engine.dart';

/// A save that fails (full disk, no permission) used to vanish silently.
void main() {
  test('a failed save is reported once', () async {
    final controller = AppController(
      engine: TestPlayerEngine(),
      favoritesStore: _BrokenFavorites(),
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);

    controller.toggleFavorite(_track('a'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.takeNotice(), AppStrings.t('storage.writeFailed'));
    expect(controller.takeNotice(), isNull);

    controller.toggleFavorite(_track('b'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.takeNotice(), isNull); // Once per session.
  });
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

final class _BrokenFavorites implements FavoritesStore {
  @override
  Future<List<CatalogTrack>> load() async => const [];

  @override
  Future<void> save(List<CatalogTrack> favorites) async =>
      throw const FileSystemExceptionStub();
}

class FileSystemExceptionStub implements Exception {
  const FileSystemExceptionStub();
}
