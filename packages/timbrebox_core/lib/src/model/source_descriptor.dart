enum SourceCapability { search, discovery, streaming, lyrics, download }

enum SourceAvailability { available, unavailable }

class SourceDescriptor {
  SourceDescriptor({
    required this.id,
    required this.name,
    required Iterable<SourceCapability> capabilities,
    this.availability = SourceAvailability.available,
    this.unavailableReason,
  }) : capabilities = Set.unmodifiable(capabilities) {
    if (!RegExp(r'^[a-z][a-z0-9_]{1,31}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Use lowercase source identifiers.');
    }
  }

  final String id;
  final String name;
  final Set<SourceCapability> capabilities;
  final SourceAvailability availability;
  final String? unavailableReason;

  bool supports(SourceCapability capability) =>
      capabilities.contains(capability);
}
