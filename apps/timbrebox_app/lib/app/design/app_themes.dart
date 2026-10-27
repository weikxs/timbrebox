import 'package:flutter/material.dart';

import 'timbre_colors.dart';

/// A selectable theme. `palette == null` means "follow system", resolved at
/// build time from the OS brightness. A custom uploaded background image is a
/// separate skin that overrides the theme's background but keeps the dark
/// palette for legibility over the image.
class AppTheme {
  const AppTheme(this.id, this.nameKey, this.palette);

  final String id;

  /// AppStrings key for the display name (resolved at build time for i18n).
  final String nameKey;
  final TimbrePalette? palette; // null => system
}

const kDefaultThemeId = 'dark';

/// The four standard themes: light, dark, follow-system, and pure black.
const kAppThemes = <AppTheme>[
  AppTheme('light', 'theme.light', kLightPalette),
  AppTheme('dark', 'theme.dark', kDarkPalette),
  AppTheme('system', 'theme.system', null),
  AppTheme('black', 'theme.black', kBlackPalette),
];

AppTheme appThemeById(String id) => kAppThemes.firstWhere(
  (theme) => theme.id == id,
  orElse: () => kAppThemes[1],
);

/// Resolves the concrete palette for [id], mapping "system" to light/dark by
/// the current OS [platformBrightness].
TimbrePalette resolvePalette(String id, Brightness platformBrightness) {
  final palette = appThemeById(id).palette;
  if (palette != null) return palette;
  return platformBrightness == Brightness.light ? kLightPalette : kDarkPalette;
}
