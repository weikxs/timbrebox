import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/model/playlist.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/playlist_store.dart';

import 'support/test_player_engine.dart';

class _MemoryPlaylistStore implements PlaylistStore {
  List<Playlist> saved = const [];

  @override
  Future<List<Playlist>> load() async => saved;

  @override
  Future<void> save(List<Playlist> playlists) async => saved = playlists;
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
  test('create, add (dedup), remove, rename, delete', () {
    final store = _MemoryPlaylistStore();
    final controller = AppController(
      engine: TestPlayerEngine(),
      playlistStore: store,
    );
    addTearDown(controller.dispose);

    final id = controller.createPlaylist('Chill');
    expect(controller.playlists.single.name, 'Chill');

    controller.addToPlaylist(id, _track('a'));
    controller.addToPlaylist(id, _track('a')); // dedupe
    controller.addToPlaylist(id, _track('b'));
    expect(controller.playlists.single.tracks.map((t) => t.id), ['a', 'b']);

    controller.removeFromPlaylist(id, _track('a').ref);
    expect(controller.playlists.single.tracks.map((t) => t.id), ['b']);

    controller.renamePlaylist(id, 'Focus');
    expect(controller.playlists.single.name, 'Focus');

    controller.deletePlaylist(id);
    expect(controller.playlists, isEmpty);
  });

  test('saveQueueAsPlaylist captures the current queue', () async {
    final controller = AppController(engine: TestPlayerEngine());
    addTearDown(controller.dispose);
    await controller.play(_track('a'));
    controller.addNext(_track('b'));

    final id = controller.saveQueueAsPlaylist('My queue');
    final saved = controller.playlists.firstWhere((p) => p.id == id);
    expect(saved.name, 'My queue');
    expect(saved.tracks.map((t) => t.id), ['a', 'b']);
  });

  test('playAll and shufflePlay start playback from a track list', () async {
    final controller = AppController(engine: TestPlayerEngine());
    addTearDown(controller.dispose);
    final tracks = [_track('a'), _track('b'), _track('c')];

    await controller.playAll(tracks);
    expect(controller.isPlaying, isTrue);
    expect(controller.queue.map((t) => t.id).toSet(), {'a', 'b', 'c'});

    await controller.shufflePlay(tracks);
    expect(controller.isPlaying, isTrue);
    expect(controller.queue.map((t) => t.id).toSet(), {'a', 'b', 'c'});
  });

  test('playlists persist and restore', () async {
    final store = _MemoryPlaylistStore();
    final first = AppController(
      engine: TestPlayerEngine(),
      playlistStore: store,
    );
    final id = first.createPlaylist('Road trip', seed: _track('x'));
    first.addToPlaylist(id, _track('y'));
    await _settle();
    expect(store.saved.single.tracks.map((t) => t.id), ['x', 'y']);
    first.dispose();

    final second = AppController(
      engine: TestPlayerEngine(),
      playlistStore: store,
    );
    addTearDown(second.dispose);
    await _settle();
    expect(second.playlists.single.name, 'Road trip');
    expect(second.playlists.single.tracks.map((t) => t.id), ['x', 'y']);
  });
}
