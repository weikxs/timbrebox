import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../state/app_controller.dart';

/// Playback-speed chips for the settings General tab (0.5×–2×). A true equalizer
/// is not offered because the audio engine exposes no filter API.
class PlaybackRateControl extends StatelessWidget {
  const PlaybackRateControl({required this.controller, super.key});

  final AppController controller;

  static const List<double> _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        AppStrings.t('settings.playbackSpeed'),
        style: TextStyle(color: TimbreColors.muted, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final rate in _rates)
            ChoiceChip(
              label: Text(
                rate == 1.0
                    ? AppStrings.t('settings.speedNormal')
                    : '${rate.toString().replaceAll('.0', '')}×',
              ),
              selected: (controller.playbackRate - rate).abs() < 0.001,
              onSelected: (_) => controller.setPlaybackRate(rate),
            ),
        ],
      ),
    ],
  );
}
