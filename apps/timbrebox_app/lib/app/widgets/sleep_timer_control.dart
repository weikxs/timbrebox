import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../state/app_controller.dart';

/// Sleep-timer chips for the settings General tab: pick a duration to pause
/// playback after, or turn it off. Shows a live remaining countdown.
class SleepTimerControl extends StatelessWidget {
  const SleepTimerControl({required this.controller, super.key});

  final AppController controller;

  static const List<int> _minuteOptions = [15, 30, 60, 90];

  @override
  Widget build(BuildContext context) {
    final total = controller.sleepTimerTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppStrings.t('settings.sleepTimer'),
              style: TextStyle(color: TimbreColors.muted, fontSize: 12),
            ),
            // The countdown ticks every second; only this label follows it.
            ValueListenableBuilder<Duration?>(
              valueListenable: controller.sleepRemainingListenable,
              builder: (context, _, _) {
                final remaining = controller.sleepTimerLabel;
                if (remaining == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '· $remaining',
                    style: TextStyle(
                      color: TimbreColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(AppStrings.t('settings.sleepOff')),
              selected: !controller.hasSleepTimer,
              onSelected: (_) => controller.setSleepTimer(null),
            ),
            for (final minutes in _minuteOptions)
              ChoiceChip(
                label: Text(
                  AppStrings.t('settings.minutesFmt').replaceFirst(
                    '{m}',
                    '$minutes',
                  ),
                ),
                selected: total == Duration(minutes: minutes),
                onSelected: (_) =>
                    controller.setSleepTimer(Duration(minutes: minutes)),
              ),
          ],
        ),
      ],
    );
  }
}
