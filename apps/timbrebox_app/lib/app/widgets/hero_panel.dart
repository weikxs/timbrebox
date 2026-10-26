import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../design/app_effects.dart';
import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';
import '../state/app_controller.dart';
import 'lyrics_view.dart';
import 'mini_player.dart';
import 'player_progress_bar.dart';
import 'playlists_panel.dart';

class HeroPanel extends StatelessWidget {
  const HeroPanel({
    required this.controller,
    required this.onOpenSearch,
    super.key,
  });
  final AppController controller;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked = constraints.maxWidth < 620;
      final nowPlaying = _NowPlayingDesk(controller: controller);
      final queue = _QueueDesk(
        controller: controller,
        onOpenSearch: onOpenSearch,
      );

      final light = TimbreColors.active.brightness == Brightness.light;
      final rounded = BorderRadius.circular(22);
      final body = stacked
          ? Column(
              children: [
                Expanded(flex: 11, child: nowPlaying),
                Divider(height: 1, color: TimbreColors.line),
                Expanded(flex: 9, child: queue),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 12, child: nowPlaying),
                VerticalDivider(width: 1, color: TimbreColors.line),
                Expanded(flex: 9, child: queue),
              ],
            );
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: rounded,
          boxShadow: [
            BoxShadow(
              color: light ? const Color(0x24101826) : const Color(0x5e000000),
              blurRadius: light ? 34 : 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: rounded,
          // A translucent frosted card: the backdrop blur lets the app
          // background bleed through for a liquid-glass depth. Dropped (with a
          // near-opaque fill) when "reduce visual effects" is on.
          child: _frost(
            reduced: AppEffects.reduced,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: rounded,
                border: Border.all(
                  color: Colors.white.withValues(alpha: light ? .5 : .1),
                  width: .8,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    TimbreColors.canvasRaised.withValues(
                      alpha: AppEffects.reduced ? 1 : .82,
                    ),
                    TimbreColors.canvas.withValues(
                      alpha: AppEffects.reduced ? 1 : .82,
                    ),
                  ],
                ),
              ),
              child: body,
            ),
          ),
        ),
      );
    },
  );
}

class _NowPlayingDesk extends StatelessWidget {
  const _NowPlayingDesk({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack;
    final favorite = track != null && controller.isFavorite(track);
    return Stack(
      fit: StackFit.expand,
      children: [
        _VinylHalo(spinning: controller.isPlaying),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 25, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track == null
                    ? AppStrings.t('player.listening')
                    : '${AppStrings.t('player.nowPlaying')}  ·  ${track.sourceName}',
                style: TextStyle(
                  color: TimbreColors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              Text(
                track?.title ?? AppStrings.t('player.pickTrack'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 35,
                  height: .96,
                  letterSpacing: -1.6,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '${track?.artist ?? AppStrings.t('player.searchPublic')} · ${track?.sourceName ?? AppStrings.t('player.noSource')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: TimbreColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                controller.isLoading
                    ? AppStrings.t('player.resolvingStream')
                    : track == null
                    ? AppStrings.t('player.readyToListen')
                    : '${track.durationLabel} · ${track.quality}',
                style: TextStyle(color: TimbreColors.muted, fontSize: 11),
              ),
              const Spacer(),
              PlayerProgressBar(controller: controller),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 420;
                  return Row(
                    children: [
                      _ControlButton(
                        icon: Icons.skip_previous_rounded,
                        tooltip: AppStrings.t('player.previous'),
                        onPressed: controller.previous,
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: controller.togglePlayback,
                        icon: Icon(
                          controller.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 19,
                        ),
                        label: Text(
                          controller.isLoading
                              ? AppStrings.t('player.resolving')
                              : controller.isPlaying
                              ? AppStrings.t('player.pause')
                              : AppStrings.t('player.play'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: TimbreColors.gold,
                          foregroundColor: const Color(0xff2b1e13),
                          minimumSize: const Size(104, 38),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ControlButton(
                        icon: Icons.skip_next_rounded,
                        tooltip: AppStrings.t('player.next'),
                        onPressed: controller.next,
                      ),
                      const Spacer(),
                      if (controller.currentTrackHasLyric)
                        IconButton(
                          onPressed: () => showLyricsSheet(context, controller),
                          tooltip: AppStrings.t('player.lyrics'),
                          icon: const Icon(Icons.lyrics_outlined),
                          color: TimbreColors.muted,
                        ),
                      PlaybackModeButton(
                        controller: controller,
                        showLabel: !narrow,
                      ),
                      if (!narrow) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () {
                            if (track != null) controller.toggleFavorite(track);
                          },
                          tooltip: AppStrings.t(
                            favorite
                                ? 'common.unfavorite'
                                : 'player.favoriteThis',
                          ),
                          icon: Icon(
                            favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                          color: favorite
                              ? TimbreColors.gold
                              : TimbreColors.muted,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QueueDesk extends StatelessWidget {
  const _QueueDesk({required this.controller, required this.onOpenSearch});

  final AppController controller;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.queue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(21, 23, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t('player.upNext'),
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 23),
                ),
              ),
              if (tracks.isNotEmpty)
                IconButton(
                  tooltip: AppStrings.t('player.saveQueue'),
                  icon: const Icon(Icons.playlist_add_rounded, size: 20),
                  color: TimbreColors.gold,
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final name = await promptPlaylistName(context);
                    if (name == null || name.isEmpty) return;
                    controller.saveQueueAsPlaylist(name);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(AppStrings.t('player.queueSaved')),
                      ),
                    );
                  },
                ),
              IconButton(
                onPressed: onOpenSearch,
                tooltip: AppStrings.t('player.searchMusic'),
                icon: const Icon(Icons.search_rounded, size: 20),
                color: TimbreColors.gold,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            AppStrings.t(
              'player.inQueueFmt',
            ).replaceFirst('{n}', '${tracks.length}'),
            style: TextStyle(color: TimbreColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: tracks.length,
              onReorderItem: (oldIndex, newIndex) =>
                  controller.reorderQueue(oldIndex, newIndex),
              itemBuilder: (context, index) => _QueueRow(
                key: ValueKey(tracks[index].ref),
                index: index,
                track: tracks[index],
                controller: controller,
              ),
            ),
          ),
          if (controller.playbackError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.playbackError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: TimbreColors.gold, fontSize: 10),
                  ),
                ),
                // The way back when a saved track no longer resolves.
                TextButton(
                  onPressed: () {
                    unawaited(controller.searchAgainForCurrent());
                    onOpenSearch();
                  },
                  child: Text(
                    AppStrings.t('player.searchAgain'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.index,
    required this.track,
    required this.controller,
    super.key,
  });

  final int index;
  final CatalogTrack track;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.currentTrack?.ref == track.ref;
    return InkWell(
      onTap: () => controller.play(track),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}'.padLeft(2, '0'),
                style: TextStyle(color: TimbreColors.muted, fontSize: 11),
              ),
            ),
            Icon(
              active && controller.isPlaying
                  ? Icons.graphic_eq_rounded
                  : Icons.play_arrow_rounded,
              size: 18,
              color: active ? TimbreColors.gold : TimbreColors.muted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? TimbreColors.ink : TimbreColors.muted,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: TimbreColors.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              track.durationLabel,
              style: TextStyle(color: TimbreColors.muted, fontSize: 10),
            ),
            const SizedBox(width: 4),
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: AppStrings.t('player.reorderQueue'),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 18,
                  color: TimbreColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon),
    iconSize: 21,
    color: TimbreColors.ink,
    style: IconButton.styleFrom(
      backgroundColor: TimbreColors.panelStrong,
      side: BorderSide(color: TimbreColors.line),
    ),
  );
}

/// Wraps [child] in a backdrop blur unless visual effects are reduced.
Widget _frost({required bool reduced, required Widget child}) => reduced
    ? child
    : BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: child,
      );

/// The turntable halo behind the now-playing text. It spins while audio is
/// playing and freezes in place when paused, like a real record deck. It also
/// stops while the app is not in the foreground.
class _VinylHalo extends StatefulWidget {
  const _VinylHalo({required this.spinning});

  final bool spinning;

  @override
  State<_VinylHalo> createState() => _VinylHaloState();
}

class _VinylHaloState extends State<_VinylHalo> {
  /// One full turn of the record.
  static const _period = Duration(seconds: 14);

  /// About 12 frames a second: smooth enough for a slow-turning record, and
  /// a fifth of the frames a vsync-driven animation would make. Every frame
  /// recomposites the whole window, frosted glass included.
  static const _frameInterval = Duration(milliseconds: 83);

  static final double _turnsPerFrame =
      _frameInterval.inMicroseconds / _period.inMicroseconds;

  /// The record's angle in turns; the painter repaints when it changes.
  final ValueNotifier<double> _turns = ValueNotifier(0);
  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;

  bool get _foreground {
    final state = SchedulerBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  bool get _shouldSpin => widget.spinning && !AppEffects.reduced && _foreground;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _syncSpin());
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant _VinylHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  void _syncSpin() {
    if (_shouldSpin && _ticker == null) {
      _ticker = Timer.periodic(_frameInterval, (_) => _advance());
    } else if (!_shouldSpin && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _advance() => _turns.value = (_turns.value + _turnsPerFrame) % 1;

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    _turns.dispose();
    super.dispose();
  }

  // The painter repaints itself from [_turns] (no rebuild, no relayout of the
  // panel), and the boundary keeps each frame from repainting the frosted
  // panel around it.
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: const Alignment(.85, -.24),
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size.square(218),
          painter: _VinylPainter(_turns),
        ),
      ),
    ),
  );
}

/// Paints the vinyl record: grooves, a rotating light glint that makes the
/// spin visible, a gold centre label, and the spindle hole. The record is
/// recorded once into a picture; each frame only draws it rotated by [turns].
class _VinylPainter extends CustomPainter {
  _VinylPainter(this.turns) : super(repaint: turns);

  final ValueListenable<double> turns;

  static const _gold = Color(0xffe1b27b);

  /// The recorded record and the size it was recorded at.
  static (Size, Picture)? _record;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(turns.value * 2 * pi)
      ..translate(-center.dx, -center.dy)
      ..drawPicture(_recordFor(size))
      ..restore();
  }

  static Picture _recordFor(Size size) {
    final cached = _record;
    if (cached != null && cached.$1 == size) return cached.$2;
    cached?.$2.dispose();
    final recorder = PictureRecorder();
    _drawRecord(Canvas(recorder), size);
    final picture = recorder.endRecording();
    _record = (size, picture);
    return picture;
  }

  static void _drawRecord(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, Paint()..color = const Color(0x0effca91));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x2ee1b27b),
    );

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x14e1b27b);
    for (var r = radius - 10; r > radius * 0.36; r -= 7) {
      canvas.drawCircle(center, r, groove);
    }

    // A short bright arc near the rim; rotating it is what reads as motion.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      -0.6,
      0.75,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x55ffd9a6),
    );

    final labelRadius = radius * 0.30;
    canvas.drawCircle(
      center,
      labelRadius,
      Paint()..color = const Color(0x40e1b27b),
    );
    canvas.drawCircle(
      center,
      labelRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33e1b27b),
    );

    _paintNote(canvas, center, labelRadius);

    canvas.drawCircle(center, 3, Paint()..color = const Color(0xff20211c));
  }

  /// Draws a music note glyph as the record's centre label art.
  static void _paintNote(Canvas canvas, Offset center, double labelRadius) {
    const note = Icons.music_note_rounded;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(note.codePoint),
        style: TextStyle(
          fontSize: labelRadius * 1.25,
          fontFamily: note.fontFamily,
          package: note.fontPackage,
          color: _gold.withValues(alpha: .9),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => oldDelegate.turns != turns;
}
