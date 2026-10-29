part of 'music_catalog.dart';

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
    final decoded = _decodeJson(
      body,
      message: SourceStrings.t('source.audius.badSearch'),
    );
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) {
      throw SourceException(
        SourceStrings.t('source.audius.badSearch'),
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
    final decoded = _decodeJson(
      body,
      message: SourceStrings.t('source.audius.badChart'),
    );
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) {
      throw SourceException(
        SourceStrings.t('source.audius.badChart'),
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
    quality: SourceStrings.t('quality.publicStream'),
    artworkUrl: _artwork[summary.ref.itemId],
  );

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(SourceStrings.t('source.err.refMismatch'));
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
      final url =
          artwork['480x480'] ?? artwork['1000x1000'] ?? artwork['150x150'];
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
    final data = _decodeJson(
      body,
      message: SourceStrings.t('source.radio.badResponse'),
    );
    if (data is! List) {
      throw SourceException(
        SourceStrings.t('source.radio.badResponse'),
        retryable: true,
        code: 'invalid_catalog_response',
      );
    }
    return SearchPage(items: [for (final entry in data) ?_summaryFrom(entry)]);
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) {
    if (!_streams.containsKey(summary.ref.itemId)) {
      throw StateError(SourceStrings.t('source.radio.expired'));
    }
    return CatalogTrack(
      id: summary.ref.itemId,
      title: summary.title,
      artist: summary.artist,
      sourceId: descriptor.id,
      sourceName: descriptor.name,
      duration: Duration.zero,
      quality: SourceStrings.t('quality.liveRadio'),
    );
  }

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(SourceStrings.t('source.err.refMismatch'));
    }
    // After a restart nothing was searched yet: look the station up by id.
    final value =
        _streams[request.ref.itemId] ??
        await _lookUpStation(request.ref.itemId, request.cancellation);
    final uri = Uri.tryParse(value ?? '');
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
      throw SourceException(
        SourceStrings.t('source.radio.expired'),
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
      message: SourceStrings.t('source.radio.badResponse'),
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
    final root = _decodeJson(
      body,
      message: SourceStrings.t('source.archive.badSearch'),
    );
    final response = root is Map ? root['response'] : null;
    final docs = response is Map ? response['docs'] : null;
    if (docs is! List) {
      throw SourceException(
        SourceStrings.t('source.archive.badSearch'),
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
    quality: SourceStrings.t('quality.publicAudio'),
  );

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(SourceStrings.t('source.err.refMismatch'));
    }
    var fileName = _fileNames[request.ref.itemId];
    if (fileName == null) {
      await prepareItem(request.ref.itemId, request.cancellation);
      fileName = _fileNames[request.ref.itemId];
    }
    if (fileName == null || fileName.isEmpty) {
      throw SourceException(
        SourceStrings.t('source.archive.expired'),
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
    final root = _decodeJson(
      body,
      message: SourceStrings.t('source.archive.badMetadata'),
    );
    final files = root is Map ? root['files'] : null;
    if (files is! List) {
      throw SourceException(
        SourceStrings.t('source.archive.noFiles'),
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
        SourceStrings.t('source.archive.noAudio'),
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
