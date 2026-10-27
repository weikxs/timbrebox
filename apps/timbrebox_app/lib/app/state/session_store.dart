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
  /// Saves the queue and the current track (and the position with them).
  Future<void> save(
    List<CatalogTrack> queue,
    int currentIndex, {
    int positionMs,
  });

  /// Saves only the position in the current track; the queue is unchanged
  /// since the last [save].
  Future<void> savePosition(int positionMs);

  Future<RestoredSession?> load();
  Future<void> clear();
}

/// The queue lives in `session.json` and is rewritten only when it changes;
/// the position, which moves every few seconds of playback, has its own tiny
/// `session-position.json`. Files from versions that kept the position in
/// `session.json` still load.
final class FileSessionStore implements SessionStore {
  FileSessionStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _queueFileName = 'session.json';
  static const _positionFileName = 'session-position.json';

  @override
  Future<void> save(
    List<CatalogTrack> queue,
    int currentIndex, {
    int positionMs = 0,
  }) async {
    final file = await _file(_queueFileName);
    await file.parent.create(recursive: true);
    await writeFileAtomically(
      file,
      jsonEncode({
        'currentIndex': currentIndex,
        'queue': [for (final track in queue) track.toJson()],
      }),
    );
    await savePosition(positionMs);
  }

  @override
  Future<void> savePosition(int positionMs) async {
    final file = await _file(_positionFileName);
    await file.parent.create(recursive: true);
    await writeFileAtomically(file, jsonEncode({'positionMs': positionMs}));
  }

  @override
  Future<RestoredSession?> load() async {
    final file = await _file(_queueFileName);
    if (!await file.exists()) return null;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final list = data['queue'] as List? ?? const [];
      final queue = [
        for (final entry in list)
          CatalogTrack.fromJson(entry as Map<String, Object?>),
      ];
      if (queue.isEmpty) return null;
      return RestoredSession(
        queue: queue,
        currentIndex: (data['currentIndex'] as num?)?.toInt() ?? 0,
        positionMs:
            await _savedPosition() ??
            (data['positionMs'] as num?)?.toInt() ??
            0,
      );
    } catch (_) {
      return null;
    }
  }

  /// The position file's value, or null when there is none (an older
  /// session) or it cannot be read.
  Future<int?> _savedPosition() async {
    final file = await _file(_positionFileName);
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      return data is Map ? (data['positionMs'] as num?)?.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    for (final name in const [_queueFileName, _positionFileName]) {
      final file = await _file(name);
      if (await file.exists()) await file.delete();
    }
  }

  Future<File> _file(String name) async {
    final dir = await _directory();
    return File('${dir.path}/$name');
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
