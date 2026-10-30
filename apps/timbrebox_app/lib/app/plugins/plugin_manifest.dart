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
    this.variables = const [],
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

  /// The settings the plugin asks the user for (its `userVariables`).
  final List<PluginVariable> variables;

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
        variables: variables,
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
    'variables': [for (final variable in variables) variable.toJson()],
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
    variables: PluginVariable.listFrom(json['variables']),
  );
}

/// One setting a plugin asks the user for: a server address, an account
/// name, a password. The value the user enters reaches only that plugin.
class PluginVariable {
  const PluginVariable({required this.key, required this.name, this.hint});

  static const maxCount = 20;
  static final _validKey = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');
  static final _secretWords = RegExp(
    'pass|token|secret|cookie|key|密码|令牌|密钥',
    caseSensitive: false,
  );

  /// The name the plugin reads the value by.
  final String key;

  /// What the setting is called in the form.
  final String name;

  /// An example or explanation shown in the empty field.
  final String? hint;

  /// Whether the value should be hidden while typed (a password, a token).
  bool get isSecret =>
      _secretWords.hasMatch(key) || _secretWords.hasMatch(name);

  /// The well-formed entries of a declared list, at most [maxCount]; an
  /// entry without a usable key is left out.
  static List<PluginVariable> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final variables = <PluginVariable>[];
    final keys = <String>{};
    for (final entry in raw) {
      if (entry is! Map) continue;
      final key = entry['key'];
      if (key is! String || !_validKey.hasMatch(key) || !keys.add(key)) {
        continue;
      }
      final name = _text(entry['name'], 60);
      variables.add(
        PluginVariable(
          key: key,
          name: name ?? key,
          hint: _text(entry['hint'], 200),
        ),
      );
      if (variables.length == maxCount) break;
    }
    return List.unmodifiable(variables);
  }

  static String? _text(Object? value, int maxLength) {
    if (value is! String) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    return text.length > maxLength ? text.substring(0, maxLength) : text;
  }

  Map<String, Object?> toJson() => {'key': key, 'name': name, 'hint': hint};
}
