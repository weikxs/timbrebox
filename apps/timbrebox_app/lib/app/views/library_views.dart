import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';
import '../state/app_controller.dart';
import '../widgets/glass_panel.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/playlists_panel.dart';
import '../widgets/track_artwork.dart';
import '../widgets/track_list.dart';

class LibraryView extends StatelessWidget {
  const LibraryView({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => PageScaffold(
    kicker: AppStrings.t('kicker.library'),
    title: AppStrings.t('nav.myMusic'),
    detail: AppStrings.t('library.favoritesDetail'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlaylistsPanel(controller: controller),
        const SizedBox(height: 14),
        if (controller.favorites.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => controller.playAll(controller.favorites),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(AppStrings.t('library.playAll')),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => controller.shufflePlay(controller.favorites),
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: Text(AppStrings.t('library.shuffle')),
                ),
              ],
            ),
          ),
        TrackList(
          tracks: controller.favorites,
          controller: controller,
          emptyTitle: AppStrings.t('library.emptyFavoritesTitle'),
          emptyDetail: AppStrings.t('library.emptyFavoritesDetail'),
        ),
      ],
    ),
  );
}

class DownloadsView extends StatelessWidget {
  const DownloadsView({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.downloadingTracks;
    final failed = controller.failedDownloads;
    return PageScaffold(
      kicker: AppStrings.t('kicker.offline'),
      title: AppStrings.t('nav.localMusic'),
      detail: AppStrings.t('library.localDetail'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active.isNotEmpty || failed.isNotEmpty) ...[
            _DownloadingSection(
              controller: controller,
              active: active,
              failed: failed,
            ),
            const SizedBox(height: 14),
          ],
          TrackList(
            tracks: controller.downloads,
            controller: controller,
            emptyTitle: AppStrings.t('library.emptyLocalTitle'),
            emptyDetail: AppStrings.t('library.emptyLocalDetail'),
          ),
        ],
      ),
    );
  }
}

/// In-progress and failed downloads, shown at the top of the local-music page.
class _DownloadingSection extends StatelessWidget {
  const _DownloadingSection({
    required this.controller,
    required this.active,
    required this.failed,
  });

  final AppController controller;
  final List<CatalogTrack> active;
  final List<CatalogTrack> failed;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppStrings.t('download.downloading'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '${active.length}',
              style: TextStyle(color: TimbreColors.gold, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final track in active)
          ValueListenableBuilder<Map<String, double>>(
            valueListenable: controller.downloadProgressListenable,
            builder: (context, progress, _) {
              final fraction = progress[track.ref.toString()];
              return _DownloadRow(
                track: track,
                status: fraction == null
                    ? AppStrings.t('download.inProgress')
                    : AppStrings.t(
                        'download.progressFmt',
                      ).replaceFirst('{p}', '${(fraction * 100).floor()}'),
                busy: true,
                progress: fraction,
                onCancel: () => controller.cancelDownload(track),
              );
            },
          ),
        for (final track in failed)
          _DownloadRow(
            track: track,
            status: controller.downloadErrorFor(track) ?? AppStrings.t('download.failed'),
            busy: false,
            onRetry: () => controller.toggleDownload(track),
          ),
      ],
    ),
  );
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.track,
    required this.status,
    required this.busy,
    this.progress,
    this.onRetry,
    this.onCancel,
  });

  final CatalogTrack track;
  final String status;
  final bool busy;

  /// 0..1 while the size is known; null shows an indeterminate spinner.
  final double? progress;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        TrackArtwork(track: track, size: 40, radius: 9),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${track.artist} · $status',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: busy ? TimbreColors.muted : TimbreColors.gold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (busy) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
              color: TimbreColors.gold,
            ),
          ),
          if (onCancel != null)
            IconButton(
              tooltip: AppStrings.t('download.cancel'),
              iconSize: 18,
              color: TimbreColors.muted,
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
            ),
        ] else if (onRetry != null)
          IconButton(
            tooltip: AppStrings.t('common.retry'),
            iconSize: 18,
            color: TimbreColors.gold,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    ),
  );
}

class RecentView extends StatelessWidget {
  const RecentView({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    final hasTracks = queue.isNotEmpty;
    return PageScaffold(
      kicker: AppStrings.t('kicker.upNext'),
      title: AppStrings.t('queue.title'),
      detail: AppStrings.t('queue.detail'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: hasTracks ? () => controller.playAll(queue) : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(AppStrings.t('player.playAll')),
                style: FilledButton.styleFrom(
                  backgroundColor: TimbreColors.gold,
                  foregroundColor: const Color(0xff2b1e13),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: hasTracks ? controller.clearQueue : null,
                icon: const Icon(Icons.clear_all_rounded, size: 17),
                label: Text(AppStrings.t('queue.clear')),
              ),
              const Spacer(),
              Text(
                '${AppStrings.t('queue.countPrefix')}${queue.length}${AppStrings.t('queue.countSuffix')}',
                style: TextStyle(color: TimbreColors.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasTracks)
            GlassPanel(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    AppStrings.t('queue.empty'),
                    style: TextStyle(color: TimbreColors.muted),
                  ),
                ),
              ),
            )
          else
            GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (var index = 0; index < queue.length; index++)
                    ListTile(
                      dense: true,
                      leading: Text('${index + 1}'.padLeft(2, '0')),
                      title: Text(queue[index].title),
                      subtitle: Text(queue[index].artist),
                      trailing: IconButton(
                        tooltip: AppStrings.t('queue.remove'),
                        onPressed: () => controller.removeFromQueue(index),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      onTap: () => controller.play(queue[index]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
