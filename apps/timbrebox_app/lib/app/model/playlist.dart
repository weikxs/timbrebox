import 'catalog_track.dart';

/// A user-created playlist: a named, ordered list of tracks. Stores full track
/// metadata (never a source URL / token) so it renders after a restart.
class Playlist {
  const Playlist({required this.id, required this.name, this.tracks = const []});

  final String id;
  final String name;
  final List<CatalogTrack> tracks;

  Playlist copyWith({String? name, List<CatalogTrack>? tracks}) => Playlist(
    id: id,
    name: name ?? this.name,
    tracks: tracks ?? this.tracks,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tracks': [for (final track in tracks) track.toJson()],
  };

  static Playlist? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString();
    final name = value['name']?.toString();
    if (id == null || name == null || id.isEmpty) return null;
    final list = value['tracks'] as List? ?? const [];
    return Playlist(
      id: id,
      name: name,
      tracks: [
        for (final entry in list)
          if (entry is Map<String, Object?>) CatalogTrack.fromJson(entry),
      ],
    );
  }
}
