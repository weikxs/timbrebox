import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import '../data/catalog_source.dart';
import '../data/stream_header_proxy.dart';
import '../model/catalog_track.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

/// Exposes a loaded plugin as a first-class catalog source.
///
/// It adapts the plugin's JS `search` / `getMediaSource` to TimbreBox's models.
/// The original JS music item is retained per id because `getMediaSource` needs
/// the full item (with plugin-private fields), not just the id. Streams that
/// require request headers are routed through the loopback proxy so media_kit
/// can play them.
final class PluginCatalogSource implements CatalogSource {
  PluginCatalogSource({
    required this.manifest,
    required PluginRuntime runtime,
    StreamHeaderProxy? proxy,
  }) : _proxy = proxy ?? StreamHeaderProxy(),
       // ignore: prefer_initializing_formals
       _runtime = runtime;

  final PluginManifest manifest;
  final PluginRuntime _runtime;
  final StreamHeaderProxy _proxy;
  final Map<String, Map<String, Object?>> _items = {};
  final Map<String, Map<String, Object?>> _topListItems = {};
  final Map<String, String> _artwork = {};

  bool get hasTopLists => _runtime.hasFunction('getTopLists');
  bool get hasLyric => _runtime.hasFunction('getLyric');

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: manifest.id,
    name: manifest.platform,
    capabilities: [
      if (_runtime.hasFunction('search')) SourceCapability.search,
      if (_runtime.hasFunction('getMediaSource')) SourceCapability.streaming,
      if (_runtime.hasFunction('getLyric')) SourceCapability.lyrics,
    ],
  );

  @override
  Future<SearchPage> search(SearchRequest request) async {
    final Object? raw;
    try {
      raw = await _runtime.call('search', [request.query, request.page, 'music']);
    } catch (error) {
      throw SourceException(
        AppStrings.t('plugin.src.searchFailed').replaceFirst('{e}', '$error'),
        retryable: true,
        code: 'plugin_error',
      );
    }
    if (raw is! Map) return const SearchPage(items: []);
    final data = raw['data'];
    if (data is! List) return const SearchPage(items: []);
    final items = <TrackSummary>[];
    for (final entry in data) {
      final summary = _summaryFrom(entry);
      if (summary != null) items.add(summary);
    }
    final isEnd = raw['isEnd'] == true;
    return SearchPage(
      items: items,
      nextCursor: isEnd ? null : '${request.page + 1}',
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
    quality: AppStrings.t('plugin.src.qualityFmt').replaceFirst('{p}', manifest.platform),
    artworkUrl: _artwork[summary.ref.itemId],
  );

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    request.cancellation.throwIfCancelled();
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(AppStrings.t('plugin.src.refMismatch'));
    }
    final item = _items[request.ref.itemId];
    if (item == null) {
      throw SourceException(
        AppStrings.t('plugin.src.expired'),
        retryable: true,
        code: 'media_reference_expired',
      );
    }
    // Try the common qualities in order — some plugins only expose high/super,
    // so pinning 'standard' would wrongly report "no playable url".
    Object? raw;
    try {
      for (final quality in const ['standard', 'high', 'super', 'low']) {
        raw = await _runtime.call('getMediaSource', [item, quality]);
        if (raw is Map && (raw['url']?.toString().isNotEmpty ?? false)) break;
      }
    } catch (error) {
      throw SourceException(
        AppStrings.t('plugin.src.resolveFailed').replaceFirst('{e}', '$error'),
        retryable: true,
        code: 'plugin_error',
      );
    }
    if (raw is! Map) {
      throw SourceException(
        AppStrings.t('plugin.src.noUrl'),
        retryable: false,
        code: 'source_stream_unavailable',
      );
    }
    final url = raw['url']?.toString();
    final parsed = Uri.tryParse(url ?? '');
    if (url == null || url.isEmpty || parsed == null) {
      throw SourceException(
        AppStrings.t('plugin.src.noUrl'),
        retryable: false,
        code: 'source_stream_unavailable',
      );
    }
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        headers[key.toString()] = value?.toString() ?? '';
      });
    }
    final userAgent = raw['userAgent']?.toString();
    if (userAgent != null && userAgent.isNotEmpty) {
      headers['User-Agent'] = userAgent;
    }
    // Header-gated streams can't be opened by media_kit directly — relay them
    // through the loopback proxy which injects the headers per hop.
    if (headers.isNotEmpty) {
      final local = await _proxy.publish(parsed, headers);
      return ResolvedStream(uri: local, mimeType: _mimeType(url));
    }
    return ResolvedStream(uri: parsed, mimeType: _mimeType(url));
  }

  /// Flattens the plugin's `getTopLists` groups into a single list of charts.
  Future<List<PluginTopListItem>> topLists() async {
    if (!hasTopLists) return const [];
    final raw = await _runtime.call('getTopLists', const []);
    if (raw is! List) return const [];
    final items = <PluginTopListItem>[];
    for (final group in raw) {
      final data = group is Map ? group['data'] : null;
      if (data is! List) continue;
      for (final entry in data) {
        if (entry is! Map) continue;
        final id = entry['id']?.toString();
        final title = entry['title']?.toString();
        if (id == null || title == null || title.isEmpty) continue;
        _topListItems[id] = Map<String, Object?>.from(entry);
        items.add(
          PluginTopListItem(
            sourceId: descriptor.id,
            sourceName: descriptor.name,
            id: id,
            title: title,
            cover: (entry['coverImg'] ?? entry['artwork'] ?? entry['pic'])
                ?.toString(),
          ),
        );
      }
    }
    return items;
  }

  /// Loads one chart's tracks via `getTopListDetail`.
  Future<List<TrackSummary>> topListDetail(String listId) async {
    final item = _topListItems[listId];
    if (item == null || !_runtime.hasFunction('getTopListDetail')) {
      return const [];
    }
    final raw = await _runtime.call('getTopListDetail', [item, 1]);
    if (raw is! Map) return const [];
    final list = raw['musicList'] ?? raw['data'];
    if (list is! List) return const [];
    final tracks = <TrackSummary>[];
    for (final entry in list) {
      final summary = _summaryFrom(entry);
      if (summary != null) tracks.add(summary);
    }
    return tracks;
  }

  /// Returns the plugin's lyric text for [itemId], if it provides one.
  Future<String?> lyric(String itemId) async {
    final item = _items[itemId];
    if (item == null || !hasLyric) return null;
    final raw = await _runtime.call('getLyric', [item]);
    if (raw is! Map) return null;
    final value = raw['rawLrc'] ?? raw['lrc'] ?? raw['lyric'];
    final text = value?.toString();
    return text == null || text.isEmpty ? null : text;
  }

  TrackSummary? _summaryFrom(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id']?.toString();
    final title = entry['title']?.toString().trim();
    if (id == null || id.isEmpty || title == null || title.isEmpty) return null;
    _items[id] = Map<String, Object?>.from(entry);
    final artwork = entry['artwork'] ?? entry['coverImg'] ?? entry['pic'];
    if (artwork is String && artwork.isNotEmpty) _artwork[id] = artwork;
    final artist = entry['artist']?.toString().trim();
    return TrackSummary(
      ref: MediaRef(sourceId: descriptor.id, itemId: id),
      title: title,
      artist: artist?.isNotEmpty == true ? artist! : descriptor.name,
      duration: _duration(entry['duration']),
    );
  }

  Duration? _duration(Object? value) {
    if (value is num) return Duration(seconds: value.round());
    final text = value?.toString();
    final seconds = text == null ? null : num.tryParse(text);
    return seconds == null ? null : Duration(seconds: seconds.round());
  }

  String? _mimeType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m4a') || lower.contains('.mp4')) return 'audio/mp4';
    if (lower.contains('.mp3')) return 'audio/mpeg';
    if (lower.contains('.flac')) return 'audio/flac';
    if (lower.contains('.ogg')) return 'audio/ogg';
    return null;
  }

  void dispose() {
    _runtime.dispose();
    _proxy.dispose();
  }
}

/// One chart/top-list entry surfaced by a plugin's `getTopLists`.
class PluginTopListItem {
  const PluginTopListItem({
    required this.sourceId,
    required this.sourceName,
    required this.id,
    required this.title,
    this.cover,
  });

  final String sourceId;
  final String sourceName;
  final String id;
  final String title;
  final String? cover;
}
