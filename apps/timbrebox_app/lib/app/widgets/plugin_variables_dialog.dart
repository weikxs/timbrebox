import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../plugins/plugin_manifest.dart';
import '../state/app_controller.dart';

/// Lets the user fill in the settings [plugin] declares (a server address,
/// an account) and saves them; the plugin reads them with
/// `env.getUserVariables()`.
Future<void> showPluginVariablesDialog(
  BuildContext context,
  AppController controller,
  PluginManifest plugin,
) async {
  final values = await controller.pluginVariables(plugin.id);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _PluginVariablesDialog(
      controller: controller,
      plugin: plugin,
      values: values,
    ),
  );
}

class _PluginVariablesDialog extends StatefulWidget {
  const _PluginVariablesDialog({
    required this.controller,
    required this.plugin,
    required this.values,
  });

  final AppController controller;
  final PluginManifest plugin;
  final Map<String, String> values;

  @override
  State<_PluginVariablesDialog> createState() => _PluginVariablesDialogState();
}

class _PluginVariablesDialogState extends State<_PluginVariablesDialog> {
  late final Map<String, TextEditingController> _fields = {
    for (final variable in widget.plugin.variables)
      variable.key: TextEditingController(text: widget.values[variable.key]),
  };
  var _saving = false;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await widget.controller.savePluginVariables(widget.plugin.id, {
        for (final entry in _fields.entries) entry.key: entry.value.text,
      });
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.t('plugin.settingsSaved'))),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.t('plugin.settingsSaveFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      AppStrings.t(
        'plugin.settingsTitleFmt',
      ).replaceFirst('{name}', widget.plugin.platform),
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final variable in widget.plugin.variables) ...[
            _field(variable),
            const SizedBox(height: 12),
          ],
          Text(
            AppStrings.t('plugin.settingsPrivacy'),
            style: TextStyle(color: TimbreColors.muted, fontSize: 11),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: Text(AppStrings.t('common.cancel')),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(AppStrings.t('common.save')),
      ),
    ],
  );

  Widget _field(PluginVariable variable) => TextField(
    controller: _fields[variable.key],
    obscureText: variable.isSecret,
    autocorrect: !variable.isSecret,
    enableSuggestions: !variable.isSecret,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      isDense: true,
      labelText: variable.name,
      hintText: variable.hint,
      border: const OutlineInputBorder(),
    ),
  );
}
