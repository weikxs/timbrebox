import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';
import '../state/app_controller.dart';
import 'glass_panel.dart';
import 'player_progress_bar.dart';
import 'track_artwork.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GlassPanel(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayerRow(
            controller: controller,
            compact: constraints.maxWidth < 560,
          ),
          PlayerProgressBar(controller: controller, showLabels: false),
          if (controller.isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      AppStrings.t(
                        controller.playbackDiagnostics['stage'] == 'opening'
                            ? 'player.openingAudio'
                            : 'player.resolvingAudio',
                      ),
                      key: const ValueKey('mini-player-loading'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          if (controller.playbackError case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Tooltip(
                message: error,
                child: Text(
                  error,
                  key: const ValueKey('mini-player-error'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.controller, required this.compact});
  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      TrackArtwork(track: controller.currentTrack, size: compact ? 32 : 42),
      SizedBox(width: compact ? 8 : 11),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.currentTrack?.title ??
                  AppStrings.t('player.noTrackSelected'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              controller.currentTrack == null
                  ? AppStrings.t('player.chooseFromSearch')
                  : '${controller.currentTrack!.artist} · ${controller.currentTrack!.sourceName}',
              style: TextStyle(color: TimbreColors.muted, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      if (!compact)
        IconButton(
          onPressed: controller.previous,
          tooltip: AppStrings.t('player.previous'),
          icon: const Icon(Icons.skip_previous_rounded),
        ),
      IconButton(
        onPressed: controller.togglePlayback,
        tooltip: AppStrings.t(
          controller.isLoading
              ? 'player.cancelLoading'
              : controller.isPlaying
              ? 'player.pause'
              : 'player.play',
        ),
        icon: Icon(
          controller.isLoading
              ? Icons.cancel_outlined
              : controller.isPlaying
              ? Icons.pause_circle_filled
              : Icons.play_circle_fill,
          color: TimbreColors.gold,
          size: 34,
        ),
      ),
      PlaybackModeButton(controller: controller),
      if (!compact)
        IconButton(
          onPressed: controller.next,
          tooltip: AppStrings.t('player.next'),
          icon: const Icon(Icons.skip_next_rounded),
        ),
      if (!compact) const SizedBox(width: 4),
      if (!compact)
        RepaintBoundary(
          child: ValueListenableBuilder<Duration>(
            valueListenable: controller.positionListenable,
            builder: (context, _, _) => Text(
              '${controller.positionLabel}  /  ${controller.playbackDurationLabel}',
              style: TextStyle(color: TimbreColors.muted, fontSize: 11),
            ),
          ),
        ),
    ],
  );
}

class PlaybackModeButton extends StatelessWidget {
  const PlaybackModeButton({
    required this.controller,
    this.showLabel = false,
    super.key,
  });

  final AppController controller;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => PopupMenuButton<PlaybackLoop>(
    tooltip: '${AppStrings.t('player.playbackMode')}${controller.loop.label}',
    initialValue: controller.loop,
    onSelected: controller.setLoop,
    itemBuilder: (context) => [
      for (final mode in PlaybackLoop.values)
        PopupMenuItem(
          value: mode,
          child: Row(
            children: [
              Icon(
                mode.icon,
                size: 18,
                color: mode == controller.loop
                    ? TimbreColors.gold
                    : TimbreColors.muted,
              ),
              const SizedBox(width: 9),
              Text(mode.label),
            ],
          ),
        ),
    ],
    icon: showLabel ? null : _icon(),
    child: showLabel
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _icon(),
                const SizedBox(width: 6),
                Text(controller.loop.label),
              ],
            ),
          )
        : null,
  );

  Widget _icon() => Icon(
    controller.loop.icon,
    color: controller.loop == PlaybackLoop.off
        ? TimbreColors.muted
        : TimbreColors.gold,
  );
}
