import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../state/app_controller.dart';
import 'settings_common.dart';

/// Settings → Plugins: install from a URL, check for updates, switch
/// installed plugins on or off, uninstall.
class PluginSettings extends StatefulWidget {
  const PluginSettings({required this.controller, super.key});
  final AppController controller;

  @override
  State<PluginSettings> createState() => _PluginSettingsState();
}

class _PluginSettingsState extends State<PluginSettings> {
  final _urlController = TextEditingController();
  var _installing = false;
  var _updating = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final plugins = controller.plugins;
    return SettingsPanel(
      title: AppStrings.t('plugin.title'),
      detail: AppStrings.t('plugin.detail'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!controller.supportsPlugins)
            Text(
              AppStrings.t('plugin.unsupported'),
              style: TextStyle(color: TimbreColors.muted, fontSize: 12),
            )
          else ...[
            TextField(
              controller: _urlController,
              enabled: !_installing,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: AppStrings.t('plugin.urlHint'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _install(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _installing ? null : _install,
                  icon: _installing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded, size: 17),
                  label: Text(
                    AppStrings.t(
                      _installing ? 'plugin.installing' : 'plugin.install',
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: TimbreColors.gold,
                    foregroundColor: const Color(0xff2b1e13),
                  ),
                ),
                if (plugins.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _updating ? null : _update,
                    icon: _updating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      AppStrings.t(
                        _updating ? 'plugin.checking' : 'plugin.checkUpdates',
                      ),
                    ),
                  ),
                ],
              ],
            ),
            GroupLabel(AppStrings.t('plugin.installed')),
            if (plugins.isEmpty)
              Text(
                AppStrings.t('plugin.none'),
                style: TextStyle(color: TimbreColors.muted, fontSize: 12),
              )
            else
              for (final plugin in plugins)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${plugin.platform}  ·  v${plugin.version}'),
                  subtitle: plugin.author == null
                      ? null
                      : Text(
                          plugin.author!,
                          style: TextStyle(
                            color: TimbreColors.muted,
                            fontSize: 11,
                          ),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch.adaptive(
                        value: controller.sourceEnabled(plugin.id),
                        onChanged: (enabled) =>
                            controller.setSourceEnabled(plugin.id, enabled),
                      ),
                      IconButton(
                        tooltip: AppStrings.t('plugin.uninstall'),
                        iconSize: 18,
                        onPressed: () => controller.removePlugin(plugin.id),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _install() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final confirmed = await _confirmInstall(url);
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _installing = true);
    try {
      final count = await widget.controller.installPluginFromUrl(url);
      _urlController.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.t(
              'plugin.installedCountFmt',
            ).replaceFirst('{n}', '$count'),
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.t(
              'plugin.installFailedFmt',
            ).replaceFirst('{e}', '$error'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _update() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updating = true);
    try {
      final count = await widget.controller.updatePlugins();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? AppStrings.t(
                    'plugin.updatedCountFmt',
                  ).replaceFirst('{n}', '$count')
                : AppStrings.t('plugin.upToDate'),
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.t(
              'plugin.updateFailedFmt',
            ).replaceFirst('{e}', '$error'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<bool> _confirmInstall(String url) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.t('plugin.confirmTitle')),
        content: Text('${AppStrings.t('plugin.confirmBody')}\n\n$url'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              AppStrings.t('plugin.confirmInstall'),
              style: TextStyle(color: TimbreColors.gold),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
