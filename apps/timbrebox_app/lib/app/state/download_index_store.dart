import 'dart:convert';
import 'dart:io';

import 'package:timbrebox_core/timbrebox_core.dart';

import '../model/catalog_track.dart';
import 'download_paths.dart';
import '../design/app_strings.dart';
import 'atomic_file.dart';

/// One persisted local-music record. It holds only the metadata needed to
/// rebuild a [CatalogTrack] and the on-disk path — never a source URL, header,
/// token or cookie.
class DownloadedEntry {
  const DownloadedEntry({required this.track, required this.path});

  final CatalogTrack track;
  final String path;

  Map<String, Object?> toJson() => {
    'id': track.id,
    'title': track.title,
    'artist': track.artist,
    'sourceId': track.sourceId,
    'sourceName': track.sourceName,
    'durationMs': track.duration.inMilliseconds,
    'quality': track.quality,
    'album': track.album,
    'artworkUrl': track.artworkUrl,
    'path': path,
  };

  static DownloadedEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString();
    final title = value['title']?.toString();
    final sourceId = value['sourceId']?.toString();
    final path = value['path']?.toString();
    if (id == null || title == null || sourceId == null || path == null) {
      return null;
    }
    if (id.isEmpty || sourceId.isEmpty || path.isEmpty) return null;
    final durationMs = (value['durationMs'] as num?)?.round() ?? 0;
    return DownloadedEntry(
      track: CatalogTrack(
        id: id,
        title: title,
        artist: value['artist']?.toString() ?? '',
        sourceId: sourceId,
        sourceName: value['sourceName']?.toString() ?? sourceId,
        duration: Duration(milliseconds: durationMs),
        quality:
            value['quality']?.toString() ?? AppStrings.t('quality.localFile'),
        album: value['album']?.toString(),
        artworkUrl: value['artworkUrl']?.toString(),
      ),
      path: path,
    );
  }

  MediaRef get ref => track.ref;
}

/// Persists the local-music index so downloaded files survive a restart and
/// keep playing straight from disk without re-contacting any source.
abstract interface class DownloadIndexStore {
  Future<List<DownloadedEntry>> load();
  Future<void> save(List<DownloadedEntry> entries);
}

typedef IndexDirectoryProvider = Future<Directory> Function();

final class FileDownloadIndexStore implements DownloadIndexStore {
  FileDownloadIndexStore({IndexDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? resolveDownloadDirectory;

  final IndexDirectoryProvider _directoryProvider;

  static const _fileName = 'library-index.json';

  @override
  Future<List<DownloadedEntry>> load() async {
    final directory = await _directoryProvider();
    final file = await _indexFile();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final entries = <DownloadedEntry>[];
      for (final raw in decoded) {
        final entry = DownloadedEntry.fromJson(raw);
        // Only files directly inside the library are trusted: the index is a
        // plain file a user or another program can edit, and "clear
        // downloads" deletes whatever it lists.
        final path = entry == null ? null : _inside(directory, entry.path);
        // Drop records whose file was deleted outside the app so the library
        // never lists something that cannot play.
        if (path != null && await File(path).exists()) {
          entries.add(DownloadedEntry(track: entry!.track, path: path));
        }
      }
      return entries;
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  @override
  Future<void> save(List<DownloadedEntry> entries) async {
    final file = await _indexFile();
    await file.parent.create(recursive: true);
    final directory = await _directoryProvider();
    final payload = jsonEncode([
      for (final entry in entries)
        if (_inside(directory, entry.path) case final path?)
          DownloadedEntry(track: entry.track, path: _baseName(path)).toJson(),
    ]);
    await writeFileAtomically(file, payload);
  }

  /// The normalized path of [stored] if it names a file directly inside
  /// [directory] (a bare file name, or an absolute path from older indexes),
  /// otherwise null.
  static String? _inside(Directory directory, String stored) {
    final base = _normalized(directory.absolute.path);
    final candidate = _normalized(
      File(stored).isAbsolute
          ? stored
          : '$base${Platform.pathSeparator}$stored',
    );
    return File(candidate).parent.path == base ? candidate : null;
  }

  static String _normalized(String path) =>
      Uri.file(path).normalizePath().toFilePath();

  static String _baseName(String path) => File(path).uri.pathSegments.last;

  Future<File> _indexFile() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$_fileName');
  }
}
