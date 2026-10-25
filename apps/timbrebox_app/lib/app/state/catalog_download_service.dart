import 'dart:io';

import 'package:timbrebox_core/timbrebox_core.dart';

import '../model/catalog_track.dart';
import 'download_paths.dart';
import '../design/app_strings.dart';

typedef DownloadDirectoryProvider = Future<Directory> Function();

/// Resolves and transfers one source stream into the platform app directory.
///
/// URLs and request headers are held only for this operation. A completed
/// download is played from its local path and never re-resolved remotely.
final class CatalogDownloadService {
  CatalogDownloadService({
    required this.resolver,
    DownloadDirectoryProvider? directoryProvider,
    this.maxBytes = 512 * 1024 * 1024,
  }) : _directoryProvider = directoryProvider ?? resolveDownloadDirectory;

  final StreamResolver resolver;
  final DownloadDirectoryProvider _directoryProvider;
  final int maxBytes;

  Future<File> download(
    CatalogTrack track, {
    CancellationToken? cancellation,
  }) async {
    final token = cancellation ?? CancellationToken();
    token.throwIfCancelled();
    final stream = await resolver.resolve(
      StreamRequest(
        ref: track.ref,
        quality: track.quality,
        cancellation: token,
      ),
    );
    token.throwIfCancelled();
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final base = _safeName('${track.artist} - ${track.title}');
    final extension = _extension(stream.mimeType, stream.uri);
    final target = File('${directory.path}/$base.$extension');

    // Only network streams are downloaded. A `file://` URI here could only
    // come from a plugin and would copy an arbitrary local file.
    if (stream.uri.scheme != 'https' && stream.uri.scheme != 'http') {
      throw StateError(AppStrings.t('download.errScheme'));
    }

    final partial = File('${target.path}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(stream.uri);
      stream.headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(AppStrings.t('download.errHttp').replaceFirst('{code}', '${response.statusCode}'));
      }
      final length = response.contentLength;
      if (length > maxBytes) throw StateError(AppStrings.t('download.errTooLarge'));
      var received = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response) {
          token.throwIfCancelled();
          received += chunk.length;
          if (received > maxBytes) throw StateError(AppStrings.t('download.errTooLarge'));
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (await target.exists()) await target.delete();
      return partial.rename(target.path);
    } finally {
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }

  String _extension(String? mime, Uri uri) {
    if (mime?.contains('mp4') ?? false) return 'm4a';
    if (mime?.contains('webm') ?? false) return 'webm';
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final suffix = name.split('.').last.toLowerCase();
    return suffix.length <= 4 && RegExp(r'^[a-z0-9]+$').hasMatch(suffix)
        ? suffix
        : 'audio';
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ');
    final compact = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.isEmpty
        ? 'timbrebox-track'
        : compact.substring(0, compact.length.clamp(0, 120));
  }
}
