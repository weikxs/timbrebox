import '../model/search_models.dart';

/// Owns the ordered listening session without retaining stream URLs.
class PlaybackQueue {
  PlaybackQueue([Iterable<TrackSummary> tracks = const []])
    : _tracks = List.of(tracks);

  final List<TrackSummary> _tracks;
  int? _currentIndex;

  /// Where the playing item was when it was removed from the queue. The
  /// player keeps playing it, so the next step must land on the item that
  /// followed it (now at this index), not one further.
  int? _removedAt;

  List<TrackSummary> get tracks => List.unmodifiable(_tracks);
  TrackSummary? get current =>
      _currentIndex == null ? null : _tracks[_currentIndex!];
  int? get currentIndex => _currentIndex;
  bool get isEmpty => _tracks.isEmpty;

  void clear() {
    _tracks.clear();
    _currentIndex = null;
    _removedAt = null;
  }

  void replace(Iterable<TrackSummary> tracks, {int initialIndex = 0}) {
    _tracks
      ..clear()
      ..addAll(tracks);
    _removedAt = null;
    _currentIndex = _tracks.isEmpty
        ? null
        : initialIndex.clamp(0, _tracks.length - 1);
  }

  void add(TrackSummary track, {bool playNext = false}) {
    final removedAt = _removedAt;
    if (playNext && removedAt != null) {
      _tracks.insert(removedAt, track);
      return;
    }
    if (playNext && _currentIndex != null) {
      _tracks.insert(_currentIndex! + 1, track);
      return;
    }
    _tracks.add(track);
  }

  bool removeAt(int index) {
    if (index < 0 || index >= _tracks.length) return false;
    final currentIndex = _currentIndex;
    final removedAt = _removedAt;
    _tracks.removeAt(index);
    if (removedAt != null && index < removedAt) _removedAt = removedAt - 1;
    if (_tracks.isEmpty) {
      _currentIndex = null;
      _removedAt = null;
    } else if (currentIndex != null && index < currentIndex) {
      _currentIndex = currentIndex - 1;
    } else if (currentIndex != null && index == currentIndex) {
      _currentIndex = currentIndex.clamp(0, _tracks.length - 1);
      _removedAt = index;
    }
    return true;
  }

  /// Moves the track at [from] to index [to], keeping the currently-playing
  /// track selected wherever it ends up.
  void move(int from, int to) {
    if (from < 0 || from >= _tracks.length) return;
    to = to.clamp(0, _tracks.length - 1);
    if (from == to) return;
    _removedAt = null;
    final track = _tracks.removeAt(from);
    _tracks.insert(to, track);
    final currentIndex = _currentIndex;
    if (currentIndex == null) return;
    if (currentIndex == from) {
      _currentIndex = to;
      return;
    }
    var index = currentIndex;
    if (from < index) index -= 1; // an earlier track was pulled out
    if (to <= index) index += 1; // a track was inserted at/before current
    _currentIndex = index;
  }

  TrackSummary? select(int index) {
    if (index < 0 || index >= _tracks.length) return null;
    _currentIndex = index;
    _removedAt = null;
    return current;
  }

  TrackSummary? next({bool wrap = false}) => _move(1, wrap: wrap);
  TrackSummary? previous({bool wrap = false}) => _move(-1, wrap: wrap);

  TrackSummary? _move(int step, {required bool wrap}) {
    if (_tracks.isEmpty) return null;
    final removedAt = _removedAt;
    _removedAt = null;
    // After the playing item was removed, its neighbours sit at removedAt
    // (the following item) and removedAt - 1 (the preceding one).
    final nextIndex = removedAt != null
        ? (step > 0 ? removedAt : removedAt - 1)
        : (_currentIndex ?? 0) + step;
    if (nextIndex >= 0 && nextIndex < _tracks.length) {
      _currentIndex = nextIndex;
    } else if (wrap) {
      _currentIndex = step > 0 ? 0 : _tracks.length - 1;
    } else {
      return null;
    }
    return current;
  }
}
