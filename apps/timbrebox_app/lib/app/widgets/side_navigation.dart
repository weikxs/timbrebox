import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../state/app_controller.dart';
import 'glass_panel.dart';
import 'timbre_brand_mark.dart';

class SideNavigation extends StatelessWidget {
  const SideNavigation({
    required this.activeIndex,
    required this.onSelected,
    required this.controller,
    super.key,
  });

  final int activeIndex;
  final ValueChanged<int> onSelected;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 212,
      child: GlassPanel(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Brand(),
            _Label(AppStrings.t('nav.browse')),
            _NavItem(
              AppStrings.t('nav.home'),
              Icons.home_outlined,
              0,
              activeIndex,
              onSelected,
            ),
            _NavItem(
              AppStrings.t('nav.search'),
              Icons.search,
              1,
              activeIndex,
              onSelected,
            ),
            _NavItem(
              AppStrings.t('nav.hot'),
              Icons.local_fire_department_outlined,
              2,
              activeIndex,
              onSelected,
            ),
            const SizedBox(height: 16),
            _Label(AppStrings.t('nav.yourSpace')),
            _NavItem(
              AppStrings.t('nav.myMusic'),
              Icons.library_music_outlined,
              3,
              activeIndex,
              onSelected,
            ),
            _NavItem(
              AppStrings.t('nav.localMusic'),
              Icons.download_done_outlined,
              4,
              activeIndex,
              onSelected,
            ),
            _NavItem(
              AppStrings.t('nav.recent'),
              Icons.history,
              5,
              activeIndex,
              onSelected,
            ),
            const Spacer(),
            const Divider(height: 28),
            Text(
              AppStrings.t('nav.localLibrary'),
              style: TextStyle(
                color: TimbreColors.muted,
                fontSize: 9,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              AppStrings.t('nav.libraryStatsFmt')
                  .replaceFirst('{f}', '${controller.favorites.length}')
                  .replaceFirst('{d}', '${controller.downloads.length}'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            _NavItem(
              AppStrings.t('nav.settings'),
              Icons.tune_outlined,
              6,
              activeIndex,
              onSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 2, 8, 20),
      child: Row(
        children: [
          const _Mark(),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'TimbreBox',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Georgia', fontSize: 21),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mark extends TimbreBrandMark {
  const _Mark() : super(size: 28);
}

class _Label extends StatelessWidget {
  const _Label(this.value);
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(9, 0, 9, 7),
    child: Text(
      value,
      style: TextStyle(
        color: TimbreColors.muted,
        fontSize: 9,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem(
    this.label,
    this.icon,
    this.index,
    this.active,
    this.onSelected,
  );

  final String label;
  final IconData icon;
  final int index;
  final int active;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = active == index;
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected
              ? TimbreColors.gold.withValues(alpha: .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelected(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? TimbreColors.gold : TimbreColors.muted,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? TimbreColors.ink : TimbreColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (selected)
                    Text('•', style: TextStyle(color: TimbreColors.gold)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
