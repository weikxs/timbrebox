import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import 'audio_source.dart';

/// Resolves a stable candidate into an ephemeral player input.
///
/// Source adapters should implement this boundary.  The default resolver is
/// intentionally conservative and only handles already-resolved HTTPS URLs
/// and local file URIs, which keeps the player independent from network code.
abstract interface class PlayerSourceResolver {
  Future<AudioSourceSpec> resolve(StreamCandidate candidate);
}

final class DefaultPlayerSourceResolver implements PlayerSourceResolver {
  const DefaultPlayerSourceResolver();

  @override
  Future<AudioSourceSpec> resolve(StreamCandidate candidate) async {
    final input = candidate.id.trim();
    if (input.startsWith('file://')) {
      final uri = Uri.tryParse(input);
      if (uri == null || uri.scheme != 'file') {
        throw StateError(AppStrings.t('stream.err.badLocalPath'));
      }
      return AudioSourceSpec.localFile(uri.toFilePath());
    }
    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme != 'https') {
      throw StateError(AppStrings.t('stream.err.noSecureStream'));
    }
    return AudioSourceSpec.remote(
      uri,
      allowInsecure: candidate.ref.sourceId == 'radio_browser',
    );
  }
}
