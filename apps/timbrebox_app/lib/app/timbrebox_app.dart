import 'dart:io';

import 'package:flutter/material.dart';

import 'data/music_catalog.dart';
import 'design/app_themes.dart';
import 'design/timbre_colors.dart';
import 'plugins/plugin_platform.dart';
import 'plugins/plugin_repository.dart';
import 'shell_page.dart';
import 'widgets/player_hotkeys.dart';
import 'state/app_controller.dart';
import 'state/audio_route_monitor.dart';
import 'state/catalog_download_service.dart';
import 'state/media_kit_audio_route_monitor.dart';
import 'state/catalog_player_source_resolver.dart';
import 'state/download_index_store.dart';
import 'state/favorites_store.dart';
import 'state/playlist_store.dart';
import 'state/search_history_store.dart';
import 'state/appearance_store.dart';
import 'state/media_kit_backend.dart';
import 'state/network_player_engine.dart';
import 'state/session_store.dart';
import 'state/settings_store.dart';
import 'state/system_media_controls.dart';

class TimbreBoxApp extends StatefulWidget {
  const TimbreBoxApp({
    this.controller,
    this.softwareRendering = false,
    super.key,
  });

  /// Tests can inject a deterministic controller. The shipped app owns a
  /// single native stream player for the whole listening session.
  final AppController? controller;

  /// No GPU: visual effects default to off (see `isSoftwareRendering`).
  final bool softwareRendering;

  @override
  State<TimbreBoxApp> createState() => _TimbreBoxAppState();
}

class _TimbreBoxAppState extends State<TimbreBoxApp>
    with WidgetsBindingObserver {
  late final BuiltInMusicCatalog _catalog = BuiltInMusicCatalog.standard();
  late final MediaKitBackend _backend = MediaKitBackend();
  late final AppController _controller =
      widget.controller ??
      AppController(
        catalog: _catalog,
        downloadService: CatalogDownloadService(
          resolver: _catalog.streamResolver,
        ),
        downloadStore: FileDownloadIndexStore(),
        appearanceStore: AppearanceStore(),
        mediaControls: createSystemMediaControls(),
        routeMonitor: _createRouteMonitor(),
        // No repository on mobile: plugin code is never fetched or run there.
        pluginRepository: pluginsAllowedHere ? PluginRepository() : null,
        settingsStore: SettingsStore(),
        sessionStore: FileSessionStore(),
        favoritesStore: FileFavoritesStore(),
        searchHistoryStore: FileSearchHistoryStore(),
        playlistStore: FilePlaylistStore(),
        engine: NetworkPlayerEngine(
          backend: _backend,
          resolver: CatalogPlayerSourceResolver(_catalog.streamResolver),
        ),
        softwareRendering: widget.softwareRendering,
      );

  /// Windows/Linux watch media_kit's live device list; macOS/mobile use the
  /// platform monitor picked by [createAudioRouteMonitor].
  AudioRouteMonitor _createRouteMonitor() {
    if (Platform.isWindows || Platform.isLinux) {
      return MediaKitAudioRouteMonitor(_backend.audioDeviceList);
    }
    return createAudioRouteMonitor();
  }

  late final bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() {
    // Re-resolve the "follow system" theme when the OS light/dark mode flips.
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  ThemeData? _theme;
  TimbrePalette? _themePalette;

  /// Palettes are constants, so the ThemeData (and its seeded ColorScheme) is
  /// built once per palette instead of on every root rebuild.
  ThemeData _themeFor(TimbrePalette palette) {
    final cached = _theme;
    if (cached != null && identical(palette, _themePalette)) return cached;
    _themePalette = palette;
    return _theme = ThemeData(
      brightness: palette.brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: palette.brightness,
      ),
      scaffoldBackgroundColor: palette.canvas,
      dividerColor: palette.line,
      useMaterial3: true,
    );
  }

  static const _seed = Color(0xffd6a96d);

  @override
  Widget build(BuildContext context) {
    // Only theme/skin changes rebuild the root; the shell listens to the rest.
    return ListenableBuilder(
      listenable: _controller.appearanceListenable,
      builder: (context, _) {
        // A custom background image keeps the dark palette so text stays legible
        // over the scrim; otherwise resolve the selected theme (system → OS).
        final palette = _controller.hasSkin
            ? kDarkPalette
            : resolvePalette(
                _controller.themeId,
                WidgetsBinding.instance.platformDispatcher.platformBrightness,
              );
        TimbreColors.active = palette;
        return MaterialApp(
          title: 'TimbreBox',
          debugShowCheckedModeBanner: false,
          theme: _themeFor(palette),
          home: PlayerHotkeys(
            controller: _controller,
            child: ShellPage(controller: _controller),
          ),
        );
      },
    );
  }
}
