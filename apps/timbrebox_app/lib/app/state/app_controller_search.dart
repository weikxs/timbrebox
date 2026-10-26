part of 'app_controller.dart';

/// Search across sources, per-source paging and hot-library categories.
extension AppControllerSearch on AppController {
  Future<void> search(String value) async {
    _query = value.trim();
    if (_query.isNotEmpty) _recordSearch(_query);
    final generation = ++_searchGeneration;
    _searchCancellation?.cancel();
    _searchCancellation = null;
    _loadMoreCancellation?.cancel();
    _loadMoreCancellation = null;
    _resetPaging();
    if (_query.isEmpty) {
      _results = [];
      _searchBatch = null;
      _searchError = null;
      _isSearching = false;
      _notify();
      return;
    }
    final cancellation = CancellationToken();
    _searchCancellation = cancellation;
    if (_enabledSources.isEmpty) {
      _results = [];
      _searchBatch = null;
      _searchError = AppStrings.t('search.noSources');
      _isSearching = false;
      _notify();
      return;
    }
    _isSearching = true;
    _searchError = null;
    _notify();
    try {
      final groupedCatalog = _catalog is GroupedMusicCatalog
          ? _catalog as GroupedMusicCatalog
          : null;
      if (groupedCatalog != null) {
        // Results show per source as each one finishes; the previous query's
        // results are gone from the start so the two never mix.
        _searchBatch = CatalogSearchBatch(query: _query, groups: const []);
        _results = [];
        await for (final batch in groupedCatalog.searchGrouped(
          _query,
          cancellation: cancellation,
        )) {
          if (generation != _searchGeneration) return;
          _searchBatch = batch;
          _results = batch.tracks;
          _initPagingFromBatch(batch);
          for (final track in _results) {
            _knownTracks[track.ref.toString()] = track;
          }
          _notify();
        }
        if (generation != _searchGeneration) return;
        _searchError = _globalSearchError(_searchBatch!);
      } else {
        final results = await _catalog.search(
          _query,
          cancellation: cancellation,
        );
        if (generation != _searchGeneration) return;
        _searchBatch = null;
        _results = results;
        _searchError = null;
        for (final track in results) {
          _knownTracks[track.ref.toString()] = track;
        }
      }
    } on MusicCatalogException catch (error) {
      if (generation != _searchGeneration) return;
      _results = [];
      _searchBatch = null;
      _searchError = error.message;
    } catch (_) {
      if (generation != _searchGeneration) return;
      _results = [];
      _searchBatch = null;
      _searchError = AppStrings.t('search.unavailable');
    } finally {
      if (generation == _searchGeneration) {
        _isSearching = false;
        _notify();
      }
    }
  }

  /// Loads the next page for a single source (the selected tab) and appends any
  /// new tracks. Sources without real pagination return an empty page, which
  /// marks them exhausted so the list stops asking.
  Future<void> loadMore(String sourceId) async {
    if (_query.isEmpty) return;
    if (!hasMoreResults(sourceId)) return;
    if (_loadingMore.contains(sourceId)) return;
    // After a failure, wait before asking again: the list asks for more on
    // every frame while it is shorter than the screen.
    final retryAt = _loadMoreRetryAt[sourceId];
    if (retryAt != null && DateTime.now().isBefore(retryAt)) return;
    final catalog = _catalog;
    if (catalog is! PagedMusicCatalog) return;
    _loadingMore.add(sourceId);
    _notify();
    final generation = _searchGeneration;
    final nextPage = (_sourcePage[sourceId] ?? 1) + 1;
    final cancellation = CancellationToken();
    _loadMoreCancellation = cancellation;
    try {
      final group = await (catalog as PagedMusicCatalog).searchMore(
        sourceId,
        _query,
        page: nextPage,
        cancellation: cancellation,
      );
      if (generation != _searchGeneration) return;
      final existing = _pagedResults[sourceId] ?? const <CatalogTrack>[];
      final seen = existing.map((track) => track.ref.toString()).toSet();
      final fresh = <CatalogTrack>[
        for (final track in group.tracks)
          if (seen.add(track.ref.toString())) track,
      ];
      if (fresh.isNotEmpty) {
        _pagedResults[sourceId] = [...existing, ...fresh];
        for (final track in fresh) {
          _knownTracks[track.ref.toString()] = track;
        }
        _sourcePage[sourceId] = nextPage;
      }
      // Only a genuinely empty page ends the waterfall — a partial page may
      // still have a next one, so we keep loading until nothing new arrives.
      final failure = group.failure;
      if (failure == null && fresh.isEmpty) {
        _sourceExhausted.add(sourceId);
      } else if (failure != null && !failure.retryable) {
        _sourceExhausted.add(sourceId);
      } else if (failure != null) {
        _loadMoreRetryAt[sourceId] = DateTime.now().add(
          AppController._loadMoreCooldown,
        );
      } else {
        _loadMoreRetryAt.remove(sourceId);
      }
    } finally {
      _loadingMore.remove(sourceId);
      if (generation == _searchGeneration) _notify();
    }
  }

  void _resetPaging() {
    _loadMoreRetryAt.clear();
    _pagedResults.clear();
    _sourcePage.clear();
    _sourceExhausted.clear();
    _loadingMore.clear();
  }

  /// Starts paging for each source that just reported; one already paging
  /// (it may have loaded more pages meanwhile) is left alone. [search] resets
  /// paging before the first batch.
  void _initPagingFromBatch(CatalogSearchBatch batch) {
    for (final group in batch.groups) {
      if (_pagedResults.containsKey(group.sourceId)) continue;
      _pagedResults[group.sourceId] = List.of(group.tracks);
      _sourcePage[group.sourceId] = 1;
    }
  }

  /// Loads a hot-library category's playlist on demand. A category is either an
  /// Audius genre (real genre trending) or a Bilibili keyword (a Chinese
  /// category via real B站 search). Cached after the first load.
  Future<void> loadCategory(
    String key, {
    String? audiusGenre,
    String? bilibiliQuery,
    PluginTopListItem? pluginTopList,
    bool force = false,
  }) async {
    if (!force && _categoryTracks.containsKey(key)) return;
    if (_categoryLoading.contains(key)) return;
    _categoryLoading.add(key);
    _categoryErrors.remove(key);
    _notify();
    final cancellation = CancellationToken();
    final catalog = _catalog;
    try {
      var tracks = const <CatalogTrack>[];
      if (pluginTopList != null) {
        final source = _pluginSources[pluginTopList.sourceId];
        if (source != null) {
          final summaries = await source.topListDetail(pluginTopList.id);
          tracks = summaries.map(source.toCatalogTrack).toList();
        }
      } else if (audiusGenre != null && catalog is ChartMusicCatalog) {
        tracks = await (catalog as ChartMusicCatalog).trendingByGenre(
          audiusGenre,
          cancellation: cancellation,
        );
      } else if (bilibiliQuery != null && catalog is PagedMusicCatalog) {
        final group = await (catalog as PagedMusicCatalog).searchMore(
          'bilibili',
          bilibiliQuery,
          page: 1,
          cancellation: cancellation,
        );
        if (group.tracks.isEmpty && group.failure != null) {
          throw SourceException(group.failure!.message, retryable: true);
        }
        tracks = group.tracks;
      }
      _categoryTracks[key] = tracks;
      for (final track in tracks) {
        _knownTracks[track.ref.toString()] = track;
      }
      if (tracks.isEmpty) _categoryErrors[key] = AppStrings.t('category.empty');
    } on SourceException catch (error) {
      _categoryErrors[key] = error.message;
    } catch (_) {
      _categoryErrors[key] = AppStrings.t('category.loadFailed');
    } finally {
      _categoryLoading.remove(key);
      _notify();
    }
  }

  /// Searches for the current track by title and artist: the way back when
  /// a saved track no longer resolves (its source forgot it, or the item is
  /// gone).
  Future<void> searchAgainForCurrent() async {
    final track = _currentTrack;
    if (track == null) return;
    await search('${track.title} ${track.artist}'.trim());
  }

  String? _globalSearchError(CatalogSearchBatch batch) {
    if (batch.hasResults) return null;
    for (final group in batch.groups) {
      if (group.failure case final failure?) return failure.message;
    }
    return null;
  }
}
