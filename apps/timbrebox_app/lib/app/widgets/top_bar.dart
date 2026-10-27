import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import 'glass_panel.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    required this.sectionName,
    required this.onSearch,
    required this.compact,
    required this.activeIndex,
    required this.sections,
    required this.onSectionSelected,
    super.key,
  });
  final String sectionName;
  final ValueChanged<String> onSearch;
  final bool compact;
  final int activeIndex;
  final List<String> sections;
  final ValueChanged<int> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final light = TimbreColors.active.brightness == Brightness.light;
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (compact)
            PopupMenuButton<int>(
              tooltip: AppStrings.t('top.switchPage'),
              icon: const Icon(Icons.menu_rounded),
              onSelected: onSectionSelected,
              itemBuilder: (context) => [
                for (var index = 0; index < sections.length; index++)
                  CheckedPopupMenuItem(
                    value: index,
                    checked: activeIndex == index,
                    child: Text(sections[index]),
                  ),
              ],
            )
          else
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: AppStrings.t('top.yourSpace'),
                      style: TextStyle(color: TimbreColors.ink),
                    ),
                    TextSpan(
                      text: '  /  $sectionName',
                      style: TextStyle(color: TimbreColors.muted),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (compact) const SizedBox(width: 8),
          SizedBox(
            width: compact ? 190 : 250,
            height: 38,
            child: TextField(
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
              decoration: InputDecoration(
                hintText: AppStrings.t('top.searchHint'),
                hintStyle: TextStyle(color: TimbreColors.muted, fontSize: 12),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: TimbreColors.gold,
                ),
                suffixIcon: Padding(
                  padding: EdgeInsets.all(9),
                  child: Text(
                    '⌘ K',
                    style: TextStyle(color: TimbreColors.muted, fontSize: 9),
                  ),
                ),
                filled: true,
                fillColor: light
                    ? Colors.black.withValues(alpha: .04)
                    : Colors.white.withValues(alpha: .06),
                contentPadding: EdgeInsets.zero,
                border: _border(TimbreColors.line),
                enabledBorder: _border(TimbreColors.line),
                focusedBorder: _border(TimbreColors.gold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(22),
    borderSide: BorderSide(color: color),
  );
}
