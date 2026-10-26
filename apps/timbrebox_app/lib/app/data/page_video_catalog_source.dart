part of 'video_source_adapters.dart';

/// Douyin's web search page embeds public result state in the HTML. We only
/// accept records and play URLs actually returned by that page.
final class DouyinCatalogSource extends _PageVideoCatalogSource {
  DouyinCatalogSource({super.http})
    : super(
        id: 'douyin',
        name: '抖音',
        endpoint: BuiltInSourceConfig.douyin,
        referer: 'https://www.douyin.com/',
      );

  @override
  Uri searchUri(String query) => endpoint.uri(
    'search',
    pathValues: {'query': query},
    query: const {'type': 'general'},
  );

  @override
  Uri pageUri(String id, {String? handle}) =>
      endpoint.uri('video', pathValues: {'id': id});
}

/// TikTok's public web search page uses the same page-state approach. It is
/// parsed locally and never calls an account or token endpoint.
final class TikTokCatalogSource extends _PageVideoCatalogSource {
  TikTokCatalogSource({super.http})
    : super(
        id: 'tiktok',
        name: 'TikTok',
        endpoint: BuiltInSourceConfig.tiktok,
        referer: 'https://www.tiktok.com/',
      );

  @override
  Uri searchUri(String query) =>
      endpoint.uri('search', query: {'q': query, 'lang': 'en'});

  @override
  Uri pageUri(String id, {String? handle}) =>
      endpoint.uri('video', pathValues: {'author': handle ?? '', 'id': id});
}

abstract base class _PageVideoCatalogSource
    implements CatalogSource, HintedCatalogSource {
  _PageVideoCatalogSource({
    required this.http,
    required this.id,
    required this.name,
    required this.endpoint,
    required this.referer,
  });

  final SourceHttpClient? http;
  final String id;
  final String name;
  final SourceEndpoint endpoint;
  final String referer;
  final _records = BoundedCache<String, _PageVideoRecord>();

  /// Video pages of saved tracks, from their resolve hints.
  final _pages = BoundedCache<String, Uri>();
  late final SourceHttpClient _client = http ?? SourceHttpClient();

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: id,
    name: name,
    capabilities: const [SourceCapability.search, SourceCapability.streaming],
  );

  Uri searchUri(String query);

  /// The public page of video [id] (by its author's [handle] where the
  /// site's URL needs one).
  Uri pageUri(String id, {String? handle});

  @override
  Future<SearchPage> search(SearchRequest request) async {
    // The embedded page state is a single batch; later pages would require a
    // paging endpoint we do not call, so they are honestly empty.
    if (request.page > 1) return const SearchPage(items: []);
    final text = await _client.get(
      searchUri(request.query),
      request.cancellation,
      headers: {'Referer': referer},
    );
    final records = await _parsePage(text, sourceId: id);
    if (records.isEmpty) {
      throw const SourceException(
        '该音源当前没有返回可播放的公开搜索结果。',
        retryable: true,
        code: 'source_no_public_results',
      );
    }
    for (final record in records) {
      _records[record.id] = record;
    }
    return SearchPage(
      items: [
        for (final record in records)
          TrackSummary(
            ref: MediaRef(sourceId: id, itemId: record.id),
            title: record.title,
            artist: record.artist,
            duration: record.duration,
          ),
      ],
    );
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) => CatalogTrack(
    id: summary.ref.itemId,
    title: summary.title,
    artist: summary.artist,
    sourceId: id,
    sourceName: name,
    duration: summary.duration ?? Duration.zero,
    quality: '$name public stream',
    resolveHint: {
      'page': pageUri(
        summary.ref.itemId,
        handle: _records[summary.ref.itemId]?.handle,
      ).toString(),
    },
  );

  @override
  void rememberHint(String itemId, Map<String, Object?> hint) {
    final page = Uri.tryParse('${hint['page']}');
    // Only this source's own site: the hint is read back from a file.
    if (page != null && page.scheme == 'https' && page.host == endpoint.host) {
      _pages[itemId] = page;
    }
  }

  /// Reads the record for [id] from its video page (a saved track after a
  /// restart, when no search has filled [_records]).
  Future<_PageVideoRecord?> _recordFromPage(
    String id,
    CancellationToken cancellation,
  ) async {
    final text = await _client.get(
      _pages[id] ?? pageUri(id),
      cancellation,
      headers: {'Referer': referer},
    );
    for (final record in await _parsePage(text, sourceId: this.id)) {
      if (record.id == id) return _records[id] = record;
    }
    return null;
  }

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != id) {
      throw StateError('音源引用与解析器不匹配。');
    }
    final record =
        _records[request.ref.itemId] ??
        await _recordFromPage(request.ref.itemId, request.cancellation);
    final uri = Uri.tryParse(record?.streamUrl ?? '');
    if (uri == null || uri.scheme != 'https') {
      throw const SourceException(
        '该音源未返回可直接播放的公开音频流。',
        retryable: false,
        code: 'source_stream_unavailable',
      );
    }
    return ResolvedStream(
      uri: uri,
      headers: {'Referer': referer},
      expiresAt: _expiry(uri),
    );
  }
}

final class _PageVideoRecord {
  const _PageVideoRecord({
    required this.id,
    required this.title,
    required this.artist,
    required this.streamUrl,
    this.duration,
    this.handle,
  });

  final String id;
  final String title;
  final String artist;
  final String? streamUrl;
  final Duration? duration;

  /// The author's account name, where the page URL needs it (TikTok).
  final String? handle;
}

/// Pages above this size are parsed on a background isolate: decoding up to
/// a megabyte of embedded JSON would otherwise block the UI for tens of ms.
const _backgroundParseChars = 64 * 1024;

/// Parses [text] once into a list (the lazy [_pageRecords] would re-run the
/// whole scan for every pass over it).
Future<List<_PageVideoRecord>> _parsePage(
  String text, {
  required String sourceId,
}) async {
  if (text.length < _backgroundParseChars) {
    return _pageRecords(text, sourceId: sourceId).toList();
  }
  return Isolate.run(() => _pageRecords(text, sourceId: sourceId).toList());
}

Iterable<_PageVideoRecord> _pageRecords(
  String text, {
  required String sourceId,
}) sync* {
  final seen = <String>{};
  const markers = <String>[
    '"aweme_id":',
    '"itemStruct":',
    '"videoId":',
    '"itemInfo":',
    '__UNIVERSAL_DATA_FOR_REHYDRATION__',
  ];
  for (final marker in markers) {
    for (final object in _jsonObjects(text, marker)) {
      for (final map in _nestedMaps(object)) {
        final record = _recordFromMap(map, sourceId: sourceId);
        if (record == null || !seen.add(record.id)) continue;
        yield record;
        if (seen.length == BuiltInSourceConfig.pageSize) return;
      }
    }
  }
}

_PageVideoRecord? _recordFromMap(
  Map<String, dynamic> map, {
  required String sourceId,
}) {
  final media = _firstValue(map, const [
    'video',
    'videoData',
    'itemStruct',
    'play_addr',
    'playAddr',
    'downloadAddr',
  ]);
  if (media == null) return null;
  final id = _firstText(map, const ['aweme_id', 'itemId', 'videoId', 'id']);
  final title = _firstText(map, const [
    'desc',
    'description',
    'title',
    'contents',
  ]);
  if (id == null || id.isEmpty || title == null || title.isEmpty) return null;
  final author =
      _firstText(map, const ['authorName', 'nickname', 'unique_id']) ??
      _firstText(_firstValue(map, const ['author']), const [
        'nickname',
        'unique_id',
        'name',
      ]);
  final durationValue =
      _firstValue(map, const ['duration', 'durationMs']) ??
      (media is Map
          ? _firstValue(
              <String, dynamic>{
                for (final entry in media.entries) '${entry.key}': entry.value,
              },
              const ['duration', 'durationMs'],
            )
          : null);
  final durationNumber = durationValue is num ? durationValue.round() : null;
  final streamUrl = _streamUrl(media);
  if (streamUrl == null) return null;
  final owner = _firstValue(map, const ['author']);
  final handle = owner is Map
      ? _firstText(owner, const ['uniqueId', 'unique_id'])
      : null;
  return _PageVideoRecord(
    handle: handle?.trim().isNotEmpty == true ? handle!.trim() : null,
    id: id,
    title: _stripHtml(title).trim(),
    artist: author?.trim().isNotEmpty == true ? author!.trim() : sourceId,
    streamUrl: streamUrl,
    duration: durationNumber == null
        ? null
        : Duration(
            milliseconds: durationNumber > 10000
                ? durationNumber
                : durationNumber * 1000,
          ),
  );
}

Iterable<Map<String, dynamic>> _nestedMaps(Object? value) sync* {
  if (value is Map) {
    final map = <String, dynamic>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
    yield map;
    for (final child in value.values) {
      yield* _nestedMaps(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* _nestedMaps(child);
    }
  }
}

Object? _firstValue(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) return value;
  }
  return null;
}

String? _firstText(Object? value, List<String> keys) {
  if (value is Map<String, dynamic>) {
    value = _firstValue(value, keys);
  } else if (value is Map) {
    value = _firstValue(<String, dynamic>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    }, keys);
  }
  if (value is String) return value;
  if (value is num) return value.toString();
  if (value is Map) {
    for (final key in const ['nickname', 'name', 'text', 'simpleText']) {
      final text = value[key];
      if (text is String && text.trim().isNotEmpty) return text;
    }
  }
  return null;
}

String? _streamUrl(Object? value) {
  if (value is String) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'https' ? value : null;
  }
  if (value is List) {
    for (final item in value) {
      final found = _streamUrl(item);
      if (found != null) return found;
    }
  }
  if (value is Map) {
    for (final key in const [
      'url_list',
      'urlList',
      'playAddr',
      'play_addr',
      'downloadAddr',
      'src',
      'url',
    ]) {
      final found = _streamUrl(value[key]);
      if (found != null) return found;
    }
  }
  return null;
}
