import 'package:flutter/material.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';

class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.sourceId,
    required this.sourceName,
    required this.duration,
    required this.quality,
    this.album,
    this.artworkUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String sourceId;
  final String sourceName;
  final Duration duration;
  final String quality;
  final String? album;

  /// Public cover-art URL when the source provides one (e.g. Audius). Null for
  /// sources without artwork; the UI then shows a derived placeholder.
  final String? artworkUrl;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'sourceId': sourceId,
    'sourceName': sourceName,
    'durationMs': duration.inMilliseconds,
    'quality': quality,
    'album': album,
    'artworkUrl': artworkUrl,
  };

  factory CatalogTrack.fromJson(Map<String, Object?> json) => CatalogTrack(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    sourceId: json['sourceId'] as String,
    sourceName: json['sourceName'] as String? ?? '',
    duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
    quality: json['quality'] as String? ?? '',
    album: json['album'] as String?,
    artworkUrl: json['artworkUrl'] as String?,
  );

  MediaRef get ref => MediaRef(sourceId: sourceId, itemId: id);
  TrackSummary get summary =>
      TrackSummary(ref: ref, title: title, artist: artist, duration: duration);
  StreamCandidate get candidate =>
      StreamCandidate(ref: ref, id: ref.toString(), label: quality);

  bool get hasKnownDuration => duration > Duration.zero;

  String get durationLabel {
    if (!hasKnownDuration) return '--:--';
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

enum QualityPreference { standard, high, lossless, hires }

enum SettingsSection { general, appearance, sources, plugins, downloads, shortcuts }

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
