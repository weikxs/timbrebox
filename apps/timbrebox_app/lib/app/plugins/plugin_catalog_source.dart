import 'dart:async';

import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import '../data/catalog_source.dart';
import '../data/stream_header_proxy.dart';
import '../model/catalog_track.dart';
import '../net/egress_policy.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'plugin_stream_url.dart';

/// Exposes a plugin as a first-class catalog source.
///
/// It adapts the plugin's JS `search` / `getMediaSource` to TimbreBox's models.
/// The original JS music item is retained per id because `getMediaSource` needs
/// the full item (with plugin-private fields), not just the id. Streams that
/// require request headers are routed through the loopback proxy so media_kit
/// can play them.
///
/// The JS engine starts on the first call that needs it
/// ([PluginCatalogSource.lazy]), so installed plugins cost nothing at launch
/// and disabled ones never start; capabilities come from the functions
/// recorded in the manifest, never from evaluating JS on a read.
final class PluginCatalogSource implements CatalogSource {
  /// Wraps an already loaded [runtime] (a fresh install).
  PluginCatalogSource({
    required PluginManifest manifest,
    required PluginRuntime runtime,
    StreamHeaderProxy? proxy,
    EgressPolicy policy = const EgressPolicy(),
  }) : this._(
         manifest: manifest,
         functions: exportedFunctions(runtime),
         loadRuntime: () async => runtime,
         proxy: proxy,
         policy: policy,
         idleTimeout: null,
       );

  /// Starts the plugin's runtime with [loadRuntime] on first use, and shuts
  /// it down again after [idleTimeout] without a call (the next call starts
  /// a fresh one).
  PluginCatalogSource.lazy({
    required PluginManifest manifest,
    required Set<String> functions,
    required Future<PluginRuntime> Function() loadRuntime,
    StreamHeaderProxy? proxy,
    EgressPolicy policy = const EgressPolicy(),
    Duration idleTimeout = defaultIdleTimeout,
  }) : this._(
         manifest: manifest,
         functions: functions,
         loadRuntime: loadRuntime,
         proxy: proxy,
         policy: policy,
         idleTimeout: idleTimeout,
       );

  PluginCatalogSource._({
    required this.manifest,
    required Set<String> functions,
    required Future<PluginRuntime> Function() loadRuntime,
    StreamHeaderProxy? proxy,
    required EgressPolicy policy,
    required Duration? idleTimeout,
  }) : _functions = Set.unmodifiable(functions),
       // ignore: prefer_initializing_formals
       _idleTimeout = idleTimeout,
       // ignore: prefer_initializing_formals
       _loadRuntime = loadRuntime,
       _proxy = proxy ?? StreamHeaderProxy(policy: policy),
       _ownsProxy = proxy == null,
       // ignore: prefer_initializing_formals
       _policy = policy;

  /// The plugin functions TimbreBox calls; see [PluginManifest.functions].
  static const knownFunctions = [
    'search',
    'getMediaSource',
    'getLyric',
    'getTopLists',
    'getTopListDetail',
  ];

  /// Which of [knownFunctions] the plugin loaded in [runtime] exports.
  static Set<String> exportedFunctions(PluginRuntime runtime) => {
    for (final name in knownFunctions)
      if (runtime.hasFunction(name)) name,
  };

  /// How long an engine may sit unused before it is shut down.
  static const defaultIdleTimeout = Duration(minutes: 5);

  final PluginManifest manifest;
  final Set<String> _functions;
  final Future<PluginRuntime> Function() _loadRuntime;
  Future<PluginRuntime>? _runtime;
  var _disposed = false;

  /// Null keeps the engine for the source's lifetime (a runtime handed to
  /// the constructor cannot be started again once released).
  final Duration? _idleTimeout;
  Timer? _idleTimer;
  var _activeCalls = 0;
  final StreamHeaderProxy _proxy;

  /// False when the proxy is shared (see [PluginRepository.streamProxy]):
  /// a track still playing from it must outlive this source.
  final bool _ownsProxy;

  /// Checks the stream URL a plugin hands back before anything opens it.
  final EgressPolicy _policy;
  final Map<String, Map<String, Object?>> _items = {};
  final Map<String, Map<String, Object?>> _topListItems = {};
  final Map<String, String> _artwork = {};

  bool get hasTopLists => _functions.contains('getTopLists');
  bool get hasLyric => _functions.contains('getLyric');

  /// Whether the plugin's JS engine has been started.
  bool get isStarted => _runtime != null;

  @override
  late final SourceDescriptor descriptor = SourceDescriptor(
    id: manifest.id,
    name: manifest.platform,
    capabilities: [
      if (_functions.contains('search')) SourceCapability.search,
      if (_functions.contains('getMediaSource')) SourceCapability.streaming,
      if (_functions.contains('getLyric')) SourceCapability.lyrics,
    ],
  );

  /// Calls a plugin function, starting the runtime first if needed.
  Future<Object?> _call(String function, List<Object?> args) async {
    _idleTimer?.cancel();
    _activeCalls++;
    try {
      final runtime = await _started();
      return await runtime.call(function, args);
    } on PluginScriptTimeout {
      // A script stopped mid-run may have left the engine in any state:
      // the next call starts a fresh one.
      if (_idleTimeout != null) _discardEngine();
      rethrow;
    } finally {
      _activeCalls--;
      _scheduleIdleStop();
    }
  }

  void _scheduleIdleStop() {
    final timeout = _idleTimeout;
    if (timeout == null || _activeCalls > 0 || _disposed) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(timeout, _stopIdleEngine);
  }

  /// Releases an engine nobody has used for [_idleTimeout]; the metadata,
  /// search items and charts stay, so the next call simply starts it again.
  void _stopIdleEngine() {
    if (_activeCalls == 0) _discardEngine();
  }

  void _discardEngine() {
    final runtime = _runtime;
    _runtime = null;
    runtime?.then((engine) => engine.dispose(), onError: (_) {});
  }

  Future<PluginRuntime> _started() {
    if (_disposed) throw StateError(AppStrings.t('plugin.src.disposed'));
    return _runtime ??= _start();
  }

  Future<PluginRuntime> _start() async {
    final PluginRuntime runtime;
    try {
      runtime = await _loadRuntime();
    } catch (_) {
      _runtime = null; // A failed start is retried on the next call.
      rethrow;
    }
    // Disposed while the engine was starting: release it right away.
    if (_disposed) {
      runtime.dispose();
      throw StateError(AppStrings.t('plugin.src.disposed'));
    }
    return runtime;
  }

  @override
  Future<SearchPage> search(SearchRequest request) async {
    final Object? raw;
    try {
      raw = await _call('search', [request.query, request.page, 'music']);
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
        // A newer track was chosen: stop trying further qualities.
        request.cancellation.throwIfCancelled();
        raw = await _call('getMediaSource', [item, quality]);
        if (raw is Map && (raw['url']?.toString().isNotEmpty ?? false)) break;
      }
    } on OperationCancelled {
      rethrow;
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
    final parsed = await checkedPluginStreamUri(url, policy: _policy);
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
    // Every plugin stream is relayed through the loopback proxy, headers or
    // not: it injects the headers per hop, and its client vets each redirect
    // hop against the egress policy, which libmpv opening the URL itself
    // would not.
    final local = await _proxy.publish(parsed, headers);
    return ResolvedStream(uri: local, mimeType: _mimeType(url!));
  }

  /// Flattens the plugin's `getTopLists` groups into a single list of charts.
  Future<List<PluginTopListItem>> topLists() async {
    if (!hasTopLists) return const [];
    final raw = await _call('getTopLists', const []);
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
    if (item == null || !_functions.contains('getTopListDetail')) {
      return const [];
    }
    final raw = await _call('getTopListDetail', [item, 1]);
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
    final raw = await _call('getLyric', [item]);
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
    _disposed = true;
    _idleTimer?.cancel();
    _runtime?.then((runtime) => runtime.dispose(), onError: (_) {});
    if (_ownsProxy) _proxy.dispose();
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
