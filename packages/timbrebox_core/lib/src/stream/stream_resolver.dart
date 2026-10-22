import '../model/cancellation_token.dart';
import '../model/media_ref.dart';

/// Describes one request for a short-lived playable stream.
///
/// The request contains only a stable media reference. Providers resolve it
/// when playback or download starts; callers must not persist the result.
class StreamRequest {
  const StreamRequest({
    required this.ref,
    required this.quality,
    required this.cancellation,
  });

  final MediaRef ref;
  final String quality;
  final CancellationToken cancellation;
}

/// A provider result that is valid for the current operation only.
class ResolvedStream {
  ResolvedStream({
    required this.uri,
    Map<String, String> headers = const <String, String>{},
    this.mimeType,
    this.expiresAt,
  }) : headers = Map.unmodifiable(headers);

  final Uri uri;
  final Map<String, String> headers;
  final String? mimeType;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());
}

/// Resolves a stable media reference to an ephemeral stream.
abstract interface class StreamResolver {
  Future<ResolvedStream> resolve(StreamRequest request);
}
