import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import '../design/app_themes.dart';
import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';
import '../state/app_controller.dart';
import '../state/diagnostic_log.dart';
import '../state/download_paths.dart';
import 'playback_rate_control.dart';
import 'settings_common.dart';
import 'settings_plugins_section.dart';
import 'settings_shortcuts_section.dart';
import 'sleep_timer_control.dart';

class SettingsSectionContent extends StatelessWidget {
  const SettingsSectionContent({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => switch (controller.settingsSection) {
    SettingsSection.general => _GeneralSettings(controller: controller),
    SettingsSection.appearance => _AppearanceSettings(controller: controller),
    SettingsSection.sources => _SourceSettings(controller: controller),
    SettingsSection.plugins => PluginSettings(controller: controller),
    SettingsSection.downloads => _DownloadSettings(controller: controller),
    SettingsSection.shortcuts => ShortcutsSettings(controller: controller),
  };
}

class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => SettingsPanel(
    title: AppStrings.t('settings.appearance'),
    detail: AppStrings.t('settings.appearanceDetail'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final theme in kAppThemes)
              _ThemeSwatch(
                theme: theme,
                selected: !controller.hasSkin && controller.themeId == theme.id,
                onTap: () => controller.selectTheme(theme.id),
              ),
          ],
        ),
        GroupLabel(AppStrings.t('settings.custom')),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => _pickSkin(context, controller),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(AppStrings.t(controller.hasSkin ? 'settings.changeBg' : 'settings.uploadBg')),
              style: FilledButton.styleFrom(
                backgroundColor: TimbreColors.gold,
                foregroundColor: const Color(0xff2b1e13),
              ),
            ),
            const SizedBox(width: 12),
            if (controller.hasSkin)
              Text(
                AppStrings.t('settings.usingCustomBg'),
                style: TextStyle(color: TimbreColors.muted, fontSize: 12),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _pickSkin(BuildContext context, AppController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await controller.setSkinFromFile(path);
      messenger.showSnackBar(SnackBar(content: Text(AppStrings.t('settings.bgApplied'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(AppStrings.t('settings.bgReadFailed'))));
    }
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = theme.palette;
    final gradient = palette != null
        ? LinearGradient(
            colors: [palette.canvasRaised, palette.canvas],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        // "Follow system" — a hard diagonal split of light and dark.
        : LinearGradient(
            colors: [
              kLightPalette.canvasRaised,
              kLightPalette.canvasRaised,
              kDarkPalette.canvas,
              kDarkPalette.canvas,
            ],
            stops: [0, 0.5, 0.5, 1],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final accent = (palette ?? kDarkPalette).gold;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: gradient,
              border: Border.all(
                color: selected ? TimbreColors.gold : TimbreColors.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check_rounded, color: accent, size: 20)
                : Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.t(theme.nameKey),
            style: TextStyle(
              fontSize: 11,
              color: selected ? TimbreColors.ink : TimbreColors.muted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => SettingsPanel(
    title: AppStrings.t('settings.general'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(AppStrings.t('settings.language')),
          trailing: DropdownButton<String>(
            value: controller.language,
            onChanged: (value) {
              if (value != null) controller.setLanguage(value);
            },
            items: const [
              DropdownMenuItem(value: '简体中文', child: Text('简体中文')),
              DropdownMenuItem(value: 'English', child: Text('English')),
            ],
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: controller.autoPlay,
          onChanged: controller.setAutoPlay,
          title: Text(AppStrings.t('settings.restoreSession')),
        ),
        GroupLabel(AppStrings.t('settings.playback')),
        Text('${AppStrings.t('settings.volume')} ${(controller.volume * 100).round()}%'),
        Slider(value: controller.volume, onChanged: controller.setVolume),
        const SizedBox(height: 2),
        Text(
          AppStrings.t('settings.loopMode'),
          style: TextStyle(color: TimbreColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final mode in PlaybackLoop.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: controller.loop == mode,
                onSelected: (_) => controller.setLoop(mode),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: DropdownButton<QualityPreference>(
            value: controller.quality,
            onChanged: (choice) {
              if (choice != null) controller.setQuality(choice);
            },
            items: [
              for (final quality in QualityPreference.values)
                DropdownMenuItem(
                  value: quality,
                  child: Text('${AppStrings.t('settings.defaultQuality')}${quality.label}'),
                ),
            ],
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: controller.releaseAfterPause,
          onChanged: controller.setReleaseAfterPause,
          title: Text(AppStrings.t('settings.releaseAfterPause')),
        ),
        const SizedBox(height: 10),
        PlaybackRateControl(controller: controller),
        const SizedBox(height: 10),
        SleepTimerControl(controller: controller),
        GroupLabel(AppStrings.t('settings.appearancePrivacy')),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: controller.reducedEffects,
          onChanged: controller.setReducedEffects,
          title: Text(AppStrings.t('settings.reducedEffects')),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: controller.diagnosticLogging,
          onChanged: controller.setDiagnosticLogging,
          title: Text(AppStrings.t('settings.diagnosticLogging')),
          subtitle: Text(AppStrings.t('settings.diagnosticSubtitle')),
        ),
        if (controller.diagnosticLogging)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showDiagnostics(context),
              icon: const Icon(Icons.article_outlined, size: 16),
              label: Text(AppStrings.t('settings.viewDiagnostics')),
            ),
          ),
        GroupLabel(AppStrings.t('settings.agentControl')),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: controller.agentControlEnabled,
          onChanged: (v) => controller.setAgentControlEnabled(v),
          title: Text(AppStrings.t('agent.localInterface')),
          subtitle: Text(AppStrings.t('agent.interfaceSubtitle')),
        ),
        if (controller.agentControlEnabled) _AgentControlInfo(controller: controller),
      ],
    ),
  );
}

void _showDiagnostics(BuildContext context) {
  final text = DiagnosticLog.text;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppStrings.t('settings.diagnosticsTitle')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: SelectableText(
            text.isEmpty ? AppStrings.t('settings.noLogs') : text,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            DiagnosticLog.clear();
            Navigator.of(dialogContext).pop();
          },
          child: Text(AppStrings.t('common.clear')),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            Navigator.of(dialogContext).pop();
          },
          child: Text(AppStrings.t('common.copy')),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppStrings.t('common.close')),
        ),
      ],
    ),
  );
}

class _AgentControlInfo extends StatelessWidget {
  const _AgentControlInfo({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.agentControlError;
    final address =
        error ?? controller.agentControlAddress ?? AppStrings.t('agent.starting');
    final tokenPath = controller.agentControlTokenPath ?? '…';
    final example =
        'curl -H "X-TimbreBox-Token: \$(cat \'$tokenPath\')" "$address/status"';
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TimbreColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: TimbreColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(AppStrings.t('agent.address'), address),
          const SizedBox(height: 6),
          _kv(AppStrings.t('agent.token'), tokenPath),
          const SizedBox(height: 8),
          Text(
            '${AppStrings.t('agent.exampleLabel')}$example\n'
            '${AppStrings.t('agent.endpointsLabel')}GET /status /queue /sources /lyric · '
            'POST /search?q= /play-ref?source=&item= /play /pause /toggle /next '
            '/previous /stop /seek?ms= /volume?level= /mode?loop= /quit',
            style: TextStyle(
              color: TimbreColors.muted,
              fontSize: 10.5,
              fontFamily: 'monospace',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: example));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppStrings.t('agent.copiedUrl'))),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: Text(AppStrings.t('common.copy')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 36,
        child: Text(
          key,
          style: TextStyle(color: TimbreColors.muted, fontSize: 11),
        ),
      ),
      Expanded(
        child: SelectableText(
          value,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ),
    ],
  );
}

class _SourceSettings extends StatelessWidget {
  const _SourceSettings({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => SettingsPanel(
    title: AppStrings.t('settings.builtinSources'),
    detail: AppStrings.t('settings.sourcesDetail'),
    child: Column(
      children: [
        for (final source in controller.sourceDescriptors) ...[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value:
                source.availability == SourceAvailability.available &&
                controller.sourceEnabled(source.id),
            onChanged: source.availability == SourceAvailability.available
                ? (enabled) => controller.setSourceEnabled(source.id, enabled)
                : null,
            title: Text(source.name),
            subtitle: Text(
              source.unavailableReason ?? _sourceDetail(source.id),
              style: TextStyle(color: TimbreColors.muted, fontSize: 11),
            ),
          ),
        ],
      ],
    ),
  );
}

class _DownloadSettings extends StatefulWidget {
  const _DownloadSettings({required this.controller});
  final AppController controller;

  @override
  State<_DownloadSettings> createState() => _DownloadSettingsState();
}

class _DownloadSettingsState extends State<_DownloadSettings> {
  // Resolve once — SettingsView rebuilds on every controller change, so calling
  // resolveDownloadDirectory() in build() would re-run and flicker the tile.
  late final Future<Directory> _directory = resolveDownloadDirectory();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return SettingsPanel(
      title: AppStrings.t('download.settingsTitle'),
      detail: AppStrings.t('download.settingsDetail'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<Directory>(
            future: _directory,
            builder: (context, snapshot) => _DirectoryTile(
            path: snapshot.hasData ? snapshot.data!.path : AppStrings.t('download.resolving'),
            ready: snapshot.hasData,
          ),
        ),
        Divider(height: 22, color: TimbreColors.line),
        Row(
          children: [
            Text(AppStrings.t('download.downloaded')),
            const Spacer(),
            Text(
              AppStrings.t('count.tracksFmt').replaceFirst('{n}', '${controller.downloads.length}'),
              style: TextStyle(color: TimbreColors.gold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: controller.downloads.isEmpty
                ? null
                : () => _confirmClear(context, controller),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: Text(AppStrings.t('download.clearLocal')),
          ),
        ),
        ],
      ),
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({required this.path, required this.ready});
  final String path;
  final bool ready;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: TimbreColors.panel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: TimbreColors.line),
    ),
    child: Row(
      children: [
        Icon(Icons.folder_outlined, size: 18, color: TimbreColors.gold),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.t('download.saveDir'),
                style: TextStyle(fontSize: 11, color: TimbreColors.muted),
              ),
              const SizedBox(height: 3),
              SelectableText(
                path,
                maxLines: 2,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        if (ready) ...[
          IconButton(
            tooltip: AppStrings.t('download.copyPath'),
            iconSize: 18,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppStrings.t('download.pathCopied'))),
              );
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          if (_canRevealFolder)
            IconButton(
              tooltip: AppStrings.t('download.openInFileManager'),
              iconSize: 18,
              color: TimbreColors.gold,
              onPressed: () => _revealFolder(path),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ],
    ),
  );
}

bool get _canRevealFolder =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> _revealFolder(String path) async {
  try {
    await Directory(path).create(recursive: true);
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  } catch (_) {
    // Best-effort: revealing the folder is a convenience, not critical.
  }
}

void _confirmClear(BuildContext context, AppController controller) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppStrings.t('download.clearLocal')),
      content: Text(AppStrings.t('download.clearConfirm')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppStrings.t('common.cancel')),
        ),
        TextButton(
          onPressed: () {
            controller.clearDownloads();
            Navigator.of(dialogContext).pop();
          },
          child: Text(AppStrings.t('common.clear'), style: TextStyle(color: TimbreColors.gold)),
        ),
      ],
    ),
  );
}

String _sourceDetail(String sourceId) => switch (sourceId) {
  'audius' => AppStrings.t('source.audiusDetail'),
  'radio_browser' => AppStrings.t('source.radioDetail'),
  _ => AppStrings.t('source.builtinDetail'),
};
