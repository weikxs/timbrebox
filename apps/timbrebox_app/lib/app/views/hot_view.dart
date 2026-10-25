import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';
import '../plugins/plugin_catalog_source.dart';
import '../state/app_controller.dart';
import '../widgets/glass_panel.dart';
import '../widgets/track_artwork.dart';

// Aurora accent palette, local to this page (used for saturated accents that
// read on both light and dark; page text uses the theme palette).
const _indigo = Color(0xff8b7bff);
const _magenta = Color(0xffc06bff);
const _cyan = Color(0xff5cd0ff);

/// A hot-library category = a playlist. It resolves either to an Audius genre
/// (real genre trending) or a Bilibili keyword (real 华语 category via search).
class _Category {
  const _Category(
    this.key,
    this.label, {
    this.localized = false,
    this.audiusGenre,
    this.bilibiliQuery,
    this.pluginRef,
    this.pluginSourceName,
    required this.gradient,
  });

  final String key;

  /// Either a translation key (when [localized]) or a literal (plugin title).
  final String label;
  final bool localized;
  final String? audiusGenre;
  final String? bilibiliQuery;
  final PluginTopListItem? pluginRef;
  final String? pluginSourceName;
  final List<Color> gradient;

  String get displayLabel => localized ? AppStrings.t(label) : label;

  String get source => pluginRef != null
      ? (pluginSourceName ?? AppStrings.t('hot.plugin'))
      : (audiusGenre != null ? 'Audius' : AppStrings.t('hot.bilibili'));
}

const _pluginGradients = <List<Color>>[
  [Color(0xff654ea3), Color(0xffeaafc8)],
  [Color(0xff36d1dc), Color(0xff5b86e5)],
  [Color(0xfff7971e), Color(0xffffd200)],
  [Color(0xff11998e), Color(0xff38ef7d)],
  [Color(0xffee0979), Color(0xffff6a00)],
  [Color(0xff396afc), Color(0xff2948ff)],
];

List<_Category> _pluginCategories(List<PluginTopListItem> lists) => [
  for (var i = 0; i < lists.length; i++)
    _Category(
      'plugintop_${lists[i].sourceId}_${lists[i].id}',
      lists[i].title,
      pluginRef: lists[i],
      pluginSourceName: lists[i].sourceName,
      gradient: _pluginGradients[i % _pluginGradients.length],
    ),
];

const _audiusCategories = <_Category>[
  _Category('jazz', 'hot.cat.jazz', localized: true, audiusGenre: 'Jazz', gradient: [Color(0xff8e2de2), Color(0xff4a00e0)]),
  _Category('electronic', 'hot.cat.electronic', localized: true, audiusGenre: 'Electronic', gradient: [Color(0xff00c6ff), Color(0xff0072ff)]),
  _Category('hiphop', 'hot.cat.hiphop', localized: true, audiusGenre: 'Hip-Hop/Rap', gradient: [Color(0xfff7971e), Color(0xffffd200)]),
  _Category('pop', 'hot.cat.pop', localized: true, audiusGenre: 'Pop', gradient: [Color(0xffff5f6d), Color(0xffffc371)]),
  _Category('rock', 'hot.cat.rock', localized: true, audiusGenre: 'Rock', gradient: [Color(0xffcb2d3e), Color(0xffef473a)]),
  _Category('classical', 'hot.cat.classical', localized: true, audiusGenre: 'Classical', gradient: [Color(0xff2c3e50), Color(0xff4ca1af)]),
  _Category('ambient', 'hot.cat.ambient', localized: true, audiusGenre: 'Ambient', gradient: [Color(0xff30cfd0), Color(0xff330867)]),
  _Category('soul', 'hot.cat.soul', localized: true, audiusGenre: 'R&B/Soul', gradient: [Color(0xffee0979), Color(0xffff6a00)]),
];

const _bilibiliCategories = <_Category>[
  _Category('guofeng', 'hot.cat.guofeng', localized: true, bilibiliQuery: '古风音乐', gradient: [Color(0xff642b73), Color(0xffc6426e)]),
  _Category('cpop', 'hot.cat.cpop', localized: true, bilibiliQuery: '华语流行', gradient: [Color(0xffff512f), Color(0xffdd2476)]),
  _Category('cover', 'hot.cat.cover', localized: true, bilibiliQuery: '翻唱', gradient: [Color(0xff11998e), Color(0xff38ef7d)]),
  _Category('acg', 'hot.cat.acg', localized: true, bilibiliQuery: 'ACG 音乐', gradient: [Color(0xff2193b0), Color(0xff6dd5ed)]),
  _Category('folk', 'hot.cat.folk', localized: true, bilibiliQuery: '民谣', gradient: [Color(0xfff12711), Color(0xfff5af19)]),
  _Category('guochao', 'hot.cat.guochao', localized: true, bilibiliQuery: '国风电音', gradient: [Color(0xff3a1c71), Color(0xffd76d77)]),
];

Color _sourceColor(String sourceId) => switch (sourceId) {
  'youtube' => const Color(0xffff5470),
  'bilibili' => const Color(0xff3fb6ff),
  'audius' => _magenta,
  'internet_archive' => const Color(0xfff5b041),
  'radio_browser' => const Color(0xff5ad07a),
  _ => _indigo,
};

class HotView extends StatefulWidget {
  const HotView({required this.controller, super.key});

  final AppController controller;

  @override
  State<HotView> createState() => _HotViewState();
}

class _HotViewState extends State<HotView> {
  _Category? _open;

  @override
  void initState() {
    super.initState();
    // Without plugins the load finishes synchronously and notifies listeners,
    // which must not happen while this page is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadPluginTopLists();
    });
  }

  void _openCategory(_Category category) {
    setState(() => _open = category);
    widget.controller.loadCategory(
      category.key,
      audiusGenre: category.audiusGenre,
      bilibiliQuery: category.bilibiliQuery,
      pluginTopList: category.pluginRef,
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return Stack(
      children: [
        const _Ambient(),
        if (open == null)
          _CategoryGrid(controller: widget.controller, onOpen: _openCategory)
        else
          _Playlist(
            category: open,
            controller: widget.controller,
            onBack: () => setState(() => _open = null),
          ),
      ],
    );
  }
}

class _Ambient extends StatelessWidget {
  const _Ambient();

  @override
  Widget build(BuildContext context) => Positioned(
    top: -80,
    left: -40,
    right: -40,
    height: 320,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-.4, -.6),
            radius: 1.1,
            colors: [_indigo.withValues(alpha: .22), Colors.transparent],
          ),
        ),
      ),
    ),
  );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.controller, required this.onOpen});

  final AppController controller;
  final ValueChanged<_Category> onOpen;

  @override
  Widget build(BuildContext context) {
    final pluginCats = _pluginCategories(controller.pluginTopLists);
    return ListView(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 16),
      children: [
        _Kicker(AppStrings.t('kicker.trending')),
        const SizedBox(height: 8),
        Text(
          AppStrings.t('nav.hot'),
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            color: TimbreColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.t('hot.subtitle'),
          style: TextStyle(color: TimbreColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 24),
        _GroupLabel(AppStrings.t('hot.genresGroup'), color: _magenta),
        const SizedBox(height: 12),
        _Tiles(categories: _audiusCategories, onOpen: onOpen),
        const SizedBox(height: 26),
        _GroupLabel(AppStrings.t('hot.chineseGroup'), color: _cyan),
        const SizedBox(height: 12),
        _Tiles(categories: _bilibiliCategories, onOpen: onOpen),
        if (pluginCats.isNotEmpty) ...[
          const SizedBox(height: 26),
          _GroupLabel(AppStrings.t('hot.pluginCharts'), color: _indigo),
          const SizedBox(height: 12),
          _Tiles(categories: pluginCats, onOpen: onOpen),
        ],
      ],
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.categories, required this.onOpen});

  final List<_Category> categories;
  final ValueChanged<_Category> onOpen;

  static const _gap = 14.0;
  static const _minCard = 200.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / _minCard).floor().clamp(2, 5);
      final cardWidth =
          (constraints.maxWidth - _gap * (columns - 1)) / columns;
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final category in categories)
            SizedBox(
              width: cardWidth,
              child: _CategoryCard(
                category: category,
                onTap: () => onOpen(category),
              ),
            ),
        ],
      );
    },
  );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final _Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: category.gradient.first.withValues(alpha: .42),
            blurRadius: 22,
            offset: const Offset(0, 11),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 96,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: category.gradient,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .18)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // glass sheen, top-left
              Positioned(
                left: -30,
                top: -40,
                child: Container(
                  width: 120,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(60),
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: .22),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              // tilted disc accent, bottom-right
              Positioned(
                right: -18,
                bottom: -22,
                child: Transform.rotate(
                  angle: .4,
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.displayLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                  ),
                ),
                const Spacer(),
                Text(
                  category.source,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .82),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
  );
}

class _Playlist extends StatelessWidget {
  const _Playlist({
    required this.category,
    required this.controller,
    required this.onBack,
  });

  final _Category category;
  final AppController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.categoryTracks(category.key);
    final loading = controller.isCategoryLoading(category.key);
    final error = controller.categoryError(category.key);
    return ListView(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 16),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: AppStrings.t('common.back'),
              color: TimbreColors.ink,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.displayLabel,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.6,
                      color: TimbreColors.ink,
                    ),
                  ),
                  Text(
                    '${category.source} · ${AppStrings.t('hot.publicTrending')}',
                    style: TextStyle(color: TimbreColors.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (tracks.isNotEmpty)
              _PlayAllButton(onPressed: () => controller.playAll(tracks)),
          ],
        ),
        const SizedBox(height: 16),
        if (tracks.isEmpty)
          _Notice(
            loading: loading,
            error: error,
            onRetry: () => controller.loadCategory(
              category.key,
              audiusGenre: category.audiusGenre,
              bilibiliQuery: category.bilibiliQuery,
              pluginTopList: category.pluginRef,
              force: true,
            ),
          )
        else
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < tracks.length; i++) ...[
                  _TrackRow(
                    index: i + 1,
                    track: tracks[i],
                    controller: controller,
                  ),
                  if (i != tracks.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 78),
                      child: Divider(height: 1, color: TimbreColors.line),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  const _PlayAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const LinearGradient(colors: [_indigo, _magenta]),
      boxShadow: [
        BoxShadow(
          color: _indigo.withValues(alpha: .45),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 19),
              const SizedBox(width: 7),
              Text(
                AppStrings.t('player.playAll'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.index,
    required this.track,
    required this.controller,
  });

  final int index;
  final CatalogTrack track;
  final AppController controller;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final controller = widget.controller;
    final current = controller.currentTrack?.ref == track.ref;
    final playing = current && controller.isPlaying;
    final favorite = controller.isFavorite(track);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: current
              ? TimbreColors.gold.withValues(alpha: .12)
              : _hover
              ? TimbreColors.ink.withValues(alpha: .05)
              : Colors.transparent,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => controller.play(track),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${widget.index}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: TimbreColors.muted,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Stack(
                  children: [
                    TrackArtwork(track: track, size: 46, radius: 9),
                    if (playing)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            color: const Color(0x66000000),
                          ),
                          child: const Icon(
                            Icons.graphic_eq_rounded,
                            size: 20,
                            color: _cyan,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: current ? TimbreColors.gold : TimbreColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${track.artist} · ${track.sourceName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: TimbreColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: _sourceColor(track.sourceId),
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  track.durationLabel,
                  style: TextStyle(
                    color: TimbreColors.muted,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  onPressed: () => controller.toggleFavorite(track),
                  tooltip: AppStrings.t(favorite ? 'common.unfavorite' : 'common.favorite'),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  color: favorite ? _magenta : TimbreColors.muted,
                  icon: Icon(
                    favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: TimbreColors.gold,
      fontSize: 11,
      letterSpacing: 2.4,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 5,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -.2,
          color: TimbreColors.ink,
        ),
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(22),
    child: Row(
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: loading
              ? CircularProgressIndicator(strokeWidth: 2, color: TimbreColors.gold)
              : Icon(
                  error != null
                      ? Icons.wifi_off_rounded
                      : Icons.library_music_outlined,
                  color: TimbreColors.gold,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            loading
                ? AppStrings.t('hot.loadingPlaylist')
                : error ?? AppStrings.t('hot.emptyCategory'),
            style: TextStyle(color: TimbreColors.ink, fontSize: 14),
          ),
        ),
        if (!loading)
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: TimbreColors.gold),
            child: Text(AppStrings.t('common.retry')),
          ),
      ],
    ),
  );
}
