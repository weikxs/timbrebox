class MediaRef {
  const MediaRef({required this.sourceId, required this.itemId})
    : assert(sourceId != ''),
      assert(itemId != '');

  final String sourceId;
  final String itemId;

  factory MediaRef.parse(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'tb' ||
        uri.host.isEmpty ||
        uri.pathSegments.length != 1) {
      throw FormatException('Invalid media reference: $value');
    }
    return MediaRef(sourceId: uri.host, itemId: uri.pathSegments.single);
  }

  @override
  String toString() =>
      Uri(scheme: 'tb', host: sourceId, pathSegments: [itemId]).toString();

  @override
  bool operator ==(Object other) {
    return other is MediaRef &&
        other.sourceId == sourceId &&
        other.itemId == itemId;
  }

  @override
  int get hashCode => Object.hash(sourceId, itemId);
}
