class MediaExtractionException implements Exception {
  const MediaExtractionException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}
