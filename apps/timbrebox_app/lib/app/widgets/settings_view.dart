import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';
import '../state/app_controller.dart';
import 'page_scaffold.dart';
import 'settings_sections.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => PageScaffold(
    kicker: AppStrings.t('kicker.settings'),
    title: AppStrings.t('nav.settings'),
    detail: _detailFor(controller.settingsSection),
    compact: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsTabs(controller: controller),
        const SizedBox(height: 12),
        SettingsSectionContent(controller: controller),
      ],
    ),
  );

  String _detailFor(SettingsSection section) =>
      AppStrings.t('settings.detail.${section.name}');
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final section in SettingsSection.values)
        ChoiceChip(
          label: Text(AppStrings.t('settings.${section.name}')),
          selected: controller.settingsSection == section,
          onSelected: (_) => controller.setSettingsSection(section),
          selectedColor: TimbreColors.gold.withValues(alpha: .18),
          labelStyle: TextStyle(
            color: controller.settingsSection == section
                ? TimbreColors.ink
                : TimbreColors.muted,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
    ],
  );
}
