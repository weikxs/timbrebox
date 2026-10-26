part of 'app_controller.dart';

/// Downloads into the local-music library and its persisted index.
extension AppControllerDownloads on AppController {
  void toggleDownload(CatalogTrack track) {
    final key = track.ref.toString();
    _knownTracks[key] = track;
    if (_downloadService == null) {
      _downloads.contains(key) ? _downloads.remove(key) : _downloads.add(key);
      _notify();
      return;
    }
    if (_downloading.contains(key)) return;
    if (_downloadPaths.containsKey(key)) {
      final removedPath = _downloadPaths.remove(key);
      _downloads.remove(key);
      _notify();
      unawaited(_deleteLocalFile(removedPath));
      unawaited(_persistLibrary());
      return;
    }
    _downloadErrors.remove(key);
    _downloading.add(key);
    _notify();
    unawaited(_download(track));
  }

  /// Removes every downloaded track and deletes its local file.
  void clearDownloads() {
    final keys = _downloads.toList();
    if (keys.isEmpty) return;
    for (final key in keys) {
      final path = _downloadPaths.remove(key);
      _downloads.remove(key);
      unawaited(_deleteLocalFile(path));
    }
    _notify();
    unawaited(_persistLibrary());
  }

  Future<void> _download(CatalogTrack track) async {
    final key = track.ref.toString();
    _rememberResolveHint(track);
    try {
      final file = await _downloadService!.download(track);
      _downloadPaths[key] = file.path;
      _downloads.add(key);
      unawaited(_persistLibrary());
    } catch (error) {
      _downloadErrors[key] = _friendlyDownloadError(error);
    } finally {
      _downloading.remove(key);
      _notify();
    }
  }

  /// Rebuilds the local-music library from the persisted index so downloaded
  /// files keep playing straight from disk after a restart, with no network.
  Future<void> _restoreLibrary() async {
    final store = _downloadStore;
    if (store == null) return;
    final entries = await store.load();
    if (entries.isEmpty) return;
    for (final entry in entries) {
      final key = entry.ref.toString();
      _knownTracks[key] = entry.track;
      _downloadPaths[key] = entry.path;
      _downloads.add(key);
    }
    _notify();
  }

  Future<void> _persistLibrary() async {
    final store = _downloadStore;
    if (store == null) return;
    final entries = <DownloadedEntry>[
      for (final key in _downloads)
        if (_downloadPaths[key] != null && _knownTracks[key] != null)
          DownloadedEntry(track: _knownTracks[key]!, path: _downloadPaths[key]!),
    ];
    await store.save(entries);
  }

  Future<void> _deleteLocalFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best-effort cleanup: a missing or locked file must not surface as an
      // error in the library UI.
    }
  }
}
