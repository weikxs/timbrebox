import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';
import '../state/app_controller.dart';
import 'playlists_panel.dart';
import 'glass_panel.dart';

class TrackList extends StatelessWidget {
  const TrackList({
    required this.tracks,
    required this.controller,
    this.emptyTitle,
    this.emptyDetail,
    this.showQueueAction = true,
    super.key,
  });

  final List<CatalogTrack> tracks;
  final AppController controller;
  final String? emptyTitle;
  final String? emptyDetail;
  final bool showQueueAction;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return _EmptyState(
        title: emptyTitle ?? AppStrings.t('track.emptyTitle'),
        detail: emptyDetail ?? AppStrings.t('track.emptyDetail'),
      );
    }
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          for (final track in tracks)
            _TrackRow(
              track: track,
              controller: controller,
              showQueueAction: showQueueAction,
            ),
        ],
      ),
    );
  }
}

/// [TrackList] as a lazily built sliver, for long result lists inside a
/// [CustomScrollView]: only the rows on screen are built. Every row has the
/// same height, so the first one doubles as the extent prototype. The glass
/// fill, edge and shadow match [GlassPanel]; a backdrop blur cannot wrap a
/// sliver, so the frosting is left out here.
class SliverTrackList extends StatelessWidget {
  const SliverTrackList({
    required this.tracks,
    required this.controller,
    this.emptyTitle,
    this.emptyDetail,
    super.key,
  });

  final List<CatalogTrack> tracks;
  final AppController controller;
  final String? emptyTitle;
  final String? emptyDetail;

  static const _radius = BorderRadius.all(Radius.circular(22));

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return SliverToBoxAdapter(
        child: _EmptyState(
          title: emptyTitle ?? AppStrings.t('track.emptyTitle'),
          detail: emptyDetail ?? AppStrings.t('track.emptyDetail'),
        ),
      );
    }
    Widget row(CatalogTrack track) =>
        _TrackRow(track: track, controller: controller, showQueueAction: true);
    return DecoratedSliver(
      decoration: glassShadowDecoration(_radius),
      sliver: DecoratedSliver(
        decoration: glassSurfaceDecoration(_radius),
        sliver: SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          sliver: SliverPrototypeExtentList.builder(
            prototypeItem: row(tracks.first),
            itemCount: tracks.length,
            itemBuilder: (context, index) => row(tracks[index]),
          ),
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.controller,
    required this.showQueueAction,
  });

  final CatalogTrack track;
  final AppController controller;
  final bool showQueueAction;

  @override
  Widget build(BuildContext context) {
    final current = controller.currentTrack?.ref == track.ref;
    final loading = controller.isLoadingTrack(track);
    return Semantics(
      button: true,
      label: AppStrings.t(loading ? 'track.resolvingFmt' : 'track.playFmt')
          .replaceFirst('{name}', track.title),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: loading ? null : () => controller.play(track),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: current
                      ? TimbreColors.gold.withValues(alpha: .16)
                      : TimbreColors.panel,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TimbreColors.gold,
                        ),
                      )
                    : Icon(
                        current && controller.isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                        color: current ? TimbreColors.gold : TimbreColors.muted,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, overflow: TextOverflow.ellipsis),
                    Text(
                      '${track.artist} · ${track.sourceName}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: TimbreColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                loading ? AppStrings.t('track.resolving') : track.quality,
                style: TextStyle(color: TimbreColors.gold, fontSize: 10),
              ),
              const SizedBox(width: 8),
              Text(
                track.durationLabel,
                style: TextStyle(color: TimbreColors.muted, fontSize: 11),
              ),
              IconButton(
                onPressed: () => controller.toggleFavorite(track),
                tooltip: AppStrings.t(controller.isFavorite(track) ? 'common.unfavorite' : 'common.favorite'),
                iconSize: 18,
                icon: Icon(
                  controller.isFavorite(track)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: controller.isFavorite(track)
                      ? TimbreColors.gold
                      : TimbreColors.muted,
                ),
              ),
              AddToPlaylistButton(controller: controller, track: track),
              if (showQueueAction)
                IconButton(
                  onPressed: () => controller.addNext(track),
                  tooltip: AppStrings.t('track.playNext'),
                  iconSize: 18,
                  icon: const Icon(Icons.queue_music_rounded),
                ),
              IconButton(
                onPressed: controller.isDownloading(track)
                    ? null
                    : () => controller.toggleDownload(track),
                tooltip: AppStrings.t(controller.isDownloading(track)
                    ? 'download.downloading'
                    : controller.isDownloaded(track)
                    ? 'download.remove'
                    : 'download.toLocal'),
                iconSize: 18,
                icon: controller.isDownloading(track)
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        controller.isDownloaded(track)
                            ? Icons.download_done_rounded
                            : Icons.download_outlined,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.queue_music_outlined, color: TimbreColors.gold),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        Text(detail, style: TextStyle(color: TimbreColors.muted)),
      ],
    ),
  );
}
