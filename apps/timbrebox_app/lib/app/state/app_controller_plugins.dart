part of 'app_controller.dart';

/// Plugins: third-party sources installed from a URL, their charts and
/// lyrics.
extension AppControllerPlugins on AppController {
  List<PluginManifest> get plugins => List.unmodifiable(_plugins);
  bool get supportsPlugins =>
      _pluginRepository != null && _catalog is MutableMusicCatalog;

  List<PluginTopListItem> get pluginTopLists =>
      List.unmodifiable(_pluginTopLists);

  /// Aggregates every enabled plugin's charts (`getTopLists`) for the hot library.
  Future<void> loadPluginTopLists({bool force = false}) async {
    if (_pluginTopListsLoaded && !force) return;
    _pluginTopListsLoaded = true;
    final all = <PluginTopListItem>[];
    // Snapshot before awaiting so install/remove mid-load can't throw a
    // ConcurrentModificationError.
    for (final entry in _pluginSources.entries.toList()) {
      if (!sourceEnabled(entry.key)) continue;
      try {
        all.addAll(await entry.value.topLists());
      } catch (error) {
        DiagnosticLog.record('plugin ${entry.key} top lists failed: $error');
      }
    }
    _pluginTopLists
      ..clear()
      ..addAll(all);
    _notify();
  }

  /// Plugins were restored, installed, updated, removed or switched on/off:
  /// charts already shown must reflect that (ones not shown yet load when
  /// the hot library opens).
  void _pluginsChanged() {
    if (!_pluginTopListsLoaded) return;
    unawaited(loadPluginTopLists(force: true));
  }

  bool get currentTrackHasLyric {
    final track = _currentTrack;
    if (track == null) return false;
    final source = _pluginSources[track.sourceId];
    return source != null && source.hasLyric;
  }

  /// The current track's lyric text, if it comes from a plugin providing one.
  Future<String?> currentLyric() async {
    final track = _currentTrack;
    if (track == null) return null;
    final source = _pluginSources[track.sourceId];
    if (source == null || !source.hasLyric) return null;
    return source.lyric(track.id);
  }

  Future<void> _restorePlugins() async {
    final repository = _pluginRepository;
    final catalog = _catalog;
    if (repository == null || catalog is! MutableMusicCatalog) return;
    final mutable = catalog as MutableMusicCatalog;
    final sources = await repository.loadInstalled();
    for (final source in sources) {
      _adoptSource(mutable, source, enabledDefault: source.manifest.enabled);
    }
    if (sources.isNotEmpty) {
      _pluginsChanged();
      _notify();
    }
  }

  /// Registers [source] (replacing any prior one with the same id, disposing it)
  /// and tracks its manifest + enabled state. A track playing from the old
  /// source keeps playing: its stream lives in the repository's shared proxy.
  void _adoptSource(
    MutableMusicCatalog mutable,
    PluginCatalogSource source, {
    bool enabledDefault = true,
  }) {
    final id = source.manifest.id;
    _pluginSources.remove(id)?.dispose();
    mutable.registerSource(source);
    _pluginSources[id] = source;
    _plugins.removeWhere((manifest) => manifest.id == id);
    _plugins.add(source.manifest);
    if (enabledDefault) {
      _enabledSources.add(id);
    } else {
      _catalog.setEnabled(id, false);
    }
  }

  /// Installs from a raw plugin `.js` URL or a subscription JSON URL. Returns
  /// how many plugins were installed. Throws on failure.
  Future<int> installPluginFromUrl(String url) async {
    final repository = _pluginRepository;
    final catalog = _catalog;
    if (repository == null || catalog is! MutableMusicCatalog) {
      throw PluginInstallException(AppStrings.t('plugin.err.unsupportedPlatform'));
    }
    final mutable = catalog as MutableMusicCatalog;
    final sources = await repository.installFromUrl(url);
    for (final source in sources) {
      _adoptSource(mutable, source);
    }
    _pluginsChanged();
    _notify();
    return sources.length;
  }

  /// Re-fetches every plugin from its srcUrl; returns how many were updated.
  Future<int> updatePlugins() async {
    final repository = _pluginRepository;
    final catalog = _catalog;
    if (repository == null || catalog is! MutableMusicCatalog) return 0;
    final mutable = catalog as MutableMusicCatalog;
    var updated = 0;
    for (final manifest in List.of(_plugins)) {
      try {
        final fresh = await repository.update(manifest);
        if (fresh == null) continue;
        _adoptSource(
          mutable,
          fresh,
          enabledDefault: _enabledSources.contains(manifest.id),
        );
        updated++;
      } catch (_) {
        // A single failed update must not abort the rest.
      }
    }
    if (updated > 0) {
      _pluginsChanged();
      _notify();
    }
    return updated;
  }

  Future<void> removePlugin(String id) async {
    await _pluginRepository?.remove(id);
    final catalog = _catalog;
    if (catalog is MutableMusicCatalog) {
      (catalog as MutableMusicCatalog).unregisterSource(id);
    }
    _pluginSources.remove(id)?.dispose();
    _enabledSources.remove(id);
    _plugins.removeWhere((manifest) => manifest.id == id);
    _pluginsChanged();
    _notify();
  }
}
