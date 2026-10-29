import 'package:timbrebox_core/timbrebox_core.dart';

import 'catalog_track.dart';

class CatalogSearchBatch {
  const CatalogSearchBatch({required this.query, required this.groups});

  final String query;
  final List<CatalogSearchGroup> groups;

  bool get hasResults => groups.any((group) => group.tracks.isNotEmpty);
  bool get hasFailures => groups.any((group) => group.failure != null);

  CatalogSearchGroup? groupFor(String sourceId) {
    for (final group in groups) {
      if (group.sourceId == sourceId) return group;
    }
    return null;
  }

  List<CatalogTrack> get tracks => [
    for (final group in groups) ...group.tracks,
  ];
}

class CatalogSearchGroup {
  const CatalogSearchGroup({
    required this.sourceId,
    required this.sourceName,
    required this.status,
    required this.tracks,
    this.failure,
  });

  final String sourceId;
  final String sourceName;
  final SourceSearchStatus status;
  final List<CatalogTrack> tracks;
  final SourceFailure? failure;

  bool get isEmpty => tracks.isEmpty && failure == null;
}
