import 'dart:io';

/// A resolved playback input kept in memory for the duration of a load.
///
/// Stable media references never belong here.  A resolver may provide a
/// short-lived URL and request headers, or a completed local file path.
sealed class AudioSourceSpec {
  const AudioSourceSpec({this.mimeType});

  final String? mimeType;

  static AudioSourceSpec remote(
    Uri uri, {
    Map<String, String> headers = const {},
    String? mimeType,
    bool allowInsecure = false,
  }) => RemoteAudioSource(
    uri,
    headers: headers,
    mimeType: mimeType,
    allowInsecure: allowInsecure,
  );

  static AudioSourceSpec localFile(String path, {String? mimeType}) =>
      LocalAudioSource(path, mimeType: mimeType);
}

final class RemoteAudioSource extends AudioSourceSpec {
  RemoteAudioSource(
    this.uri, {
    Map<String, String> headers = const {},
    super.mimeType,
    this.allowInsecure = false,
  }) : headers = Map.unmodifiable(headers) {
    if (uri.scheme != 'https' && !(allowInsecure && uri.scheme == 'http')) {
      throw ArgumentError.value(uri, 'uri', 'Remote audio must use HTTPS.');
    }
  }

  final Uri uri;
  final Map<String, String> headers;
  final bool allowInsecure;
}

final class LocalAudioSource extends AudioSourceSpec {
  LocalAudioSource(String path, {super.mimeType}) : path = _validate(path);

  final String path;

  static String _validate(String path) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Audio file path is empty.');
    }
    return path;
  }

  bool get exists => File(path).existsSync();
}
