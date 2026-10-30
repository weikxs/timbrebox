part of 'app_controller.dart';

/// Plugins: third-party sources installed from a URL, their charts and
/// lyrics.
extension AppControllerPlugins on AppController {
  List<PluginManifest> get plugins => List.unmodifiable(_plugins);

  /// Stored plugins that could not be loaded at launch (see
  /// [PluginRepository.skippedAtLoad]); the plugin settings list them.
  List<String> get skippedPlugins => _skippedPlugins;
  bool get supportsPlugins =>
      _pluginRepository != null && _catalog is MutableMusicCatalog;

  List<PluginTopListItem> get pluginTopLists =>
      List.unmodifiable(_pluginTopLists);

  /// Aggregates every enabled plugin's charts (`getTopLists`) for the hot library.
  Future<void> loadPluginTopLists({bool force = false}) async {
    if (_pluginTopListsLoaded && !force) return;
    _pluginTopListsLoaded = true;
    final all = <PluginTopListItem>[];
    final failed = <String>[];
    // Snapshot before awaiting so install/remove mid-load can't throw a
    // ConcurrentModificationError.
    for (final entry in _pluginSources.entries.toList()) {
      if (!sourceEnabled(entry.key)) continue;
      try {
        all.addAll(await entry.value.topLists());
      } catch (error) {
        failed.add(entry.value.manifest.platform);
        DiagnosticLog.record('plugin ${entry.key} top lists failed: $error');
      }
    }
    _pluginTopLists
      ..clear()
      ..addAll(all);
    _pluginTopListFailures = failed;
    _notify();
  }

  /// The plugins whose charts failed to load last time (their names); the
  /// hot library offers to try again.
  List<String> get pluginTopListFailures =>
      List.unmodifiable(_pluginTopListFailures);

  /// Loads every plugin's charts again (after a failure).
  Future<void> retryPluginTopLists() => loadPluginTopLists(force: true);

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
    _skippedPlugins = repository.skippedAtLoad;
    if (sources.isNotEmpty) _pluginsChanged();
    if (sources.isNotEmpty || _skippedPlugins.isNotEmpty) _notify();
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
      throw PluginInstallException(
        AppStrings.t('plugin.err.unsupportedPlatform'),
      );
    }
    final mutable = catalog as MutableMusicCatalog;
    final sources = await repository.installFromUrl(url);
    for (final source in sources) {
      _adoptSource(mutable, source);
    }
    // Reinstalling a plugin that was skipped at launch repairs it.
    final installed = {for (final source in sources) source.manifest.id};
    _skippedPlugins = [
      for (final id in _skippedPlugins)
        if (!installed.contains(id)) id,
    ];
    _pluginsChanged();
    _notify();
    return sources.length;
  }

  /// Re-fetches every plugin from its srcUrl and reports how many were
  /// updated and which could not be checked.
  Future<PluginUpdateReport> updatePlugins() async {
    final repository = _pluginRepository;
    final catalog = _catalog;
    if (repository == null || catalog is! MutableMusicCatalog) {
      return const PluginUpdateReport(updated: 0, failed: []);
    }
    final mutable = catalog as MutableMusicCatalog;
    var updated = 0;
    final failed = <PluginUpdateFailure>[];
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
      } catch (error) {
        // A single failed update must not abort the rest.
        failed.add(
          PluginUpdateFailure(
            name: manifest.platform,
            reason: error is PluginInstallException
                ? error.message
                : AppStrings.t('plugin.err.updateUnexpected'),
          ),
        );
        DiagnosticLog.record('plugin ${manifest.id} update failed: $error');
      }
    }
    if (updated > 0) {
      _pluginsChanged();
      _notify();
    }
    return PluginUpdateReport(updated: updated, failed: failed);
  }

  /// The live source of plugin [id], if it is installed.
  PluginCatalogSource? pluginSource(String id) => _pluginSources[id];

  /// The values the user entered for plugin [id]'s settings.
  Future<Map<String, String>> pluginVariables(String id) async =>
      await _pluginRepository?.variables(id) ?? const {};

  /// Saves the user's settings for plugin [id]; its engine restarts so the
  /// next call reads them.
  Future<void> savePluginVariables(
    String id,
    Map<String, String> values,
  ) async {
    final source = _pluginSources[id];
    final repository = _pluginRepository;
    if (source == null || repository == null) return;
    await repository.saveVariables(source.manifest, values);
    source.restart();
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

/// The outcome of [AppControllerPlugins.updatePlugins].
class PluginUpdateReport {
  const PluginUpdateReport({required this.updated, required this.failed});

  /// How many plugins were replaced by a newer version.
  final int updated;

  /// The plugins whose update could not be fetched or installed, and why.
  final List<PluginUpdateFailure> failed;
}

/// One plugin [AppControllerPlugins.updatePlugins] could not update.
class PluginUpdateFailure {
  const PluginUpdateFailure({required this.name, required this.reason});

  /// The plugin's name.
  final String name;

  /// What went wrong, in words for the user.
  final String reason;
}
