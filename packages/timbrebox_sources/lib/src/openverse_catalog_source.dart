part of 'music_catalog.dart';

/// Openly licensed music gathered by Openverse from Jamendo, Freesound,
/// Wikimedia Commons and ccMixter, searched without an account.
///
/// Anonymous requests get at most 20 results a page and 240 results deep
/// (and a daily request budget), so later pages end honestly empty. Every
/// track is labelled with its licence; mature tracks and audio not served
/// over HTTPS are left out.
class OpenverseCatalogSource implements CatalogSource {
  OpenverseCatalogSource({
    HttpClient Function()? clientFactory,
    JsonReader? readJson,
  }) : _readJson =
           readJson ?? JsonHttpClient(clientFactory: clientFactory).read;

  static const _pageSize = 20;
  static const _maxDepth = 240;

  final JsonReader _readJson;
  final _streams = BoundedCache<String, String>();
  final _licences = BoundedCache<String, String>();

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: 'openverse',
    name: 'Openverse',
    capabilities: const [SourceCapability.search, SourceCapability.streaming],
  );

  @override
  Future<SearchPage> search(SearchRequest request) async {
    if (request.page * _pageSize > _maxDepth) {
      return const SearchPage(items: []);
    }
    final uri = BuiltInSourceConfig.openverse.uri(
      'search',
      query: {
        'q': request.query,
        'category': 'music',
        'mature': 'false',
        'page': '${request.page}',
        'page_size': '$_pageSize',
      },
    );
    final root = _decodeJson(
      await _readJson(uri, request.cancellation),
      message: SourceStrings.t('source.openverse.badResponse'),
    );
    final results = root is Map ? root['results'] : null;
    if (results is! List) {
      throw SourceException(
        SourceStrings.t('source.openverse.badResponse'),
        retryable: true,
        code: 'invalid_catalog_response',
      );
    }
    return SearchPage(
      items: [for (final entry in results) ?_summaryFrom(entry)],
    );
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) => CatalogTrack(
    id: summary.ref.itemId,
    title: summary.title,
    artist: summary.artist,
    sourceId: descriptor.id,
    sourceName: descriptor.name,
    duration: summary.duration ?? Duration.zero,
    quality:
        _licences[summary.ref.itemId] ?? SourceStrings.t('quality.publicAudio'),
  );

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(SourceStrings.t('source.err.refMismatch'));
    }
    // After a restart nothing was searched yet: look the track up by id.
    final stream =
        _streams[request.ref.itemId] ??
        await _lookUp(request.ref.itemId, request.cancellation);
    if (stream == null) {
      throw SourceException(
        SourceStrings.t('source.openverse.expired'),
        retryable: false,
        code: 'media_reference_expired',
      );
    }
    return ResolvedStream(uri: Uri.parse(stream));
  }

  /// The track's audio address, by its id, or null when it is not served
  /// safely any more.
  Future<String?> _lookUp(String id, CancellationToken cancellation) async {
    final uri = BuiltInSourceConfig.openverse.uri(
      'audio',
      pathValues: {'id': id},
    );
    final entry = _decodeJson(
      await _readJson(uri, cancellation),
      message: SourceStrings.t('source.openverse.badResponse'),
    );
    return _summaryFrom(entry)?.ref.itemId == id ? _streams[id] : null;
  }

  TrackSummary? _summaryFrom(Object? entry) {
    if (entry is! Map || entry['mature'] == true) return null;
    final id = entry['id']?.toString();
    final stream = Uri.tryParse(entry['url']?.toString() ?? '');
    if (id == null || id.isEmpty || stream?.scheme != 'https') return null;
    _streams[id] = stream.toString();
    final licence = _licenceLabel(entry['license'], entry['license_version']);
    if (licence != null) _licences[id] = licence;
    final title = entry['title']?.toString().trim();
    final creator = entry['creator']?.toString().trim();
    final milliseconds = (entry['duration'] as num?)?.round();
    return TrackSummary(
      ref: MediaRef(sourceId: descriptor.id, itemId: id),
      title: title?.isNotEmpty == true ? title! : id,
      artist: creator?.isNotEmpty == true ? creator! : descriptor.name,
      duration: milliseconds == null
          ? null
          : Duration(milliseconds: milliseconds),
    );
  }

  /// "CC BY 4.0", "CC0 1.0" or "Public domain": what a listener needs to
  /// know about reusing the track.
  String? _licenceLabel(Object? licence, Object? version) {
    final name = licence?.toString().trim().toLowerCase() ?? '';
    if (name.isEmpty) return null;
    if (name == 'pdm') return SourceStrings.t('quality.publicDomain');
    final label = name == 'cc0' ? 'CC0' : 'CC ${name.toUpperCase()}';
    final number = version?.toString().trim() ?? '';
    return number.isEmpty ? label : '$label $number';
  }
}
