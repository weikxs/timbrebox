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
    if (_downloading.contains(key)) {
      cancelDownload(track);
      return;
    }
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

  /// Stops a running download; it ends without an error and leaves no
  /// partial file.
  void cancelDownload(CatalogTrack track) =>
      _downloadCancels[track.ref.toString()]?.cancel();

  /// How far a running download is (0..1), or null when its size is unknown.
  double? downloadProgressFor(CatalogTrack track) =>
      _downloadProgress.value[track.ref.toString()];

  /// Download progress on its own channel, so only the progress indicators
  /// rebuild as bytes arrive.
  ValueListenable<Map<String, double>> get downloadProgressListenable =>
      _downloadProgress;

  Future<void> _download(CatalogTrack track) async {
    final key = track.ref.toString();
    _rememberResolveHint(track);
    final cancellation = CancellationToken();
    _downloadCancels[key] = cancellation;
    try {
      final file = await _downloadService!.download(
        track,
        cancellation: cancellation,
        onProgress: (received, total) =>
            _reportDownloadProgress(key, received, total),
      );
      _downloadPaths[key] = file.path;
      _downloads.add(key);
      unawaited(_persistLibrary());
    } on OperationCancelled {
      DiagnosticLog.record('download cancelled: ${track.title}');
    } catch (error) {
      DiagnosticLog.record('download failed: ${track.title}: $error');
      _downloadErrors[key] = friendlyDownloadError(error);
    } finally {
      _downloadCancels.remove(key);
      _downloading.remove(key);
      // A download the app's shutdown cancelled has nobody left to tell.
      if (!_isDisposed) {
        _downloadProgress.value = {..._downloadProgress.value}..remove(key);
        _notify();
      }
    }
  }

  /// Publishes whole-percent steps only: a large file arrives in thousands
  /// of chunks.
  void _reportDownloadProgress(String key, int received, int? total) {
    if (total == null || total <= 0) return;
    final fraction = (received / total).clamp(0.0, 1.0);
    final previous = _downloadProgress.value[key];
    final sameStep =
        previous != null && (fraction * 100).floor() == (previous * 100).floor();
    if (sameStep || _isDisposed) return;
    _downloadProgress.value = {..._downloadProgress.value, key: fraction};
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
