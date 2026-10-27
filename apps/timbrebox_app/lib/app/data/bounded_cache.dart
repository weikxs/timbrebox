/// A map that keeps at most [capacity] entries, dropping the least recently
/// used one (read or written) when a new one would exceed it.
///
/// Sources keep what a search returned so a result can be resolved, its
/// artwork shown, or its lyric fetched. Bounded, a long session does not
/// keep every result it ever saw; a saved track whose entry was dropped
/// resolves again from its hint (see `CatalogTrack.resolveHint`).
final class BoundedCache<K, V> {
  BoundedCache({this.capacity = defaultCapacity}) : assert(capacity > 0);

  /// Several pages of results from every source.
  static const defaultCapacity = 512;

  final int capacity;

  /// Insertion-ordered: the first key is the least recently used.
  final _entries = <K, V>{};

  int get length => _entries.length;

  bool containsKey(K key) => _entries.containsKey(key);

  V? operator [](K key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void operator []=(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  V putIfAbsent(K key, V Function() ifAbsent) {
    final existing = this[key];
    if (existing != null) return existing;
    final value = ifAbsent();
    this[key] = value;
    return value;
  }

  void clear() => _entries.clear();
}
