import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:timbrebox_core/timbrebox_core.dart';

import 'catalog_search.dart';
import 'catalog_track.dart';
import 'net/pooled_http.dart';
import 'bounded_cache.dart';
import 'catalog_source.dart';
import 'source_config.dart';
import 'source_strings.dart';

part 'directory_catalog_sources.dart';
part 'openverse_catalog_source.dart';

/// Sources that were built in before and are now added with plugins only, by
/// id, with the name shown to the user. Tracks saved from them stay in the
/// library; playing one explains where the source went instead of reporting
/// an unknown source.
const retiredBuiltInSources = {
  'youtube': 'YouTube',
  'bilibili': 'Bilibili',
  'douyin': 'Douyin',
  'tiktok': 'TikTok',
};

/// App-facing catalog contract. It keeps source-specific HTTP details out of
/// the UI and exposes the same search path on every supported platform.
abstract interface class MusicCatalog {
  Iterable<SourceDescriptor> get sources;

  bool isEnabled(String sourceId);
  void setEnabled(String sourceId, bool enabled);

  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  });
}

abstract interface class ResolvableMusicCatalog {
  StreamResolver get streamResolver;
}

/// Hands a saved track's [CatalogTrack.resolveHint] back to its source (see
/// [HintedCatalogSource]) before it is played or downloaded.
abstract interface class ResolveHintCatalog {
  void rememberResolveHint(CatalogTrack track);
}

/// Lets sources (e.g. installed plugins) be added or removed at runtime.
abstract interface class MutableMusicCatalog {
  void registerSource(CatalogSource source);
  void unregisterSource(String id);
}

/// Optional richer contract used by the UI. Keeping this separate preserves
/// compatibility with small platform/test catalogs while the built-in catalog
/// exposes source-level status and results.
abstract interface class GroupedMusicCatalog {
  /// Emits the results so far each time a source finishes (sources in a
  /// stable order), so the UI never waits for the slowest source.
  Stream<CatalogSearchBatch> searchGrouped(
    String query, {
    required CancellationToken cancellation,
  });
}

/// Optional per-source pagination used by the infinite-scroll result list.
///
/// Only one source (the selected tab) is advanced at a time, so this fetches a
/// single next page instead of re-running every source.
abstract interface class PagedMusicCatalog {
  Future<CatalogSearchGroup> searchMore(
    String sourceId,
    String query, {
    required int page,
    required CancellationToken cancellation,
  });
}

/// Real, public trending data for the hot library — never fabricated ranks.
abstract interface class ChartMusicCatalog {
  Future<List<CatalogTrack>> trending({
    required CancellationToken cancellation,
  });

  Future<List<CatalogTrack>> trendingByGenre(
    String genre, {
    required CancellationToken cancellation,
  });
}

typedef JsonReader =
    Future<String> Function(Uri uri, CancellationToken cancellation);

class BuiltInMusicCatalog
    implements
        MusicCatalog,
        GroupedMusicCatalog,
        PagedMusicCatalog,
        ChartMusicCatalog,
        ResolvableMusicCatalog,
        ResolveHintCatalog,
        MutableMusicCatalog {
  BuiltInMusicCatalog(Iterable<CatalogSource> sources)
    : _sources = {for (final source in sources) source.descriptor.id: source},
      _registry = SourceRegistry(sources);

  /// The built-in sources: open directories with public APIs only. Video and
  /// streaming platforms are not built in; a user adds them with a plugin.
  factory BuiltInMusicCatalog.standard() => BuiltInMusicCatalog([
    AudiusCatalogSource(),
    OpenverseCatalogSource(),
    InternetArchiveCatalogSource(),
    RadioBrowserCatalogSource(),
  ]);

  final Map<String, CatalogSource> _sources;
  SourceRegistry _registry;

  @override
  StreamResolver get streamResolver => _CatalogStreamResolver(_sources);

  @override
  void rememberResolveHint(CatalogTrack track) {
    final hint = track.resolveHint;
    final source = _sources[track.sourceId];
    if (hint != null && source is HintedCatalogSource) {
      (source as HintedCatalogSource).rememberHint(track.id, hint);
    }
  }

  @override
  void registerSource(CatalogSource source) {
    _sources[source.descriptor.id] = source;
    _rebuildRegistry();
  }

  @override
  void unregisterSource(String id) {
    if (_sources.remove(id) != null) _rebuildRegistry();
  }

  /// Rebuilds the immutable registry over the current sources, preserving which
  /// sources were disabled.
  void _rebuildRegistry() {
    final disabled = _sources.keys
        .where((id) => !_registry.isEnabled(id))
        .toList(growable: false);
    _registry = SourceRegistry(_sources.values);
    for (final id in disabled) {
      if (_sources.containsKey(id)) _registry.setEnabled(id, false);
    }
  }

  @override
  Iterable<SourceDescriptor> get sources => _registry.descriptors;

  @override
  bool isEnabled(String sourceId) => _registry.isEnabled(sourceId);

  @override
  void setEnabled(String sourceId, bool enabled) =>
      _registry.setEnabled(sourceId, enabled);

  @override
  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  }) async {
    var batch = CatalogSearchBatch(query: query, groups: const []);
    await for (final next in searchGrouped(query, cancellation: cancellation)) {
      batch = next;
    }
    if (!batch.hasResults && batch.hasFailures) {
      throw MusicCatalogException(
        batch.groups
            .firstWhere((group) => group.failure != null)
            .failure!
            .message,
      );
    }
    return batch.tracks;
  }

  @override
  Stream<CatalogSearchBatch> searchGrouped(
    String query, {
    required CancellationToken cancellation,
  }) async* {
    final request = SearchRequest(query: query, cancellation: cancellation);
    // Each source's tracks are built once, not again on every later emission.
    final built = <String, CatalogSearchGroup>{};
    await for (final coreBatch in _registry.searchBatches(request)) {
      yield CatalogSearchBatch(
        query: coreBatch.query,
        groups: [
          for (final group in coreBatch.groups)
            if (_sources[group.sourceId] case final source?)
              built[group.sourceId] ??= _catalogGroup(source, group),
        ],
      );
    }
    cancellation.throwIfCancelled();
  }

  CatalogSearchGroup _catalogGroup(
    CatalogSource source,
    SourceSearchGroup group,
  ) {
    try {
      return CatalogSearchGroup(
        sourceId: group.sourceId,
        sourceName: source.descriptor.name,
        status: group.status,
        tracks: List.unmodifiable(group.items.map(source.toCatalogTrack)),
        failure: group.failure,
      );
    } on StateError catch (error) {
      return CatalogSearchGroup(
        sourceId: group.sourceId,
        sourceName: source.descriptor.name,
        status: SourceSearchStatus.failure,
        tracks: const [],
        failure: SourceFailure(error.message, retryable: true),
      );
    }
  }

  @override
  Future<CatalogSearchGroup> searchMore(
    String sourceId,
    String query, {
    required int page,
    required CancellationToken cancellation,
  }) async {
    final source = _sources[sourceId];
    if (source == null) {
      return CatalogSearchGroup(
        sourceId: sourceId,
        sourceName: sourceId,
        status: SourceSearchStatus.failure,
        tracks: const [],
        failure: SourceFailure(
          SourceStrings.t(
            'source.err.unregisteredFmt',
          ).replaceFirst('{id}', sourceId),
          retryable: false,
        ),
      );
    }
    final name = source.descriptor.name;
    try {
      final request = SearchRequest(
        query: query,
        cancellation: cancellation,
        page: page,
      );
      final result = await source.search(request);
      cancellation.throwIfCancelled();
      final tracks = <CatalogTrack>[];
      for (final summary in result.items) {
        try {
          tracks.add(source.toCatalogTrack(summary));
        } on StateError {
          // Skip an item that can no longer be materialised into a track.
        }
      }
      return CatalogSearchGroup(
        sourceId: sourceId,
        sourceName: name,
        status: tracks.isEmpty
            ? SourceSearchStatus.empty
            : SourceSearchStatus.success,
        tracks: List.unmodifiable(tracks),
      );
    } on OperationCancelled {
      return CatalogSearchGroup(
        sourceId: sourceId,
        sourceName: name,
        status: SourceSearchStatus.cancelled,
        tracks: const [],
      );
    } on SourceException catch (error) {
      return CatalogSearchGroup(
        sourceId: sourceId,
        sourceName: name,
        status: SourceSearchStatus.failure,
        tracks: const [],
        failure: SourceFailure(
          error.message,
          retryable: error.retryable,
          code: error.code,
        ),
      );
    } catch (_) {
      return CatalogSearchGroup(
        sourceId: sourceId,
        sourceName: name,
        status: SourceSearchStatus.failure,
        tracks: const [],
        failure: SourceFailure(
          SourceStrings.t('source.errLoadMore'),
          retryable: true,
        ),
      );
    }
  }

  @override
  Future<List<CatalogTrack>> trending({
    required CancellationToken cancellation,
  }) async {
    final source = _sources['audius'];
    if (source is! AudiusCatalogSource) return const [];
    final summaries = await source.trending(cancellation);
    return [for (final summary in summaries) source.toCatalogTrack(summary)];
  }

  @override
  Future<List<CatalogTrack>> trendingByGenre(
    String genre, {
    required CancellationToken cancellation,
  }) async {
    final source = _sources['audius'];
    if (source is! AudiusCatalogSource) return const [];
    final summaries = await source.trending(
      cancellation,
      genre: genre,
      limit: 12,
    );
    return [for (final summary in summaries) source.toCatalogTrack(summary)];
  }
}

/// Reads JSON from the built-in catalog APIs over one long-lived client, so
/// repeated searches reuse keep-alive connections instead of a new TLS
/// handshake per request.
class JsonHttpClient {
  JsonHttpClient({
    HttpClient Function()? clientFactory,
    SourceHttpPolicy? policy,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _policy = policy ?? BuiltInSourceConfig.http;

  final HttpClient Function() _clientFactory;
  final SourceHttpPolicy _policy;
  late final HttpClient _client = _clientFactory()
    ..idleTimeout = pooledIdleTimeout;

  Future<String> read(Uri uri, CancellationToken cancellation) async {
    try {
      return await _read(uri, cancellation);
    } on TimeoutException {
      throw SourceException(
        SourceStrings.t('source.errRespTimeout'),
        retryable: true,
      );
    } on SocketException {
      throw SourceException(
        SourceStrings.t('source.errNetworkRetry'),
        retryable: true,
      );
    } on FormatException {
      throw SourceException(
        SourceStrings.t('source.errBadSearch'),
        retryable: true,
      );
    }
  }

  Future<String> _read(Uri uri, CancellationToken cancellation) async {
    HttpClientRequest? request;
    try {
      request = await openWithin(_client.getUrl(uri), _policy.timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, _policy.userAgent);
      final response = await responseWithin(request, _policy.timeout);
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw SourceException(
          SourceStrings.t('source.errRateLimited'),
          retryable: true,
          code: 'rate_limited',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw SourceException(
          SourceStrings.t('source.errUnavailableRetry'),
          retryable: true,
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        cancellation.throwIfCancelled();
        bytes.add(chunk);
        if (bytes.length > _policy.maxResponseBytes) {
          throw SourceException(
            SourceStrings.t('source.errRespTooLarge'),
            retryable: true,
          );
        }
      }
      return utf8.decode(bytes.takeBytes());
    } catch (_) {
      // A failed exchange must not leave its pooled connection half-read.
      request?.abort();
      rethrow;
    }
  }
}

Object? _decodeJson(String body, {required String message}) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw SourceException(
      message,
      retryable: true,
      code: 'invalid_catalog_response',
    );
  }
}

class MusicCatalogException implements Exception {
  const MusicCatalogException(this.message);
  final String message;
}

class _CatalogStreamResolver implements StreamResolver {
  _CatalogStreamResolver(this._sources);

  final Map<String, CatalogSource> _sources;

  @override
  Future<ResolvedStream> resolve(StreamRequest request) {
    final source = _sources[request.ref.sourceId];
    if (source == null) {
      final retired = retiredBuiltInSources[request.ref.sourceId];
      if (retired != null) {
        throw SourceException(
          SourceStrings.t(
            'source.err.retiredFmt',
          ).replaceFirst('{id}', retired),
          retryable: false,
          code: 'source_retired',
        );
      }
      throw StateError(
        SourceStrings.t(
          'source.err.unregisteredFmt',
        ).replaceFirst('{id}', request.ref.sourceId),
      );
    }
    return source.resolve(request);
  }
}
