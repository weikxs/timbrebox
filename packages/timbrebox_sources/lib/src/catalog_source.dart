import 'package:timbrebox_core/timbrebox_core.dart';

import 'catalog_track.dart';

/// App-facing source adapter contract, independent from the registry.
abstract interface class CatalogSource implements MusicSource, StreamResolver {
  CatalogTrack toCatalogTrack(TrackSummary summary);
}

/// A source that resolves its search results from state it keeps in memory
/// (which a restart loses). Its tracks carry a [CatalogTrack.resolveHint];
/// handing the hint back lets it resolve a saved track without a search.
abstract interface class HintedCatalogSource {
  void rememberHint(String itemId, Map<String, Object?> hint);
}
