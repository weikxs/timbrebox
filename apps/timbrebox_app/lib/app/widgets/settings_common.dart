import 'package:flutter/material.dart';

import '../design/timbre_colors.dart';
import 'glass_panel.dart';

/// A titled glass panel wrapping one settings section.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    required this.title,
    required this.child,
    this.detail,
    super.key,
  });

  final String title;
  final String? detail;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        if (detail != null) ...[
          const SizedBox(height: 3),
          Text(
            detail!,
            style: TextStyle(color: TimbreColors.muted, fontSize: 10),
          ),
        ],
        const SizedBox(height: 5),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 13),
          child: child,
        ),
      ],
    ),
  );
}

/// A gold, uppercase group divider label inside a settings panel.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
    child: Row(
      children: [
        Text(
          text,
          style: TextStyle(
            color: TimbreColors.gold,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: TimbreColors.line, height: 1)),
      ],
    ),
  );
}
