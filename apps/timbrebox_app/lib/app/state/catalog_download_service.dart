import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import '../model/catalog_track.dart';
import '../net/egress_policy.dart';
import 'download_paths.dart';

typedef DownloadDirectoryProvider = Future<Directory> Function();

/// Bytes received so far, and the total when the server announced it.
typedef DownloadProgress = void Function(int received, int? total);

/// Resolves and transfers one source stream into the platform app directory.
///
/// URLs and request headers are held only for this operation. A completed
/// download is played from its local path and never re-resolved remotely.
final class CatalogDownloadService {
  CatalogDownloadService({
    required this.resolver,
    DownloadDirectoryProvider? directoryProvider,
    this.maxBytes = 512 * 1024 * 1024,
    this.policy = const EgressPolicy(),
    this.idleTimeout = const Duration(seconds: 30),
  }) : _directoryProvider = directoryProvider ?? resolveDownloadDirectory;

  final StreamResolver resolver;
  final DownloadDirectoryProvider _directoryProvider;
  final int maxBytes;

  /// Stream URLs may come from a plugin: every connection and redirect hop
  /// must reach a public host. The loopback relay is the exception — it
  /// applies the same policy to its own upstream hops.
  final EgressPolicy policy;

  /// How long the body may stall before the download gives up.
  final Duration idleTimeout;

  /// How long the server may take to answer with headers.
  static const _responseTimeout = Duration(seconds: 20);

  /// How often a running transfer checks whether it was cancelled.
  static const _cancelPoll = Duration(milliseconds: 100);

  /// When this service was created; partial files older than that were left
  /// by an earlier run.
  final _startedAt = DateTime.now();

  Future<File> download(
    CatalogTrack track, {
    CancellationToken? cancellation,
    DownloadProgress? onProgress,
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
    // Only network streams are downloaded. A `file://` URI here could only
    // come from a plugin and would copy an arbitrary local file.
    if (stream.uri.scheme != 'https' && stream.uri.scheme != 'http') {
      throw StateError(AppStrings.t('download.errScheme'));
    }
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    // The short id keeps two different tracks with the same artist and title
    // (or the same song from two sources) from sharing one file.
    final base = '${_safeName('${track.artist} - ${track.title}')} '
        '[${_shortId(track.ref)}]';
    final extension = _extension(stream.mimeType, stream.uri);
    final target = File('${directory.path}/$base.$extension');
    final partial = File('${target.path}$partSuffix');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    if (!_isLoopback(stream.uri)) policy.attach(client);
    // Cancelling closes the client, which ends a transfer waiting on a
    // stalled connection at once.
    final watcher = Timer.periodic(_cancelPoll, (_) {
      if (token.isCancelled) client.close(force: true);
    });
    try {
      await _transfer(client, stream, partial, token, onProgress);
      if (await target.exists()) await target.delete();
      // Awaited so `finally` below runs after the rename, not during it.
      return await partial.rename(target.path);
    } catch (_) {
      if (token.isCancelled) throw const OperationCancelled();
      rethrow;
    } finally {
      watcher.cancel();
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<void> _transfer(
    HttpClient client,
    ResolvedStream stream,
    File partial,
    CancellationToken token,
    DownloadProgress? onProgress,
  ) async {
    final request = await client.getUrl(stream.uri);
    stream.headers.forEach(request.headers.set);
    final response = await request.close().timeout(_responseTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        AppStrings.t(
          'download.errHttp',
        ).replaceFirst('{code}', '${response.statusCode}'),
      );
    }
    final length = response.contentLength;
    if (length > maxBytes) {
      throw StateError(AppStrings.t('download.errTooLarge'));
    }
    final total = length > 0 ? length : null;
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in response.timeout(idleTimeout)) {
        token.throwIfCancelled();
        received += chunk.length;
        if (received > maxBytes) {
          throw StateError(AppStrings.t('download.errTooLarge'));
        }
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
  }

  /// The suffix of a file still being written.
  static const partSuffix = '.part';

  /// Deletes partial files an earlier run left behind (it quit or crashed
  /// mid-download). Ones this run is writing are newer and stay.
  Future<void> removeStaleParts() async {
    try {
      final directory = await _directoryProvider();
      if (!await directory.exists()) return;
      await for (final entry in directory.list()) {
        if (entry is! File || !entry.path.endsWith(partSuffix)) continue;
        if ((await entry.lastModified()).isBefore(_startedAt)) {
          await entry.delete();
        }
      }
    } on FileSystemException {
      // Best effort: a locked or vanished file is retried next launch.
    }
  }

  static bool _isLoopback(Uri uri) =>
      uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1';

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

/// What to tell the user about a failed download. Messages written for the
/// user pass through; anything else gets a fixed text, so no exception text
/// (which may carry a local path) reaches the screen.
String friendlyDownloadError(Object error) => switch (error) {
  SourceException(:final message) => message,
  StateError(:final message) => message,
  EgressDeniedException(:final message) => message,
  TimeoutException() => AppStrings.t('download.errStalled'),
  FileSystemException() => AppStrings.t('download.errDisk'),
  SocketException() || HttpException() || TlsException() =>
    AppStrings.t('download.errNetwork'),
  _ => AppStrings.t('download.failed'),
};
