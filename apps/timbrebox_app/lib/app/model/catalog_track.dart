import 'package:flutter/material.dart';

import '../design/app_strings.dart';

// CatalogTrack lives in the shared timbrebox_sources package; the app's own
// preference enums and their labels stay here.
export 'package:timbrebox_sources/timbrebox_sources.dart' show CatalogTrack;

enum QualityPreference { standard, high, lossless, hires }

enum SettingsSection {
  general,
  appearance,
  sources,
  plugins,
  downloads,
  shortcuts,
}

enum PlaybackLoop { queue, track, off, shuffle }

extension QualityPreferenceLabel on QualityPreference {
  String get label => AppStrings.t('quality.$name');
}

extension SettingsSectionLabel on SettingsSection {
  String get label => AppStrings.t('settings.$name');
}

extension PlaybackLoopLabel on PlaybackLoop {
  String get label => AppStrings.t('loop.$name');

  IconData get icon => switch (this) {
    PlaybackLoop.queue => Icons.repeat_rounded,
    PlaybackLoop.track => Icons.repeat_one_rounded,
    PlaybackLoop.off => Icons.format_list_numbered_rounded,
    PlaybackLoop.shuffle => Icons.shuffle_rounded,
  };
}
