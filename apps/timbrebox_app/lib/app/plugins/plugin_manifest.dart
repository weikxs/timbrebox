/// Metadata describing one installed plugin. Persisted alongside its `.js`.
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.platform,
    required this.version,
    this.author,
    this.srcUrl,
    this.sha256,
    this.enabled = true,
    this.functions,
  });

  /// Stable source id (valid `SourceDescriptor` id: lowercase, `plugin_…`).
  final String id;

  /// The plugin's own source name (`module.exports.platform`).
  final String platform;
  final String version;
  final String? author;
  final String? srcUrl;

  /// SHA-256 of the stored `.js`, used to detect updates from `srcUrl`.
  final String? sha256;
  final bool enabled;

  /// The plugin functions TimbreBox uses that the script exports, recorded
  /// at install so the source's capabilities are known without starting its
  /// JS engine. Null for plugins installed before this was recorded.
  final List<String>? functions;

  /// Derives a valid, stable `SourceDescriptor` id from the plugin platform.
  /// Source ids must match `^[a-z][a-z0-9_]{1,31}$`.
  static String idFor(String platform) {
    final slug = platform.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '_');
    final id = 'plugin_$slug';
    return id.length > 32 ? id.substring(0, 32) : id;
  }

  PluginManifest copyWith({bool? enabled, List<String>? functions}) =>
      PluginManifest(
        id: id,
        platform: platform,
        version: version,
        author: author,
        srcUrl: srcUrl,
        sha256: sha256,
        enabled: enabled ?? this.enabled,
        functions: functions ?? this.functions,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'platform': platform,
    'version': version,
    'author': author,
    'srcUrl': srcUrl,
    'sha256': sha256,
    'enabled': enabled,
    'functions': functions,
  };

  factory PluginManifest.fromJson(Map<String, Object?> json) => PluginManifest(
    id: json['id'] as String,
    platform: json['platform'] as String? ?? json['id'] as String,
    version: json['version'] as String? ?? '0.0.0',
    author: json['author'] as String?,
    srcUrl: json['srcUrl'] as String?,
    sha256: json['sha256'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    functions: (json['functions'] as List?)?.whereType<String>().toList(),
  );
}
