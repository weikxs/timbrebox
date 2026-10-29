import 'package:timbrebox_core/timbrebox_core.dart';

import 'package:timbrebox_playback/timbrebox_playback.dart';
import 'player_source_resolver.dart';

/// Bridges the platform-neutral resolver to the native audio backend.
///
/// The bridge creates an AudioSourceSpec only for the active load operation;
/// stable media references remain in the catalog and library models. A source
/// may resolve to a local `file://` URI (a downloaded track); everything else
/// is a remote URL.
final class CatalogPlayerSourceResolver implements PlayerSourceResolver {
  CatalogPlayerSourceResolver(this._resolver);

  final StreamResolver _resolver;

  @override
  Future<AudioSourceSpec> resolve(
    StreamCandidate candidate, {
    CancellationToken? cancellation,
  }) async {
    final local = Uri.tryParse(candidate.id);
    if (local?.scheme == 'file') {
      return AudioSourceSpec.localFile(local!.toFilePath());
    }
    final stream = await _resolver.resolve(
      StreamRequest(
        ref: candidate.ref,
        quality: candidate.label,
        cancellation: cancellation ?? CancellationToken(),
      ),
    );
    if (stream.uri.scheme == 'file') {
      return AudioSourceSpec.localFile(
        stream.uri.toFilePath(),
        mimeType: stream.mimeType,
      );
    }
    return AudioSourceSpec.remote(
      stream.uri,
      headers: stream.headers,
      mimeType: stream.mimeType,
      // Loopback (the header proxy for plugin streams) and radio streams may be
      // plain http; loopback carries no MITM risk, radio has no https option.
      allowInsecure:
          _isLoopback(stream.uri) || candidate.ref.sourceId == 'radio_browser',
    );
  }

  static bool _isLoopback(Uri uri) =>
      uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1';
}
