import '../model/search_models.dart';

/// Owns the ordered listening session without retaining stream URLs.
class PlaybackQueue {
  PlaybackQueue([Iterable<TrackSummary> tracks = const []])
    : _tracks = List.of(tracks);

  final List<TrackSummary> _tracks;
  int? _currentIndex;

  List<TrackSummary> get tracks => List.unmodifiable(_tracks);
  TrackSummary? get current =>
      _currentIndex == null ? null : _tracks[_currentIndex!];
  bool get isEmpty => _tracks.isEmpty;

  void clear() {
    _tracks.clear();
    _currentIndex = null;
  }

  void replace(Iterable<TrackSummary> tracks, {int initialIndex = 0}) {
    _tracks
      ..clear()
      ..addAll(tracks);
    _currentIndex = _tracks.isEmpty
        ? null
        : initialIndex.clamp(0, _tracks.length - 1);
  }

  void add(TrackSummary track, {bool playNext = false}) {
    if (playNext && _currentIndex != null) {
      _tracks.insert(_currentIndex! + 1, track);
      return;
    }
    _tracks.add(track);
  }

  bool removeAt(int index) {
    if (index < 0 || index >= _tracks.length) return false;
    final currentIndex = _currentIndex;
    _tracks.removeAt(index);
    if (_tracks.isEmpty) {
      _currentIndex = null;
    } else if (currentIndex != null && index < currentIndex) {
      _currentIndex = currentIndex - 1;
    } else if (currentIndex != null && index == currentIndex) {
      _currentIndex = currentIndex.clamp(0, _tracks.length - 1);
    }
    return true;
  }

  /// Moves the track at [from] to index [to], keeping the currently-playing
  /// track selected wherever it ends up.
  void move(int from, int to) {
    if (from < 0 || from >= _tracks.length) return;
    to = to.clamp(0, _tracks.length - 1);
    if (from == to) return;
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
    return current;
  }

  TrackSummary? next({bool wrap = false}) => _move(1, wrap: wrap);
  TrackSummary? previous({bool wrap = false}) => _move(-1, wrap: wrap);

  TrackSummary? _move(int step, {required bool wrap}) {
    if (_tracks.isEmpty) return null;
    final currentIndex = _currentIndex ?? 0;
    final nextIndex = currentIndex + step;
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
