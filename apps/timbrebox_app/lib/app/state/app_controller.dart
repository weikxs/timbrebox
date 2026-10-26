import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

import '../data/music_catalog.dart';
import '../model/catalog_search.dart';
import '../model/catalog_track.dart';
import '../model/player_shortcut.dart';
import '../model/playlist.dart';
import '../design/app_effects.dart';
import '../design/app_strings.dart';
import '../design/app_themes.dart';
import '../plugins/plugin_catalog_source.dart';
import '../plugins/plugin_manifest.dart';
import '../plugins/plugin_repository.dart';
import 'appearance_store.dart';
import 'audio_route_monitor.dart';
import 'catalog_download_service.dart';
import 'diagnostic_log.dart';
import 'download_index_store.dart';
import 'favorites_store.dart';
import 'network_player_engine.dart';
import 'player_control_server.dart';
import 'playlist_store.dart';
import 'search_history_store.dart';
import 'session_store.dart';
import 'settings_store.dart';
import 'system_media_controls.dart';

part 'app_controller_downloads.dart';
part 'app_controller_playlists.dart';
part 'app_controller_plugins.dart';
part 'app_controller_search.dart';

class AppController extends ChangeNotifier {
  AppController({
    required PlayerEngine engine,
    MusicCatalog? catalog,
    CatalogDownloadService? downloadService,
    DownloadIndexStore? downloadStore,
    AppearanceStore? appearanceStore,
    SystemMediaControls? mediaControls,
    AudioRouteMonitor? routeMonitor,
    PluginRepository? pluginRepository,
    SettingsStore? settingsStore,
    SessionStore? sessionStore,
    FavoritesStore? favoritesStore,
    SearchHistoryStore? searchHistoryStore,
    PlaylistStore? playlistStore,
    Random? random,
  }) : _playerEngine = engine,
       // ignore: prefer_initializing_formals
       _favoritesStore = favoritesStore,
       // ignore: prefer_initializing_formals
       _searchHistoryStore = searchHistoryStore,
       // ignore: prefer_initializing_formals
       _playlistStore = playlistStore,
       // Defaults to a no-op (tests); the app injects the platform monitor via
       // createAudioRouteMonitor(), like createSystemMediaControls().
       _routeMonitor = routeMonitor ?? const NoopAudioRouteMonitor(),
       _player = PlayerController(engine),
       _catalog = catalog ?? BuiltInMusicCatalog.standard(),
       // ignore: prefer_initializing_formals
       _downloadService = downloadService,
       // ignore: prefer_initializing_formals
       _downloadStore = downloadStore,
       // ignore: prefer_initializing_formals
       _appearanceStore = appearanceStore,
       _mediaControls = mediaControls ?? const NoopMediaControls(),
       // ignore: prefer_initializing_formals
       _pluginRepository = pluginRepository,
       // ignore: prefer_initializing_formals
       _settingsStore = settingsStore,
       // ignore: prefer_initializing_formals
       _sessionStore = sessionStore,
       _random = random ?? Random() {
    _enabledSources.addAll(_catalog.sources.map((source) => source.id));
    unawaited(_restoreLibrary());
    unawaited(_restoreFavorites());
    unawaited(_restoreSearchHistory());
    unawaited(_restorePlaylists());
    unawaited(_restoreAppearance());
    unawaited(_initMediaControls());
    unawaited(_initRouteMonitor());
    unawaited(_restorePlugins());
    unawaited(_restoreSettings().then((_) => _restoreSession()));
    unawaited(_player.setVolume(_volume));
    unawaited(_player.setReleaseAfterPause(_releaseAfterPause));
    _completionSubscription = _player.completions.listen((_) {
      unawaited(_onPlaybackCompleted());
    });
    _playbackSubscription = _player.states.listen((state) {
      _playbackError = state.errorMessage;
      _syncPlaybackState();
      notifyListeners();
    });
    final PlaybackProgressEvents? progress = engine is PlaybackProgressEvents
        ? engine as PlaybackProgressEvents
        : null;
    if (progress != null) {
      _positionSubscription = progress.positions.listen((value) {
        // A paused track does not move; the only report while paused is the
        // 0 sent when the idle source is released, which must not erase the
        // paused position (shown, saved, and resumed from).
        if (_player.value.status == PlaybackStatus.paused) return;
        _position = value;
        // Keep the saved session close to where playback is, so a crash or a
        // quit resumes near the same spot.
        if ((value - _savedPosition).abs() >= _sessionSaveInterval) {
          _persistSession();
        }
        // No notifyListeners(): ticks arrive 10-50 times a second, and only
        // the widgets listening to [positionListenable] depend on them.
      });
      _durationSubscription = progress.durations.listen((value) {
        _playbackDuration = value;
        // A real duration only arrives after a stream opens; re-push it so the
        // OS media/lock-screen scrubber knows the track length.
        _syncNowPlaying();
        _syncPlaybackState();
        notifyListeners();
      });
    }
  }

  final PlaybackQueue _queue = PlaybackQueue();
  final MusicCatalog _catalog;
  final Map<String, CatalogTrack> _knownTracks = {};
  final Set<String> _favorites = {};
  final Set<String> _downloads = {};
  final Map<String, String> _downloadPaths = {};
  final Set<String> _downloading = {};
  final Map<String, String> _downloadErrors = {};
  final Set<String> _enabledSources = {};
  final PlayerEngine _playerEngine;
  final PlayerController _player;
  final CatalogDownloadService? _downloadService;
  final DownloadIndexStore? _downloadStore;
  final AppearanceStore? _appearanceStore;
  final SystemMediaControls _mediaControls;
  final PluginRepository? _pluginRepository;
  final SettingsStore? _settingsStore;
  final SessionStore? _sessionStore;
  final FavoritesStore? _favoritesStore;
  final SearchHistoryStore? _searchHistoryStore;
  final List<String> _searchHistory = [];
  static const _maxSearchHistory = 12;

  final PlaylistStore? _playlistStore;
  List<Playlist> _playlists = [];
  final List<PluginManifest> _plugins = [];
  final Map<String, PluginCatalogSource> _pluginSources = {};
  final List<PluginTopListItem> _pluginTopLists = [];
  var _pluginTopListsLoaded = false;
  late final PlayerControlServer _controlServer = PlayerControlServer(this);
  // On by default (loopback + per-session token); a saved preference overrides.
  var _agentControl = true;
  final Random _random;
  String? _skinImagePath;
  var _themeId = kDefaultThemeId;
  StreamSubscription<void>? _completionSubscription;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<MediaCommand>? _mediaCommandSubscription;
  StreamSubscription<Duration>? _mediaSeekSubscription;

  final AudioRouteMonitor _routeMonitor;
  StreamSubscription<AudioRouteEvent>? _routeSubscription;

  Timer? _sleepTimer;
  final ValueNotifier<Duration?> _sleepRemainingNotifier = ValueNotifier(null);
  Duration? get _sleepRemaining => _sleepRemainingNotifier.value;
  set _sleepRemaining(Duration? value) => _sleepRemainingNotifier.value = value;
  Duration? _sleepTotal;
  // True while playback is paused because the output device (Bluetooth /
  // headphones) went away — so we auto-resume only what we auto-paused.
  bool _pausedByRoute = false;

  /// Bumped by every [play]; see there.
  var _playGeneration = 0;

  /// The sleep timer ran out while a track was still loading.
  var _pauseWhenStarted = false;

  // A one-shot "resume where the last session left off" position for a specific
  // track, applied the first time that track is played after a restore.
  Duration? _resumePosition;
  MediaRef? _resumeRef;

  List<CatalogTrack> _results = [];
  CatalogSearchBatch? _searchBatch;
  final Map<String, List<CatalogTrack>> _pagedResults = {};
  final Map<String, int> _sourcePage = {};
  final Set<String> _sourceExhausted = {};
  final Set<String> _loadingMore = {};
  CancellationToken? _loadMoreCancellation;
  final Map<String, List<CatalogTrack>> _categoryTracks = {};
  final Set<String> _categoryLoading = {};
  final Map<String, String> _categoryErrors = {};
  CatalogTrack? _currentTrack;
  var _query = '';
  var _quality = QualityPreference.high;
  var _settingsSection = SettingsSection.general;
  var _language = '简体中文';
  var _autoPlay = true;
  var _reducedEffects = false;
  var _releaseAfterPause = true;
  var _diagnosticLogging = false;
  var _volume = .8;
  var _rate = 1.0;
  final Map<PlayerAction, ShortcutBinding> _shortcuts = defaultShortcuts();
  var _loop = PlaybackLoop.queue;
  String? _playbackError;
  String? _searchError;
  var _isSearching = false;
  var _searchGeneration = 0;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );
  Duration get _position => _positionNotifier.value;
  set _position(Duration value) => _positionNotifier.value = value;
  var _playbackDuration = Duration.zero;
  CancellationToken? _searchCancellation;
  static const _loadMoreCooldown = Duration(seconds: 15);
  final Map<String, DateTime> _loadMoreRetryAt = {};

  List<CatalogTrack> get searchResults => List.unmodifiable(_results);
  List<CatalogTrack> searchResultsFor(String sourceId) {
    final paged = _pagedResults[sourceId];
    if (paged != null) return List.unmodifiable(paged);
    return List.unmodifiable(
      _searchBatch?.groupFor(sourceId)?.tracks ??
          _results.where((track) => track.sourceId == sourceId).toList(),
    );
  }

  bool hasMoreResults(String sourceId) =>
      _pagedResults.containsKey(sourceId) &&
      (_pagedResults[sourceId]?.isNotEmpty ?? false) &&
      !_sourceExhausted.contains(sourceId);
  bool isLoadingMore(String sourceId) => _loadingMore.contains(sourceId);
  List<CatalogTrack> categoryTracks(String key) =>
      List.unmodifiable(_categoryTracks[key] ?? const <CatalogTrack>[]);
  bool categoryLoaded(String key) => _categoryTracks.containsKey(key);
  bool isCategoryLoading(String key) => _categoryLoading.contains(key);
  String? categoryError(String key) => _categoryErrors[key];
  CatalogSearchGroup? searchGroupFor(String sourceId) =>
      _searchBatch?.groupFor(sourceId);
  SourceFailure? searchFailureFor(String sourceId) =>
      searchGroupFor(sourceId)?.failure;
  List<CatalogTrack> get favorites => _fromKeys(_favorites);
  List<CatalogTrack> get downloads => _fromKeys(_downloads);
  List<CatalogTrack> get downloadingTracks => _fromKeys(_downloading);
  List<CatalogTrack> get failedDownloads =>
      _fromKeys(_downloadErrors.keys.toSet());
  List<CatalogTrack> get queue => _queue.tracks.map(_trackFor).toList();
  Iterable<SourceDescriptor> get sourceDescriptors => _catalog.sources;
  List<SourceDescriptor> get searchableSources => _catalog.sources
      .where(
        (source) =>
            sourceEnabled(source.id) &&
            source.supports(SourceCapability.search),
      )
      .toList(growable: false);
  CatalogTrack? get currentTrack => _currentTrack;
  PlaybackState get playback => _player.value;
  String get query => _query;
  QualityPreference get quality => _quality;
  SettingsSection get settingsSection => _settingsSection;
  String get language => _language;
  bool get autoPlay => _autoPlay;
  bool get reducedEffects => _reducedEffects;
  bool get releaseAfterPause => _releaseAfterPause;
  bool get diagnosticLogging => _diagnosticLogging;
  double get volume => _volume;
  PlaybackLoop get loop => _loop;

  /// The current keyboard binding for [action] (always set).
  ShortcutBinding shortcutFor(PlayerAction action) => _shortcuts[action]!;
  String? get playbackError => _playbackError;
  String? get searchError => _searchError;
  bool get isSearching => _isSearching;

  /// Whether [sourceId] has yet to report for the search that is running.
  bool isSearchingSource(String sourceId) =>
      _isSearching && searchGroupFor(sourceId) == null;
  bool get isPlaying => _player.value.isPlaying;
  bool get isLoading => _player.value.status == PlaybackStatus.loading;
  Duration get position => _position;

  /// The playback position on its own channel: it changes on every engine
  /// tick, so only the progress bar and time labels listen to it while the
  /// controller itself notifies for real state changes only.
  ValueListenable<Duration> get positionListenable => _positionNotifier;
  Duration get playbackDuration => _playbackDuration;
  String get positionLabel => _formatDuration(_position);
  String get playbackDurationLabel => _formatDuration(
    _playbackDuration > Duration.zero
        ? _playbackDuration
        : (_currentTrack?.duration ?? Duration.zero),
  );

  bool isFavorite(CatalogTrack track) =>
      _favorites.contains(track.ref.toString());
  bool isDownloaded(CatalogTrack track) =>
      _downloads.contains(track.ref.toString()) ||
      _downloadPaths.containsKey(track.ref.toString());
  bool isDownloading(CatalogTrack track) =>
      _downloading.contains(track.ref.toString());
  String? downloadErrorFor(CatalogTrack track) =>
      _downloadErrors[track.ref.toString()];
  bool sourceEnabled(String sourceId) => _enabledSources.contains(sourceId);
  int searchResultCount(String sourceId) =>
      _pagedResults[sourceId]?.length ??
      searchGroupFor(sourceId)?.tracks.length ??
      _results.where((track) => track.sourceId == sourceId).length;
  bool isLoadingTrack(CatalogTrack track) =>
      isLoading && _currentTrack?.ref == track.ref;

  /// Plays [track]. [queueIndex] names the queue entry when the caller already
  /// chose it (next / previous / shuffle / queue rows), so a track that sits
  /// in the queue twice keeps the chosen copy instead of the first one.
  Future<void> play(CatalogTrack track, {int? queueIndex}) async {
    // Consume a pending session-resume position only for its own track.
    final resumeTo = track.ref == _resumeRef ? _resumePosition : null;
    _resumeRef = null;
    _resumePosition = null;
    _knownTracks[track.ref.toString()] = track;
    final tracks = _queue.tracks;
    final chosen =
        queueIndex != null &&
        queueIndex >= 0 &&
        queueIndex < tracks.length &&
        tracks[queueIndex].ref == track.ref;
    final index = chosen
        ? queueIndex
        : tracks.indexWhere((item) => item.ref == track.ref);
    if (index >= 0) {
      _queue.select(index);
    } else {
      _queue.add(track.summary);
      _queue.select(_queue.tracks.length - 1);
    }
    _currentTrack = track;
    _position = Duration.zero;
    _playbackDuration = track.hasKnownDuration ? track.duration : Duration.zero;
    _playbackError = null;
    _syncNowPlaying();
    notifyListeners();
    final path = _downloadPaths[track.ref.toString()];
    final candidate = path == null
        ? track.candidate
        : StreamCandidate(
            ref: track.ref,
            id: Uri.file(path).toString(),
            label: 'offline',
          );
    DiagnosticLog.record('play ${track.sourceName}: ${track.title}');
    final generation = ++_playGeneration;
    final startAt = resumeTo != null && resumeTo > Duration.zero
        ? resumeTo
        : null;
    if (startAt != null) _position = startAt;
    await _player.play(candidate, startAt: startAt);
    // A newer play() took over while this one loaded; its state wins.
    if (generation != _playGeneration) return;
    _playbackError = _player.value.errorMessage;
    final pauseNow = _pauseWhenStarted;
    _pauseWhenStarted = false;
    if (pauseNow && _playbackError == null) {
      await _player.pause();
      _syncPlaybackState();
    }
    if (_playbackError != null) {
      DiagnosticLog.record('play error: $_playbackError');
    } else if (startAt != null && _playerEngine is! StartPositionLoad) {
      await seek(startAt); // Engines without start support resume by seeking.
    }
    _persistSession();
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    // A manual play/pause overrides any pending "resume when the device comes
    // back" intent, so we never auto-resume against the user.
    _pausedByRoute = false;
    final track = _currentTrack;
    if (isLoading) return;
    if (isPlaying) {
      await _player.pause();
      _playbackError = _player.value.errorMessage;
      _persistSession();
    } else if (track != null) {
      await _resumeOrReload(track);
      return;
    }
    notifyListeners();
  }

  /// Resumes the loaded source in place. When it is gone (released after a
  /// long pause, failed, or played to its end) the track is reloaded, at the
  /// paused position unless it had finished.
  Future<void> _resumeOrReload(CatalogTrack track) async {
    if (await _player.resume()) {
      _playbackError = _player.value.errorMessage;
      notifyListeners();
      return;
    }
    final finished =
        _playbackDuration > Duration.zero && _position >= _playbackDuration;
    if (!finished && _position > Duration.zero) {
      _resumeRef = track.ref;
      _resumePosition = _position;
    }
    await play(track, queueIndex: _queue.currentIndex);
  }

  Future<void> next() => _advance(
    wrap: _loop == PlaybackLoop.queue,
    shuffled: _loop == PlaybackLoop.shuffle,
  );

  Future<void> previous() async {
    final previous = _queue.previous(wrap: _loop == PlaybackLoop.queue);
    if (previous != null) {
      await play(_trackFor(previous), queueIndex: _queue.currentIndex);
    }
  }

  Future<void> _advance({required bool wrap, required bool shuffled}) async {
    final next = shuffled ? _randomNext() : _queue.next(wrap: wrap);
    if (next != null) {
      await play(_trackFor(next), queueIndex: _queue.currentIndex);
    }
  }

  TrackSummary? _randomNext() {
    final tracks = _queue.tracks;
    if (tracks.isEmpty) return null;
    if (tracks.length == 1) return _queue.select(0);
    final current = _queue.current;
    final currentIndex = tracks.indexWhere(
      (track) => track.ref == current?.ref,
    );
    if (currentIndex < 0) return _queue.select(_random.nextInt(tracks.length));
    final offset = _random.nextInt(tracks.length - 1);
    final target = offset >= currentIndex ? offset + 1 : offset;
    return _queue.select(target);
  }

  Future<void> _onPlaybackCompleted() async {
    switch (_loop) {
      case PlaybackLoop.track:
        final track = _currentTrack;
        if (track != null) await play(track, queueIndex: _queue.currentIndex);
        return;
      case PlaybackLoop.queue:
      case PlaybackLoop.off:
      case PlaybackLoop.shuffle:
        await _advance(
          wrap: _loop == PlaybackLoop.queue,
          shuffled: _loop == PlaybackLoop.shuffle,
        );
    }
  }

  void addNext(CatalogTrack track) {
    _knownTracks[track.ref.toString()] = track;
    _queue.add(track.summary, playNext: true);
    _persistSession();
    notifyListeners();
  }

  /// Replaces the queue with a whole list (a playlist / category) in its own
  /// order and starts the first track.
  Future<void> playAll(List<CatalogTrack> tracks) async {
    if (tracks.isEmpty) return;
    for (final track in tracks) {
      _knownTracks[track.ref.toString()] = track;
    }
    _queue.replace([for (final track in tracks) track.summary]);
    await play(tracks.first, queueIndex: 0);
  }

  /// Plays [tracks] in a random order.
  Future<void> shufflePlay(List<CatalogTrack> tracks) async {
    if (tracks.isEmpty) return;
    await playAll(List.of(tracks)..shuffle(_random));
  }

  void removeFromQueue(int index) {
    _queue.removeAt(index);
    _persistSession();
    notifyListeners();
  }

  void reorderQueue(int from, int to) {
    _queue.move(from, to);
    _persistSession();
    notifyListeners();
  }

  /// Empties the play queue without touching downloads or favorites.
  void clearQueue() {
    if (_queue.isEmpty) return;
    _queue.clear();
    _persistSession();
    notifyListeners();
  }

  // ---- Appearance: built-in themes + optional custom skin ----

  String get themeId => _themeId;
  String? get skinImagePath => _skinImagePath;
  bool get hasSkin => _skinImagePath != null;

  /// Notifies only when the theme or skin changes, so the app root (which
  /// rebuilds MaterialApp + ThemeData) does not follow every controller change.
  Listenable get appearanceListenable => _appearance;
  final ValueNotifier<(String, String?)> _appearance = ValueNotifier((
    kDefaultThemeId,
    null,
  ));

  void _appearanceChanged() {
    _appearance.value = (_themeId, _skinImagePath);
    notifyListeners();
  }

  Future<void> _restoreAppearance() async {
    final store = _appearanceStore;
    if (store == null) return;
    final themeId = await store.loadThemeId();
    final skin = await store.loadSkin();
    if (themeId != null) _themeId = themeId;
    _skinImagePath = skin?.path;
    _appearanceChanged();
  }

  /// Selects a built-in theme and drops any custom skin image.
  Future<void> selectTheme(String id) async {
    _themeId = id;
    _skinImagePath = null;
    _appearanceChanged();
    await _appearanceStore?.saveThemeId(id);
    await _appearanceStore?.clearSkin();
  }

  /// Copies [sourcePath] into app storage and applies it as a custom skin.
  Future<void> setSkinFromFile(String sourcePath) async {
    final store = _appearanceStore;
    if (store == null) return;
    final file = await store.saveSkin(sourcePath);
    _skinImagePath = file.path;
    _appearanceChanged();
  }

  void toggleFavorite(CatalogTrack track) {
    final key = track.ref.toString();
    if (_favorites.contains(key)) {
      _favorites.remove(key);
    } else {
      _favorites.add(key);
      // Keep the full track so the favorites list still renders after a restart.
      _knownTracks[key] = track;
    }
    unawaited(_persistFavorites());
    notifyListeners();
  }

  Future<void> _restoreFavorites() async {
    final store = _favoritesStore;
    if (store == null) return;
    final tracks = await store.load();
    for (final track in tracks) {
      final key = track.ref.toString();
      _knownTracks[key] = track;
      _favorites.add(key);
    }
    if (tracks.isNotEmpty) notifyListeners();
  }

  Future<void> _persistFavorites() async =>
      _favoritesStore?.save(favorites);

  Future<void> seek(Duration position) async {
    if (_playerEngine is! PlaybackProgressEvents) return;
    await (_playerEngine as PlaybackProgressEvents).seek(position);
    _position = position;
    _syncPlaybackState();
    _persistSession();
  }

  // ---- System media session (media keys / Bluetooth headset buttons) ----

  Future<void> _initMediaControls() async {
    try {
      await _mediaControls.init();
    } catch (_) {
      return; // Session integration is best-effort; playback works without it.
    }
    _mediaCommandSubscription = _mediaControls.commands.listen(_onMediaCommand);
    _mediaSeekSubscription = _mediaControls.seeks.listen(
      (position) => unawaited(seek(position)),
    );
  }

  // ---- Audio output route (Bluetooth / headphones connect + disconnect) ----

  Future<void> _initRouteMonitor() async {
    try {
      await _routeMonitor.start();
    } catch (_) {
      return; // Best-effort; playback works without route awareness.
    }
    _routeSubscription = _routeMonitor.events.listen(_onRouteEvent);
  }

  Future<void> _onRouteEvent(AudioRouteEvent event) async {
    switch (event) {
      case AudioRouteEvent.outputDisconnected:
        // Bluetooth / headphones went away: pause and remember, so audio does
        // not suddenly blast out of the built-in speakers.
        if (isPlaying) {
          _pausedByRoute = true;
          await _player.pause();
          _syncPlaybackState();
          notifyListeners();
        }
      case AudioRouteEvent.outputConnected:
        // The device came back: resume only what we auto-paused (a manual
        // pause/play in between clears the flag, so we never fight the user).
        final track = _currentTrack;
        if (_pausedByRoute && !isPlaying && track != null) {
          _pausedByRoute = false;
          await _resumeOrReload(track);
          _syncPlaybackState();
          notifyListeners();
        }
    }
  }

  void _onMediaCommand(MediaCommand command) {
    switch (command) {
      case MediaCommand.play:
        if (!isPlaying) unawaited(togglePlayback());
      case MediaCommand.pause:
        if (isPlaying) unawaited(togglePlayback());
      case MediaCommand.stop:
        unawaited(stopPlayback());
      case MediaCommand.next:
        unawaited(next());
      case MediaCommand.previous:
        unawaited(previous());
    }
  }

  // ---- Sleep timer ----

  bool get hasSleepTimer => _sleepTimer != null;
  Duration? get sleepTimerRemaining => _sleepRemaining;
  Duration? get sleepTimerTotal => _sleepTimer == null ? null : _sleepTotal;

  /// The sleep countdown on its own channel (it ticks every second).
  ValueListenable<Duration?> get sleepRemainingListenable =>
      _sleepRemainingNotifier;
  String? get sleepTimerLabel =>
      _sleepRemaining == null ? null : _formatDuration(_sleepRemaining!);

  /// Pauses playback after [total]. Pass null (or non-positive) to cancel.
  void setSleepTimer(Duration? total) {
    _pauseWhenStarted = false;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = null;
    _sleepTotal = null;
    if (total == null || total <= Duration.zero) {
      notifyListeners();
      return;
    }
    _sleepRemaining = total;
    _sleepTotal = total;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next =
          (_sleepRemaining ?? Duration.zero) - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _sleepTimer?.cancel();
        _sleepTimer = null;
        _sleepRemaining = null;
        if (isPlaying) {
          unawaited(_player.pause().then((_) => _persistSession()));
        } else if (isLoading) {
          _pauseWhenStarted = true; // play() pauses once the track starts
        }
        _syncPlaybackState();
        notifyListeners();
      } else {
        _sleepRemaining = next; // Only the countdown label listens to this.
      }
    });
    notifyListeners();
  }

  /// Stops playback and clears the OS media session (headset/OS "stop").
  Future<void> stopPlayback() async {
    await _player.stop();
    _persistSession();
    _syncPlaybackState();
    notifyListeners();
  }

  void _syncNowPlaying() {
    final track = _currentTrack;
    if (track == null) return;
    _mediaControls.setNowPlaying(
      NowPlayingInfo(
        id: track.ref.toString(),
        title: track.title,
        artist: track.artist,
        album: track.sourceName,
        artUri: track.artworkUrl == null
            ? null
            : Uri.tryParse(track.artworkUrl!),
        duration: _playbackDuration > Duration.zero
            ? _playbackDuration
            : (track.hasKnownDuration ? track.duration : null),
      ),
    );
  }

  void _syncPlaybackState() {
    _mediaControls.setPlaybackState(
      playing: isPlaying,
      position: _position,
      duration: _playbackDuration == Duration.zero ? null : _playbackDuration,
    );
  }

  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  Future<void> _restoreSearchHistory() async {
    final store = _searchHistoryStore;
    if (store == null) return;
    final saved = await store.load();
    if (saved.isEmpty) return;
    _searchHistory
      ..clear()
      ..addAll(saved.take(_maxSearchHistory));
    notifyListeners();
  }

  void _recordSearch(String query) {
    _searchHistory
      ..removeWhere((item) => item.toLowerCase() == query.toLowerCase())
      ..insert(0, query);
    if (_searchHistory.length > _maxSearchHistory) {
      _searchHistory.removeRange(_maxSearchHistory, _searchHistory.length);
    }
    unawaited(_searchHistoryStore?.save(_searchHistory));
  }

  void clearSearchHistory() {
    if (_searchHistory.isEmpty) return;
    _searchHistory.clear();
    unawaited(_searchHistoryStore?.save(_searchHistory));
    notifyListeners();
  }

  void setSourceEnabled(String sourceId, bool enabled) {
    if (!_catalog.sources.any((source) => source.id == sourceId)) return;
    _catalog.setEnabled(sourceId, enabled);
    enabled ? _enabledSources.add(sourceId) : _enabledSources.remove(sourceId);
    final index = _plugins.indexWhere((manifest) => manifest.id == sourceId);
    if (index >= 0) {
      _plugins[index] = _plugins[index].copyWith(enabled: enabled);
      unawaited(_pluginRepository?.setEnabled(sourceId, enabled));
      _pluginsChanged();
    }
    unawaited(search(_query));
  }

  void setQuality(QualityPreference value) {
    _quality = value;
    _persistSettings();
    notifyListeners();
  }

  // ---- Settings persistence + session restore ----

  Future<void> _restoreSettings() async {
    final store = _settingsStore;
    if (store == null) return;
    final data = await store.load();
    _volume = ((data['volume'] as num?)?.toDouble() ?? _volume).clamp(0, 1);
    _rate = ((data['rate'] as num?)?.toDouble() ?? _rate).clamp(0.25, 3.0);
    _loop = PlaybackLoop.values.firstWhere(
      (loop) => loop.name == data['loop'],
      orElse: () => _loop,
    );
    _quality = QualityPreference.values.firstWhere(
      (quality) => quality.name == data['quality'],
      orElse: () => _quality,
    );
    _language = data['language'] as String? ?? _language;
    AppStrings.lang = AppStrings.fromName(_language);
    _autoPlay = data['autoPlay'] as bool? ?? _autoPlay;
    _reducedEffects = data['reducedEffects'] as bool? ?? _reducedEffects;
    _releaseAfterPause = data['releaseAfterPause'] as bool? ?? _releaseAfterPause;
    _diagnosticLogging = data['diagnosticLogging'] as bool? ?? _diagnosticLogging;
    _agentControl = data['agentControl'] as bool? ?? _agentControl;
    _shortcuts
      ..clear()
      ..addAll(shortcutsFromJson(data['shortcuts']));
    AppEffects.reduced = _reducedEffects;
    DiagnosticLog.enabled = _diagnosticLogging;
    if (_agentControl) unawaited(_controlServer.start());
    await _player.setVolume(_volume);
    await _player.setRate(_rate);
    await _player.setReleaseAfterPause(_releaseAfterPause);
    notifyListeners();
  }

  void _persistSettings() {
    unawaited(
      _settingsStore?.save({
        'volume': _volume,
        'rate': _rate,
        'loop': _loop.name,
        'quality': _quality.name,
        'language': _language,
        'autoPlay': _autoPlay,
        'reducedEffects': _reducedEffects,
        'releaseAfterPause': _releaseAfterPause,
        'diagnosticLogging': _diagnosticLogging,
        'agentControl': _agentControl,
        'shortcuts': shortcutsToJson(_shortcuts),
      }),
    );
  }

  Future<void> _restoreSession() async {
    // "Restore last session" is gated by the autoPlay preference.
    if (!_autoPlay) return;
    final store = _sessionStore;
    if (store == null) return;
    final session = await store.load();
    if (session == null || session.queue.isEmpty) return;
    for (final track in session.queue) {
      _knownTracks[track.ref.toString()] = track;
    }
    _queue.replace(
      [for (final track in session.queue) track.summary],
      initialIndex: session.currentIndex,
    );
    final current = _queue.current;
    if (current != null) {
      _currentTrack = _trackFor(current);
      // Show the saved position and resume there on the next play of this track.
      if (session.positionMs > 0) {
        _position = Duration(milliseconds: session.positionMs);
        _resumePosition = _position;
        _resumeRef = current.ref;
      }
      _syncNowPlaying();
    }
    notifyListeners();
  }

  static const _sessionSaveInterval = Duration(seconds: 10);
  var _savedPosition = Duration.zero;

  void _persistSession() {
    final store = _sessionStore;
    if (store == null) return;
    _savedPosition = _position;
    final tracks = queue;
    final currentRef = _currentTrack?.ref;
    final index = currentRef == null
        ? 0
        : tracks.indexWhere((track) => track.ref == currentRef);
    unawaited(store.save(
      tracks,
      index < 0 ? 0 : index,
      positionMs: _position.inMilliseconds,
    ));
  }

  // ---- Agent control (local HTTP API to drive the player) ----

  bool get agentControlEnabled => _agentControl;
  String? get agentControlAddress => _controlServer.address;

  Future<void> setAgentControlEnabled(bool value) async {
    _agentControl = value;
    if (value) {
      await _controlServer.start();
    } else {
      await _controlServer.stop();
    }
    _persistSettings();
    notifyListeners();
  }

  /// Plays a track already seen this session, identified by source + item id.
  /// Used by the control API so an agent can play a prior search result.
  Future<bool> playByRef(String sourceId, String itemId) async {
    final key = MediaRef(sourceId: sourceId, itemId: itemId).toString();
    final track = _knownTracks[key];
    if (track == null) return false;
    await play(track);
    return true;
  }

  /// Plays the queue entry at [index] (for the control API).
  Future<bool> playQueueIndex(int index) async {
    final tracks = queue;
    if (index < 0 || index >= tracks.length) return false;
    await play(tracks[index], queueIndex: index);
    return true;
  }

  void setSettingsSection(SettingsSection value) {
    _settingsSection = value;
    notifyListeners();
  }

  void setLanguage(String value) {
    _language = value;
    AppStrings.lang = AppStrings.fromName(value);
    _persistSettings();
    notifyListeners();
  }

  void setAutoPlay(bool value) {
    _autoPlay = value;
    _persistSettings();
    if (!value) unawaited(_sessionStore?.clear());
    notifyListeners();
  }

  void setReducedEffects(bool value) {
    _reducedEffects = value;
    AppEffects.reduced = value;
    _persistSettings();
    notifyListeners();
  }

  void setReleaseAfterPause(bool value) {
    _releaseAfterPause = value;
    unawaited(_player.setReleaseAfterPause(value));
    _persistSettings();
    notifyListeners();
  }

  void setDiagnosticLogging(bool value) {
    _diagnosticLogging = value;
    DiagnosticLog.enabled = value;
    _persistSettings();
    notifyListeners();
  }

  void setVolume(double value) {
    _volume = value.clamp(0, 1);
    unawaited(_player.setVolume(_volume));
    _persistSettings();
    notifyListeners();
  }

  double get playbackRate => _rate;

  void setPlaybackRate(double value) {
    _rate = value.clamp(0.25, 3.0);
    unawaited(_player.setRate(_rate));
    _persistSettings();
    notifyListeners();
  }

  void setLoop(PlaybackLoop value) {
    _loop = value;
    _persistSettings();
    notifyListeners();
  }

  /// Rebinds [action] to [binding]. If another action already holds that key
  /// combo, the two swap so every action stays bound and bindings stay unique.
  void setShortcut(PlayerAction action, ShortcutBinding binding) {
    final previous = _shortcuts[action];
    PlayerAction? conflict;
    _shortcuts.forEach((other, existing) {
      if (other != action && existing == binding) conflict = other;
    });
    if (conflict != null && previous != null) _shortcuts[conflict!] = previous;
    _shortcuts[action] = binding;
    _persistSettings();
    notifyListeners();
  }

  /// Restores every shortcut to its factory default.
  void resetShortcuts() {
    _shortcuts
      ..clear()
      ..addAll(defaultShortcuts());
    _persistSettings();
    notifyListeners();
  }

  /// [notifyListeners] for the extensions in this library's part files,
  /// which may not call the protected member themselves.
  void _notify() => notifyListeners();

  @override
  void dispose() {
    _persistSession(); // Keep the position when the app closes.
    _searchCancellation?.cancel();
    _loadMoreCancellation?.cancel();
    unawaited(_completionSubscription?.cancel() ?? Future<void>.value());
    unawaited(_playbackSubscription?.cancel() ?? Future<void>.value());
    unawaited(_positionSubscription?.cancel() ?? Future<void>.value());
    unawaited(_durationSubscription?.cancel() ?? Future<void>.value());
    unawaited(_mediaCommandSubscription?.cancel() ?? Future<void>.value());
    unawaited(_mediaSeekSubscription?.cancel() ?? Future<void>.value());
    unawaited(_routeSubscription?.cancel() ?? Future<void>.value());
    unawaited(_routeMonitor.dispose());
    _sleepTimer?.cancel();
    for (final source in _pluginSources.values) {
      source.dispose();
    }
    _pluginSources.clear();
    unawaited(_pluginRepository?.dispose());
    unawaited(_controlServer.stop());
    unawaited(_mediaControls.dispose());
    unawaited(_player.dispose());
    _positionNotifier.dispose();
    _sleepRemainingNotifier.dispose();
    _appearance.dispose();
    super.dispose();
  }

  String _friendlyDownloadError(Object error) {
    final text = error.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }

  String _formatDuration(Duration value) {
    if (value <= Duration.zero) return '--:--';
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  List<CatalogTrack> _fromKeys(Set<String> keys) => keys
      .map((key) => _knownTracks[key])
      .whereType<CatalogTrack>()
      .toList(growable: false);

  String? _globalSearchError(CatalogSearchBatch batch) {
    if (batch.hasResults) return null;
    for (final group in batch.groups) {
      if (group.failure case final failure?) return failure.message;
    }
    return null;
  }

  CatalogTrack _trackFor(TrackSummary summary) {
    final track = _knownTracks[summary.ref.toString()];
    if (track == null) throw StateError('队列项目已不可用。');
    return track;
  }
}
