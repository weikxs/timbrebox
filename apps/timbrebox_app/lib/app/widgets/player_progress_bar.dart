import 'package:flutter/material.dart';

import '../design/timbre_colors.dart';
import '../state/app_controller.dart';

/// Seekable playback progress bar bound to the live position/duration streams
/// exposed by [AppController]. It never fabricates a duration: when the current
/// source has no known length (live radio, unresolved stream) the track stays
/// non-seekable and the total reads `--:--`.
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    required this.controller,
    this.showLabels = true,
    super.key,
  });

  final AppController controller;
  final bool showLabels;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  double? _dragValue;

  // Rebuilt by itself once per shown second; see
  // [AppController.positionListenable]. The boundary keeps that repaint off
  // the glass panel around it.
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ValueListenableBuilder<Duration>(
      valueListenable: widget.controller.positionListenable,
      builder: (context, _, _) => _buildBar(),
    ),
  );

  Widget _buildBar() {
    final controller = widget.controller;
    final totalMs = controller.playbackDuration.inMilliseconds;
    final seekable = totalMs > 0 && controller.currentTrack != null;
    final progress = seekable
        ? (controller.position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final value = _dragValue ?? progress;
    // While seekable, always render a real MM:SS (including 00:00) so the
    // elapsed time never reads as an unknown `--:--` during playback.
    final elapsed = !seekable
        ? controller.positionLabel
        : _format(
            Duration(
              milliseconds: _dragValue != null
                  ? (_dragValue! * totalMs).round()
                  : controller.position.inMilliseconds,
            ),
          );

    final slider = SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: TimbreColors.gold,
        inactiveTrackColor: TimbreColors.line,
        thumbColor: TimbreColors.gold,
        overlayColor: TimbreColors.gold.withValues(alpha: .14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: value.clamp(0.0, 1.0),
        // Announce the elapsed time instead of a raw 0..1 fraction.
        semanticFormatterCallback: (fraction) =>
            _format(Duration(milliseconds: (fraction * totalMs).round())),
        onChanged: seekable
            ? (next) => setState(() => _dragValue = next)
            : null,
        onChangeEnd: seekable
            ? (next) {
                setState(() => _dragValue = null);
                controller.seek(
                  Duration(milliseconds: (next * totalMs).round()),
                );
              }
            : null,
      ),
    );

    if (!widget.showLabels) {
      return SizedBox(height: 20, child: slider);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 22, child: slider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(elapsed, style: _timeStyle),
              Text(controller.playbackDurationLabel, style: _timeStyle),
            ],
          ),
        ),
      ],
    );
  }

  // An instance getter (not `static final`) so it re-reads the live palette on
  // every build — a cached static would freeze the muted color at first theme.
  TextStyle get _timeStyle => TextStyle(
    color: TimbreColors.muted,
    fontSize: 11,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
