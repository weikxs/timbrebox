import '../model/catalog_track.dart';

/// Every track the controller has seen, by media reference.
///
/// The queue only holds track summaries and looks the full track up here,
/// so whatever the queue, favorites, downloads, the current track or the
/// results on screen refer to ([pinned]) is always kept. Of the rest (older
/// search results and charts), only the [spare] most recently seen stay.
final class KnownTracks {
  KnownTracks({required Iterable<String> Function() pinned, this.spare = 400})
    // ignore: prefer_initializing_formals
    : _pinned = pinned;

  final Iterable<String> Function() _pinned;

  /// How many unpinned tracks are kept.
  final int spare;

  /// Insertion-ordered: the last key is the most recently seen.
  final _tracks = <String, CatalogTrack>{};
  var _pruneAt = 0;

  int get length => _tracks.length;

  CatalogTrack? operator [](String key) => _tracks[key];

  void operator []=(String key, CatalogTrack track) {
    _tracks.remove(key);
    _tracks[key] = track;
    // Pruning walks everything, so it runs only once enough has piled up.
    if (_tracks.length > _pruneAt + spare) _prune();
  }

  void _prune() {
    final pinned = _pinned().toSet();
    var spareLeft = spare;
    for (final key in _tracks.keys.toList().reversed) {
      if (pinned.contains(key)) continue;
      if (spareLeft > 0) {
        spareLeft--;
      } else {
        _tracks.remove(key);
      }
    }
    _pruneAt = _tracks.length;
  }
}
