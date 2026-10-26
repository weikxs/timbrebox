import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
    // The short id keeps two different tracks with the same artist and title
    // (or the same song from two sources) from sharing one file.
    final base = '${_safeName('${track.artist} - ${track.title}')} '
        '[${_shortId(track.ref)}]';
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
      // Awaited so `finally` below runs after the rename, not during it.
      return await partial.rename(target.path);
    } finally {
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }

  static const _mimeExtensions = {
    'mp4': 'm4a',
    'm4a': 'm4a',
    'aac': 'aac',
    'webm': 'webm',
    'mpeg': 'mp3',
    'mp3': 'mp3',
    'flac': 'flac',
    'ogg': 'ogg',
    'opus': 'opus',
    'wav': 'wav',
  };

  static const _audioSuffixes = {
    'm4a', 'mp4', 'aac', 'webm', 'mp3', 'flac', 'ogg', 'oga', 'opus', 'wav',
  };

  /// The file extension from the stream's MIME type, else from a known audio
  /// suffix in the URL. Proxied streams have URLs like `/s/<token>`, so an unknown
  /// suffix falls back to `audio` rather than becoming the extension.
  String _extension(String? mime, Uri uri) {
    final type = mime?.toLowerCase() ?? '';
    for (final entry in _mimeExtensions.entries) {
      if (type.contains(entry.key)) return entry.value;
    }
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final suffix = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return _audioSuffixes.contains(suffix) ? suffix : 'audio';
  }

  String _shortId(MediaRef ref) =>
      sha256.convert(utf8.encode(ref.toString())).toString().substring(0, 8);

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ');
    final compact = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.isEmpty
        ? 'timbrebox-track'
        : compact.substring(0, compact.length.clamp(0, 120));
  }
}
