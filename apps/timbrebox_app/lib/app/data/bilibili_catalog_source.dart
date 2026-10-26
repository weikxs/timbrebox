part of 'video_source_adapters.dart';

/// Bilibili's public search/play path. Anonymous response cookies are kept in
/// memory only; a 412/security response is surfaced as source_unavailable.
final class BilibiliCatalogSource implements CatalogSource {
  BilibiliCatalogSource({SourceHttpClient? http})
    : _http = http ?? SourceHttpClient();

  final SourceHttpClient _http;
  final MemoryCookieJar _cookies = MemoryCookieJar();

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: 'bilibili',
    name: '哔哩哔哩',
    capabilities: const [SourceCapability.search, SourceCapability.streaming],
  );

  /// Bilibili's edge blocks the first request with an HTML risk-control page
  /// unless a `buvid` cookie is present. The finger/spi endpoint hands one out
  /// anonymously; search then passes with a browser UA + that cookie.
  Future<void> _ensureBuvid(CancellationToken cancellation) async {
    if (_cookies.contains('buvid3')) return;
    try {
      final text = await _http.get(
        BuiltInSourceConfig.bilibili.uri('finger'),
        cancellation,
        headers: const {'User-Agent': BuiltInSourceConfig.browserUserAgent},
      );
      final data = _mapValue(jsonDecode(text), 'data');
      final buvid3 = _mapValue(data, 'b_3')?.toString();
      final buvid4 = _mapValue(data, 'b_4')?.toString();
      if (buvid3 != null && buvid3.isNotEmpty) _cookies.set('buvid3', buvid3);
      if (buvid4 != null && buvid4.isNotEmpty) _cookies.set('buvid4', buvid4);
    } catch (_) {
      // Best effort: if the handshake fails, search still attempts and its
      // own error handling reports an honest failure.
    }
  }

  @override
  Future<SearchPage> search(SearchRequest request) async {
    await _ensureBuvid(request.cancellation);
    final uri = BuiltInSourceConfig.bilibili.uri(
      'search',
      query: {
        'search_type': 'video',
        'keyword': request.query,
        'page_size': '${BuiltInSourceConfig.pageSize}',
        'page': '${request.page}',
      },
    );
    final text = await _http.get(
      uri,
      request.cancellation,
      headers: const {
        'User-Agent': BuiltInSourceConfig.browserUserAgent,
        'Referer': BuiltInSourceConfig.bilibiliReferer,
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
      cookies: _cookies,
      maxResponseBytes: BuiltInSourceConfig.videoApiMaxResponseBytes,
    );
    final data = jsonDecode(text);
    final results = _mapValue(_mapValue(data, 'data'), 'result');
    if (results is! List) return const SearchPage(items: []);
    return SearchPage(items: [for (final value in results) ?_summary(value)]);
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) => CatalogTrack(
    id: summary.ref.itemId,
    title: summary.title,
    artist: summary.artist,
    sourceId: descriptor.id,
    sourceName: descriptor.name,
    duration: summary.duration ?? Duration.zero,
    quality: 'Bilibili public stream',
  );

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    final bvid = request.ref.itemId;
    final viewUri = BuiltInSourceConfig.bilibili.uri(
      'view',
      query: {'bvid': bvid},
    );
    final view = jsonDecode(
      await _http.get(
        viewUri,
        request.cancellation,
        headers: const {'User-Agent': BuiltInSourceConfig.browserUserAgent},
        maxResponseBytes: BuiltInSourceConfig.videoApiMaxResponseBytes,
      ),
    );
    final pages = _mapValue(_mapValue(view, 'data'), 'pages');
    final firstPage = pages is List && pages.isNotEmpty ? pages.first : null;
    final cid = _mapValue(firstPage, 'cid')?.toString();
    if (cid == null || cid.isEmpty) {
      throw SourceException(
        AppStrings.t('source.bilibili.noPart'),
        retryable: false,
        code: 'source_stream_unavailable',
      );
    }
    final playUri = BuiltInSourceConfig.bilibili.uri(
      'play',
      query: {'bvid': bvid, 'cid': cid, 'fnval': '16'},
    );
    final play = jsonDecode(
      await _http.get(
        playUri,
        request.cancellation,
        headers: const {'User-Agent': BuiltInSourceConfig.browserUserAgent},
        maxResponseBytes: BuiltInSourceConfig.videoApiMaxResponseBytes,
      ),
    );
    final audio = _mapValue(
      _mapValue(_mapValue(play, 'data'), 'dash'),
      'audio',
    );
    final firstAudio = audio is List && audio.isNotEmpty ? audio.first : null;
    final url = _mapValue(firstAudio, 'baseUrl');
    final stream = Uri.tryParse(url?.toString() ?? '');
    if (stream == null || stream.scheme != 'https') {
      throw SourceException(
        AppStrings.t('source.bilibili.noSecureStream'),
        retryable: false,
        code: 'source_stream_unavailable',
      );
    }
    return ResolvedStream(
      uri: stream,
      headers: const {
        'Referer': BuiltInSourceConfig.bilibiliReferer,
        'User-Agent': BuiltInSourceConfig.browserUserAgent,
      },
      mimeType: 'audio/mp4',
      expiresAt: _expiry(stream),
    );
  }

  TrackSummary? _summary(Object? value) {
    if (value is! Map) return null;
    final bvid = value['bvid']?.toString();
    final title = _stripHtml(value['title']?.toString() ?? '').trim();
    final artist = _stripHtml(value['author']?.toString() ?? '').trim();
    final duration = _duration(value['duration']?.toString() ?? '');
    if (bvid == null || bvid.isEmpty || title.isEmpty) return null;
    return TrackSummary(
      ref: MediaRef(sourceId: descriptor.id, itemId: bvid),
      title: title,
      artist: artist.isEmpty ? descriptor.name : artist,
      duration: duration,
    );
  }
}
