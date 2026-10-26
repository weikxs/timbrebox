part of 'app_controller.dart';

/// User playlists: named, ordered track lists persisted across restarts.
extension AppControllerPlaylists on AppController {
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  Future<void> _restorePlaylists() async {
    final store = _playlistStore;
    if (store == null) return;
    final saved = await store.load();
    if (saved.isEmpty) return;
    _playlists = saved;
    _notify();
  }

  /// Creates a playlist (optionally seeded with one track) and returns its id.
  String createPlaylist(String name, {CatalogTrack? seed}) {
    final id =
        'pl-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}';
    _playlists = [
      ..._playlists,
      Playlist(id: id, name: name.trim(), tracks: [?seed]),
    ];
    _persistPlaylists();
    _notify();
    return id;
  }

  /// Creates a playlist from the current play queue and returns its id.
  String saveQueueAsPlaylist(String name) {
    final id =
        'pl-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}';
    _playlists = [
      ..._playlists,
      Playlist(id: id, name: name.trim(), tracks: List.of(queue)),
    ];
    _persistPlaylists();
    _notify();
    return id;
  }

  void renamePlaylist(String id, String name) {
    _updatePlaylist(id, (playlist) => playlist.copyWith(name: name.trim()));
  }

  void deletePlaylist(String id) {
    _playlists = _playlists.where((playlist) => playlist.id != id).toList();
    _persistPlaylists();
    _notify();
  }

  /// Adds [track] to the playlist (no-op if already present).
  void addToPlaylist(String id, CatalogTrack track) {
    _updatePlaylist(id, (playlist) {
      if (playlist.tracks.any((t) => t.ref == track.ref)) return playlist;
      return playlist.copyWith(tracks: [...playlist.tracks, track]);
    });
  }

  void removeFromPlaylist(String id, MediaRef ref) {
    _updatePlaylist(
      id,
      (playlist) => playlist.copyWith(
        tracks: playlist.tracks.where((t) => t.ref != ref).toList(),
      ),
    );
  }

  Future<void> playPlaylist(String id) async {
    final playlist = _playlists.firstWhere(
      (p) => p.id == id,
      orElse: () => const Playlist(id: '', name: ''),
    );
    if (playlist.tracks.isNotEmpty) await playAll(playlist.tracks);
  }

  void _updatePlaylist(String id, Playlist Function(Playlist) update) {
    _playlists = [
      for (final playlist in _playlists)
        if (playlist.id == id) update(playlist) else playlist,
    ];
    _persistPlaylists();
    _notify();
  }

  void _persistPlaylists() => unawaited(_playlistStore?.save(_playlists));
}
