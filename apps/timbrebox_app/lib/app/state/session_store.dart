import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../model/catalog_track.dart';
import 'atomic_file.dart';

/// Persists the last listening session (the queue, which track was current, and
/// its playback position in milliseconds) so "restore last session" can rebuild
/// it and resume where you left off. Stream URLs are never stored — only stable
/// track metadata and a position offset.
abstract interface class SessionStore {
  Future<void> save(List<CatalogTrack> queue, int currentIndex, {int positionMs});
  Future<RestoredSession?> load();
  Future<void> clear();
}

final class FileSessionStore implements SessionStore {
  static const _fileName = 'session.json';

  @override
  Future<void> save(
    List<CatalogTrack> queue,
    int currentIndex, {
    int positionMs = 0,
  }) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await writeFileAtomically(
      file,
      jsonEncode({
        'currentIndex': currentIndex,
        'positionMs': positionMs,
        'queue': [for (final track in queue) track.toJson()],
      }),
    );
  }

  @override
  Future<RestoredSession?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final list = data['queue'] as List? ?? const [];
      final queue = [
        for (final entry in list)
          CatalogTrack.fromJson(entry as Map<String, Object?>),
      ];
      if (queue.isEmpty) return null;
      return RestoredSession(
        queue: queue,
        currentIndex: (data['currentIndex'] as num?)?.toInt() ?? 0,
        positionMs: (data['positionMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }
}

class RestoredSession {
  const RestoredSession({
    required this.queue,
    required this.currentIndex,
    this.positionMs = 0,
  });

  final List<CatalogTrack> queue;
  final int currentIndex;
  final int positionMs;
}
