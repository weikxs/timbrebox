import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../model/catalog_track.dart';

/// Persists the favorite tracks (full metadata only — never a source URL,
/// header, token or cookie) so the favorites list survives restarts.
abstract interface class FavoritesStore {
  Future<List<CatalogTrack>> load();
  Future<void> save(List<CatalogTrack> favorites);
}

final class FileFavoritesStore implements FavoritesStore {
  static const _fileName = 'favorites.json';

  @override
  Future<List<CatalogTrack>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final list = jsonDecode(await file.readAsString()) as List? ?? const [];
      return [
        for (final entry in list)
          CatalogTrack.fromJson(entry as Map<String, Object?>),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<CatalogTrack> favorites) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode([for (final track in favorites) track.toJson()]),
      flush: true,
    );
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }
}
