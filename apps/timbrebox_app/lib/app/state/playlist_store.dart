import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../model/playlist.dart';
import 'atomic_file.dart';

/// Persists user playlists (track metadata only) so they survive restarts.
abstract interface class PlaylistStore {
  Future<List<Playlist>> load();
  Future<void> save(List<Playlist> playlists);
}

final class FilePlaylistStore implements PlaylistStore {
  static const _fileName = 'playlists.json';

  @override
  Future<List<Playlist>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final list = jsonDecode(await file.readAsString()) as List? ?? const [];
      return [
        for (final entry in list) ?Playlist.fromJson(entry),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<Playlist> playlists) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await writeFileAtomically(
      file,
      jsonEncode([for (final playlist in playlists) playlist.toJson()]),
    );
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }
}
