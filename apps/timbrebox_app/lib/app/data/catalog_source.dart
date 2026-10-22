import 'package:timbrebox_core/timbrebox_core.dart';

import '../model/catalog_track.dart';

/// App-facing source adapter contract, independent from the registry.
abstract interface class CatalogSource implements MusicSource, StreamResolver {
  CatalogTrack toCatalogTrack(TrackSummary summary);
}
