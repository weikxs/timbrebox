import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:timbrebox_core/timbrebox_core.dart';

import '../model/catalog_search.dart';
import '../model/catalog_track.dart';
import '../net/pooled_http.dart';
import 'bounded_cache.dart';
import 'catalog_source.dart';
import 'source_config.dart';
import 'video_source_adapters.dart';
import 'youtube_catalog_source.dart';
import '../design/app_strings.dart';

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

  factory BuiltInMusicCatalog.standard() => BuiltInMusicCatalog([
    YouTubeCatalogSource(),
    BilibiliCatalogSource(),
    DouyinCatalogSource(),
    TikTokCatalogSource(),
    AudiusCatalogSource(),
    InternetArchiveCatalogSource(),
    RadioBrowserCatalogSource(),
  ]);

  factory BuiltInMusicCatalog.v2() => BuiltInMusicCatalog([
    AudiusCatalogSource(),
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
        failure: SourceFailure(AppStrings.t('source.err.unregisteredFmt').replaceFirst('{id}', sourceId), retryable: false),
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
        failure: SourceFailure(AppStrings.t('source.errLoadMore'), retryable: true),
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

class AudiusCatalogSource implements CatalogSource {
  AudiusCatalogSource({
    HttpClient Function()? clientFactory,
    JsonReader? readJson,
  }) : _readJson =
           readJson ?? JsonHttpClient(clientFactory: clientFactory).read;

  final JsonReader _readJson;
  final _artwork = BoundedCache<String, String>();

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: 'audius',
    name: 'Audius',
    capabilities: const [SourceCapability.search, SourceCapability.streaming],
  );

  @override
  Future<SearchPage> search(SearchRequest request) async {
    // Audius full-text search returns a single ranked set with no offset, so
    // later pages are honestly empty rather than a refetched first page.
    if (request.page > 1) return const SearchPage(items: []);
    final uri = BuiltInSourceConfig.audius.uri(
      'search',
      query: {
        'query': request.query,
        'limit': '${BuiltInSourceConfig.pageSize}',
        'app_name': BuiltInSourceConfig.appName,
      },
    );
    final body = await _readJson(uri, request.cancellation);
    final decoded = _decodeJson(body, message: AppStrings.t('source.audius.badSearch'));
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) {
      throw SourceException(
        AppStrings.t('source.audius.badSearch'),
        retryable: true,
        code: 'invalid_catalog_response',
      );
    }
    return SearchPage(items: [for (final entry in data) ?_summaryFrom(entry)]);
  }

  /// Public trending tracks (optionally by genre), used by the hot library.
  /// Same track shape as search, so results map through the summary parser.
  Future<List<TrackSummary>> trending(
    CancellationToken cancellation, {
    String? genre,
    int limit = 30,
  }) async {
    final query = <String, String>{
      'app_name': BuiltInSourceConfig.appName,
      'limit': '$limit',
    };
    if (genre != null && genre.isNotEmpty) query['genre'] = genre;
    final uri = BuiltInSourceConfig.audius.uri('trending', query: query);
    final body = await _readJson(uri, cancellation);
    final decoded = _decodeJson(body, message: AppStrings.t('source.audius.badChart'));
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) {
      throw SourceException(
        AppStrings.t('source.audius.badChart'),
        retryable: true,
        code: 'invalid_catalog_response',
      );
    }
    return [for (final entry in data) ?_summaryFrom(entry)];
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) => CatalogTrack(
    id: summary.ref.itemId,
    title: summary.title,
    artist: summary.artist,
    sourceId: descriptor.id,
    sourceName: descriptor.name,
    duration: summary.duration ?? Duration.zero,
    quality: AppStrings.t('quality.publicStream'),
    artworkUrl: _artwork[summary.ref.itemId],
  );

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(AppStrings.t('source.err.refMismatch'));
    }
    return ResolvedStream(
      uri: BuiltInSourceConfig.audius.uri(
        'stream',
        pathValues: {'id': request.ref.itemId},
        query: {'app_name': BuiltInSourceConfig.appName},
      ),
    );
  }

  TrackSummary? _summaryFrom(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id']?.toString();
    final title = entry['title']?.toString().trim();
    final user = entry['user'];
    final artist = user is Map ? user['name']?.toString().trim() : null;
    if (id == null || id.isEmpty || title == null || title.isEmpty) return null;
    if (entry['is_streamable'] != true) return null;
    final artwork = entry['artwork'];
    if (artwork is Map) {
      final url = artwork['480x480'] ?? artwork['1000x1000'] ?? artwork['150x150'];
      if (url is String && url.isNotEmpty) _artwork[id] = url;
    }
    final durationSeconds = (entry['duration'] as num?)?.round();
    return TrackSummary(
      ref: MediaRef(sourceId: descriptor.id, itemId: id),
      title: title,
      artist: artist?.isNotEmpty == true ? artist! : descriptor.name,
      duration: durationSeconds == null
          ? null
          : Duration(seconds: durationSeconds),
    );
  }
}

/// Public radio directory. Radio Browser recommends selecting servers through
/// DNS; this first adapter uses its documented HTTPS endpoint. Public radio
/// streams can be HTTP, so that exception is isolated to this source only.
class RadioBrowserCatalogSource implements CatalogSource {
  RadioBrowserCatalogSource({
    HttpClient Function()? clientFactory,
    JsonReader? readJson,
  }) : _readJson =
           readJson ?? JsonHttpClient(clientFactory: clientFactory).read;

  final JsonReader _readJson;
  final _streams = BoundedCache<String, String>();

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: 'radio_browser',
    name: 'Radio Browser',
    capabilities: const [SourceCapability.search, SourceCapability.streaming],
  );

  @override
  Future<SearchPage> search(SearchRequest request) async {
    final uri = BuiltInSourceConfig.radioBrowser.uri(
      'search',
      pathValues: {'query': request.query},
      query: {
        'limit': '${BuiltInSourceConfig.pageSize}',
        'offset': '${(request.page - 1) * BuiltInSourceConfig.pageSize}',
        'hidebroken': 'true',
        'order': 'votes',
        'reverse': 'true',
      },
    );
    final body = await _readJson(uri, request.cancellation);
    final data = _decodeJson(body, message: AppStrings.t('source.radio.badResponse'));
    if (data is! List) {
      throw SourceException(
        AppStrings.t('source.radio.badResponse'),
        retryable: true,
        code: 'invalid_catalog_response',
      );
    }
    return SearchPage(items: [for (final entry in data) ?_summaryFrom(entry)]);
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) {
    if (!_streams.containsKey(summary.ref.itemId)) {
      throw StateError(AppStrings.t('source.radio.expired'));
    }
    return CatalogTrack(
      id: summary.ref.itemId,
      title: summary.title,
      artist: summary.artist,
      sourceId: descriptor.id,
      sourceName: descriptor.name,
      duration: Duration.zero,
      quality: AppStrings.t('quality.liveRadio'),
    );
  }

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(AppStrings.t('source.err.refMismatch'));
    }
    // After a restart nothing was searched yet: look the station up by id.
    final value =
        _streams[request.ref.itemId] ??
        await _lookUpStation(request.ref.itemId, request.cancellation);
    final uri = Uri.tryParse(value ?? '');
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
      throw SourceException(
        AppStrings.t('source.radio.expired'),
        retryable: true,
        code: 'media_reference_expired',
      );
    }
    return ResolvedStream(uri: uri);
  }

  /// The station's current stream address, by its id, or null when the
  /// directory no longer lists it.
  Future<String?> _lookUpStation(
    String id,
    CancellationToken cancellation,
  ) async {
    final uri = BuiltInSourceConfig.radioBrowser.uri(
      'station',
      pathValues: {'id': id},
    );
    final data = _decodeJson(
      await _readJson(uri, cancellation),
      message: AppStrings.t('source.radio.badResponse'),
    );
    if (data is! List) return null;
    for (final entry in data) {
      if (_summaryFrom(entry)?.ref.itemId == id) return _streams[id];
    }
    return null;
  }

  TrackSummary? _summaryFrom(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['stationuuid']?.toString();
    final name = entry['name']?.toString().trim();
    final stream = Uri.tryParse(entry['url_resolved']?.toString() ?? '');
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
    if (stream == null || !{'https', 'http'}.contains(stream.scheme)) {
      return null;
    }
    _streams[id] = stream.toString();
    final country = entry['countrycode']?.toString().trim();
    return TrackSummary(
      ref: MediaRef(sourceId: descriptor.id, itemId: id),
      title: name,
      artist: country?.isNotEmpty == true
          ? 'Internet radio · $country'
          : 'Internet radio',
    );
  }
}

/// Internet Archive's public audio catalogue.
///
/// Search returns stable item identifiers. The metadata request is deferred
/// until playback so signed/temporary URLs are never stored in a track or
/// search result. Only public audio files are considered playable.
class InternetArchiveCatalogSource implements CatalogSource {
  InternetArchiveCatalogSource({
    HttpClient Function()? clientFactory,
    JsonReader? readJson,
  }) : _readJson =
           readJson ?? JsonHttpClient(clientFactory: clientFactory).read;

  static const _audioFormats = <String>{
    'flac',
    'mp3',
    'mpeg',
    'ogg',
    'oga',
    'opus',
    'wav',
    'wave',
    'm4a',
    'aac',
  };

  final JsonReader _readJson;
  final _fileNames = BoundedCache<String, String>();

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: 'internet_archive',
    name: 'Internet Archive',
    capabilities: const [SourceCapability.search, SourceCapability.streaming],
  );

  @override
  Future<SearchPage> search(SearchRequest request) async {
    final query = request.query.replaceAll('"', ' ').trim();
    final uri = BuiltInSourceConfig.archive.uri(
      'search',
      query: {
        'q': 'mediatype:audio AND $query',
        'fl[]': 'identifier,title,creator,year,date,mediatype',
        'rows': '${BuiltInSourceConfig.pageSize}',
        'page': '${request.page}',
        'output': 'json',
      },
    );
    final body = await _readJson(uri, request.cancellation);
    final root = _decodeJson(body, message: AppStrings.t('source.archive.badSearch'));
    final response = root is Map ? root['response'] : null;
    final docs = response is Map ? response['docs'] : null;
    if (docs is! List) {
      throw SourceException(
        AppStrings.t('source.archive.badSearch'),
        retryable: true,
        code: 'invalid_catalog_response',
      );
    }
    return SearchPage(items: [for (final entry in docs) ?_summaryFrom(entry)]);
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) => CatalogTrack(
    id: summary.ref.itemId,
    title: summary.title,
    artist: summary.artist,
    sourceId: descriptor.id,
    sourceName: descriptor.name,
    duration: summary.duration ?? Duration.zero,
    quality: AppStrings.t('quality.publicAudio'),
  );

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(AppStrings.t('source.err.refMismatch'));
    }
    var fileName = _fileNames[request.ref.itemId];
    if (fileName == null) {
      await prepareItem(request.ref.itemId, request.cancellation);
      fileName = _fileNames[request.ref.itemId];
    }
    if (fileName == null || fileName.isEmpty) {
      throw SourceException(
        AppStrings.t('source.archive.expired'),
        retryable: true,
        code: 'media_reference_expired',
      );
    }
    final uri = BuiltInSourceConfig.archive.uri(
      'download',
      pathValues: {'id': request.ref.itemId, 'file': fileName},
    );
    return ResolvedStream(uri: uri);
  }

  TrackSummary? _summaryFrom(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['identifier']?.toString().trim();
    final title = _text(entry['title']) ?? id;
    if (id == null || id.isEmpty || title == null || title.isEmpty) return null;
    final creator = _text(entry['creator']);
    return TrackSummary(
      ref: MediaRef(sourceId: descriptor.id, itemId: id),
      title: title,
      artist: creator?.isNotEmpty == true ? creator! : descriptor.name,
      duration: _duration(entry['duration']),
    );
  }

  Duration? _duration(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final parts = text.split(':').map(int.tryParse).toList(growable: false);
    if (parts.any((part) => part == null)) return null;
    if (parts.length == 2) {
      return Duration(minutes: parts[0]!, seconds: parts[1]!);
    }
    if (parts.length == 3) {
      return Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!);
    }
    return Duration(seconds: int.tryParse(text) ?? 0);
  }

  String? _text(Object? value) {
    if (value is List) {
      final values = value
          .map((item) => item?.toString().trim())
          .whereType<String>()
          .where((item) => item.isNotEmpty);
      return values.isEmpty ? null : values.join(', ');
    }
    final text = value?.toString().trim();
    return text?.isNotEmpty == true ? text : null;
  }

  /// Resolve metadata only for a selected item. Kept separate from search so
  /// a catalogue page never triggers one metadata call per result.
  Future<void> prepareItem(
    String identifier,
    CancellationToken cancellation,
  ) async {
    final uri = BuiltInSourceConfig.archive.uri(
      'metadata',
      pathValues: {'id': identifier},
    );
    final body = await _readJson(uri, cancellation);
    final root = _decodeJson(body, message: AppStrings.t('source.archive.badMetadata'));
    final files = root is Map ? root['files'] : null;
    if (files is! List) {
      throw SourceException(
        AppStrings.t('source.archive.noFiles'),
        retryable: true,
        code: 'invalid_item_metadata',
      );
    }
    final candidate = files
        .cast<Object?>()
        .map(_audioFile)
        .whereType<String>()
        .firstOrNull;
    if (candidate == null) {
      throw SourceException(
        AppStrings.t('source.archive.noAudio'),
        retryable: false,
        code: 'audio_file_unavailable',
      );
    }
    _fileNames[identifier] = candidate;
  }

  String? _audioFile(Object? value) {
    if (value is! Map || _isPrivate(value['private'])) return null;
    final name = value['name']?.toString().trim();
    if (name == null || name.isEmpty) return null;
    final format = value['format']?.toString().toLowerCase() ?? '';
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (!_audioFormats.contains(format) && !_audioFormats.contains(extension)) {
      return null;
    }
    return name;
  }

  bool _isPrivate(Object? value) {
    final text = value?.toString().toLowerCase();
    return text == '1' || text == 'true';
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
        AppStrings.t('source.errRespTimeout'),
        retryable: true,
      );
    } on SocketException {
      throw SourceException(
        AppStrings.t('source.errNetworkRetry'),
        retryable: true,
      );
    } on FormatException {
      throw SourceException(
        AppStrings.t('source.errBadSearch'),
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
      if (response.statusCode != HttpStatus.ok) {
        throw SourceException(
          AppStrings.t('source.errUnavailableRetry'),
          retryable: true,
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        cancellation.throwIfCancelled();
        bytes.add(chunk);
        if (bytes.length > _policy.maxResponseBytes) {
          throw SourceException(
            AppStrings.t('source.errRespTooLarge'),
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
      throw StateError(AppStrings.t('source.err.unregisteredFmt').replaceFirst('{id}', request.ref.sourceId));
    }
    return source.resolve(request);
  }
}
