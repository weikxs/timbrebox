import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:timbrebox_sources/timbrebox_sources.dart';
import '../design/app_strings.dart';
import '../native/libc.dart';
import '../state/atomic_file.dart';
import '../state/private_file.dart';
import 'plugin_catalog_source.dart';
import 'plugin_environment.dart';
import 'plugin_http.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

/// Installs, persists, and loads plugins.
///
/// Each plugin lives under `<appSupport>/plugins/<id>/` as `plugin.js` +
/// `manifest.json`. Installing fetches the raw `.js` from a GitHub URL, runs it
/// once to read its metadata, then stores it. Loading rebuilds a
/// [PluginCatalogSource] per stored plugin whose JS engine starts on first use.
///
/// A plugin is stored whole or not at all: the new version is written to
/// `<id>.staging/`, the installed one is moved to `<id>.previous/`, and the
/// staging directory takes its place. A launch after a crash in between
/// finishes or undoes that move before loading.
final class PluginRepository {
  PluginRepository({
    this.policy = const EgressPolicy(),
    Future<Directory> Function()? pluginsDirectory,
    PluginRuntime Function(PluginEnvironment environment, Set<String> lanHosts)?
    createRuntime,
    @visibleForTesting Future<String> Function(Uri uri)? fetch,
    this.idleTimeout = PluginCatalogSource.defaultIdleTimeout,
  }) : _createRuntime =
           createRuntime ??
           ((environment, lanHosts) => PluginRuntime(
             environment: environment,
             http: PluginHttpClient(policy: policy.allowingLanHosts(lanHosts)),
           )),
       // ignore: prefer_initializing_formals
       _fetchOverride = fetch,
       // ignore: prefer_initializing_formals
       _pluginsDirectory = pluginsDirectory,
       streamProxy = StreamHeaderProxy(policy: policy);

  /// Plugin code is fetched over https from public hosts only, on every
  /// redirect hop too: a plain-http or LAN source could hand us any script.
  /// A plugin's requests and stream URLs are held to the same public-hosts
  /// rule, except for the LAN servers the user entered in its settings.
  final EgressPolicy policy;

  /// The loopback proxy every plugin source relays its streams through. It
  /// belongs to the repository, not to a source, so updating or removing a
  /// plugin does not cut off the track that is playing from it.
  final StreamHeaderProxy streamProxy;

  /// Closes the shared stream proxy (the app is shutting down).
  Future<void> dispose() => streamProxy.dispose();

  /// How long a plugin's engine may sit unused before it is shut down.
  final Duration idleTimeout;

  /// Where plugins are stored; defaults to `<appSupport>/plugins`.
  final Future<Directory> Function()? _pluginsDirectory;

  /// Starts an engine that tells the plugin about [PluginEnvironment] and may
  /// reach the LAN servers in the set (see [EgressPolicy.allowingLanHosts]).
  final PluginRuntime Function(
    PluginEnvironment environment,
    Set<String> lanHosts,
  )
  _createRuntime;

  /// Replaces the download in tests; the https rule still applies.
  final Future<String> Function(Uri uri)? _fetchOverride;

  static const _maxBytes = 6 * 1024 * 1024;
  static const _variablesFile = 'variables.json';
  static const _maxValueLength = 2000;
  static const _staging = '.staging';
  static const _previous = '.previous';

  /// Installs from [rawUrl], which may be a single plugin `.js` OR a
  /// subscription JSON (`{desc, plugins:[{name,url,version}]}`) — returns every
  /// installed source. Throws [PluginInstallException] if nothing installs.
  Future<List<PluginCatalogSource>> installFromUrl(String rawUrl) async {
    final uri = _normalize(rawUrl);
    final content = await _fetch(uri);
    final urls = _subscriptionUrls(content);
    if (urls == null) {
      // Not a subscription — treat the content as a single plugin script.
      return [await installSource(content, uri)];
    }
    if (urls.isEmpty) {
      throw PluginInstallException(
        AppStrings.t('plugin.err.emptySubscription'),
      );
    }
    final installed = <PluginCatalogSource>[];
    final errors = <String>[];
    for (final pluginUrl in urls) {
      try {
        final source = await _fetch(_normalize(pluginUrl));
        installed.add(await installSource(source, _normalize(pluginUrl)));
      } catch (error) {
        errors.add('$error');
      }
    }
    if (installed.isEmpty) {
      throw PluginInstallException(
        AppStrings.t(
          'plugin.err.subscriptionAllFailed',
        ).replaceFirst('{e}', errors.take(2).join('；')),
      );
    }
    return installed;
  }

  /// Re-fetches a plugin from its `srcUrl` and reinstalls only when the content
  /// changed (SHA differs). Returns the fresh source, or null if up to date.
  /// The new version replaces the installed plugin even when it names itself
  /// differently, and keeps whether it was switched on; one that does not
  /// load leaves the installed version untouched.
  Future<PluginCatalogSource?> update(PluginManifest manifest) async {
    final src = manifest.srcUrl;
    if (src == null || src.isEmpty) return null;
    final content = await _fetch(_normalize(src));
    if (sha256.convert(utf8.encode(content)).toString() == manifest.sha256) {
      return null; // Unchanged.
    }
    final installed = await _storedManifest(manifest.id) ?? manifest;
    return _install(
      content,
      _normalize(src),
      id: installed.id,
      enabled: installed.enabled,
    );
  }

  /// Validates a plugin [source], stores it, and returns its catalog source.
  /// The engine that read the metadata is released; like a stored plugin,
  /// the source starts a fresh one on first use.
  @visibleForTesting
  Future<PluginCatalogSource> installSource(String source, Uri origin) =>
      _install(source, origin);

  /// Installs [source] under [id] (by default the id its platform name
  /// gives).
  Future<PluginCatalogSource> _install(
    String source,
    Uri origin, {
    String? id,
    bool enabled = true,
  }) async {
    final runtime = _createRuntime(PluginEnvironment.current(), const {});
    try {
      await runtime.load(source);
    } catch (error) {
      runtime.dispose();
      throw PluginInstallException(
        AppStrings.t('plugin.err.scriptLoad').replaceFirst('{e}', '$error'),
      );
    }
    final platform = runtime.meta('platform');
    if (platform == null || platform.isEmpty) {
      runtime.dispose();
      throw PluginInstallException(AppStrings.t('plugin.err.missingPlatform'));
    }
    if (!runtime.hasFunction('search')) {
      runtime.dispose();
      throw PluginInstallException(AppStrings.t('plugin.err.missingSearch'));
    }
    final manifest = PluginManifest(
      id: id ?? PluginManifest.idFor(platform),
      platform: platform,
      version: runtime.meta('version') ?? '0.0.0',
      author: runtime.meta('author'),
      srcUrl: runtime.meta('srcUrl') ?? origin.toString(),
      sha256: sha256.convert(utf8.encode(source)).toString(),
      enabled: enabled,
      functions: PluginCatalogSource.exportedFunctions(runtime).toList(),
      variables: PluginVariable.listFrom(runtime.declaredVariables()),
    );
    runtime.dispose();
    final directory = await _store(
      manifest,
      source,
      keepFiles: await _isSameSource(manifest.id, origin),
    );
    return _lazySource(manifest, File('${directory.path}/plugin.js'));
  }

  /// Whether the plugin installed as [id] came from [origin]. Only then does
  /// a new script take over the files stored beside it (the user's settings):
  /// another plugin that merely names itself the same must not get them.
  Future<bool> _isSameSource(String id, Uri origin) async {
    final installed = (await _storedManifest(id))?.srcUrl;
    return installed != null && _normalize(installed) == origin;
  }

  PluginCatalogSource _lazySource(PluginManifest manifest, File script) =>
      PluginCatalogSource.lazy(
        manifest: manifest,
        functions: (manifest.functions ?? const []).toSet(),
        loadRuntime: () async {
          final settings = await _settingsOf(manifest);
          return _startRuntime(
            await script.readAsString(),
            userVariables: settings.values,
            lanHosts: settings.lanHosts,
          );
        },
        proxy: streamProxy,
        policy: policy,
        lanHosts: () async => (await _settingsOf(manifest)).lanHosts,
        idleTimeout: idleTimeout,
      );

  /// Returns the plugin URLs in a subscription JSON, or null if [content] is not
  /// a subscription (i.e. it's a plain `.js` script).
  List<String>? _subscriptionUrls(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return null; // Not JSON → a plugin script.
    }
    if (decoded is! Map || decoded['plugins'] is! List) return null;
    return [
      for (final entry in decoded['plugins'] as List)
        if (entry is Map && entry['url'] is String) entry['url'] as String,
    ];
  }

  final List<String> _skipped = [];

  /// The stored plugins (directory names) the last [loadInstalled] could not
  /// read, so the user can be told instead of the plugin silently vanishing.
  List<String> get skippedAtLoad => List.unmodifiable(_skipped);

  /// Rebuilds live sources for every stored plugin. One that fails to load is
  /// skipped and listed in [skippedAtLoad].
  Future<List<PluginCatalogSource>> loadInstalled() async {
    _skipped.clear();
    final directory = await _pluginsDir();
    if (!await directory.exists()) return const [];
    await _finishInterruptedStores(directory);
    final sources = <PluginCatalogSource>[];
    for (final entry in await directory.list().toList()) {
      if (entry is! Directory || _nameOf(entry).contains('.')) continue;
      final source = await _loadOne(entry);
      if (source != null) {
        sources.add(source);
      } else {
        _skipped.add(_nameOf(entry));
      }
    }
    _skipped.sort();
    return sources;
  }

  Future<void> remove(String id) async {
    final dir = Directory('${(await _pluginsDir()).path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Undoes a store a crash cut short: an installed version moved aside is
  /// put back when its replacement never moved in, and leftovers go.
  Future<void> _finishInterruptedStores(Directory directory) async {
    for (final entry in await directory.list().toList()) {
      if (entry is! Directory) continue;
      final name = _nameOf(entry);
      if (name.endsWith(_staging)) {
        await entry.delete(recursive: true);
      } else if (name.endsWith(_previous)) {
        final id = name.substring(0, name.length - _previous.length);
        final installed = Directory('${directory.path}/$id');
        if (await installed.exists()) {
          await entry.delete(recursive: true);
        } else {
          await entry.rename(installed.path);
        }
      }
    }
  }

  static String _nameOf(FileSystemEntity entry) =>
      entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);

  Future<PluginManifest?> _storedManifest(String id) async {
    final file = File('${(await _pluginsDir()).path}/$id/manifest.json');
    if (!await file.exists()) return null;
    try {
      return PluginManifest.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } catch (_) {
      return null;
    }
  }

  /// The user's values for the settings [manifest] declares now (a value of
  /// a setting an update dropped is left out), and the LAN servers they name:
  /// only addresses in settings that are not secret count.
  Future<({Map<String, String> values, Set<String> lanHosts})> _settingsOf(
    PluginManifest manifest,
  ) async {
    final stored = await variables(manifest.id);
    final values = {
      for (final variable in manifest.variables)
        variable.key: ?stored[variable.key],
    };
    final lanHosts = EgressPolicy.lanHostsIn([
      for (final variable in manifest.variables)
        if (!variable.isSecret) ?values[variable.key],
    ]);
    return (values: values, lanHosts: lanHosts);
  }

  /// The values the user entered for plugin [id]'s settings.
  Future<Map<String, String>> variables(String id) async {
    final file = File('${(await _pluginsDir()).path}/$id/$_variablesFile');
    if (!await file.exists()) return const {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      return const {};
    }
  }

  /// Stores [values] for the plugin's declared settings only, readable by
  /// the user alone. An empty value removes the setting.
  Future<void> saveVariables(
    PluginManifest manifest,
    Map<String, String> values,
  ) async {
    final declared = {for (final variable in manifest.variables) variable.key};
    final kept = <String, String>{
      for (final entry in values.entries)
        if (declared.contains(entry.key) && entry.value.trim().isNotEmpty)
          entry.key: entry.value.length > _maxValueLength
              ? entry.value.substring(0, _maxValueLength)
              : entry.value,
    };
    await writePrivateFile(
      File('${(await _pluginsDir()).path}/${manifest.id}/$_variablesFile'),
      jsonEncode(kept),
    );
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final file = File('${(await _pluginsDir()).path}/$id/manifest.json');
    if (!await file.exists()) return;
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final manifest = PluginManifest.fromJson(json).copyWith(enabled: enabled);
    await writeFileAtomically(file, jsonEncode(manifest.toJson()));
  }

  /// Reads one stored plugin. Its engine starts on first use; a plugin
  /// installed before its functions were recorded is started once here to
  /// record them.
  Future<PluginCatalogSource?> _loadOne(Directory dir) async {
    final manifestFile = File('${dir.path}/manifest.json');
    final scriptFile = File('${dir.path}/plugin.js');
    if (!await manifestFile.exists() || !await scriptFile.exists()) return null;
    try {
      final manifest = PluginManifest.fromJson(
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>,
      );
      if (manifest.functions == null) {
        return await _loadLegacy(manifest, scriptFile);
      }
      return _lazySource(manifest, scriptFile);
    } catch (_) {
      return null; // A broken stored plugin is skipped.
    }
  }

  Future<PluginCatalogSource> _loadLegacy(
    PluginManifest manifest,
    File scriptFile,
  ) async {
    final runtime = await _startRuntime(await scriptFile.readAsString());
    final recorded = manifest.copyWith(
      functions: PluginCatalogSource.exportedFunctions(runtime).toList(),
    );
    runtime.dispose();
    await writeFileAtomically(
      File('${scriptFile.parent.path}/manifest.json'),
      jsonEncode(recorded.toJson()),
    );
    return _lazySource(recorded, scriptFile);
  }

  Future<PluginRuntime> _startRuntime(
    String script, {
    Map<String, String> userVariables = const {},
    Set<String> lanHosts = const {},
  }) async {
    final runtime = _createRuntime(
      PluginEnvironment.current(userVariables: userVariables),
      lanHosts,
    );
    try {
      await runtime.load(script);
      return runtime;
    } catch (_) {
      runtime.dispose(); // Don't leak the JS engine on a broken plugin.
      rethrow;
    }
  }

  /// Writes the plugin to a staging directory, along with the other files
  /// the installed version keeps beside it when [keepFiles], then swaps it in.
  Future<Directory> _store(
    PluginManifest manifest,
    String source, {
    required bool keepFiles,
  }) async {
    final root = (await _pluginsDir()).path;
    final dir = Directory('$root/${manifest.id}');
    final staging = Directory('${dir.path}$_staging');
    final previous = Directory('${dir.path}$_previous');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    if (keepFiles && await dir.exists()) {
      for (final entry in await dir.list().toList()) {
        final name = _nameOf(entry);
        if (entry is File && name != 'plugin.js' && name != 'manifest.json') {
          await _copyKeepingMode(entry, '${staging.path}/$name');
        }
      }
    }
    await File('${staging.path}/plugin.js').writeAsString(source, flush: true);
    await File(
      '${staging.path}/manifest.json',
    ).writeAsString(jsonEncode(manifest.toJson()), flush: true);
    if (await previous.exists()) await previous.delete(recursive: true);
    if (await dir.exists()) await dir.rename(previous.path);
    await staging.rename(dir.path);
    if (await previous.exists()) await previous.delete(recursive: true);
    return dir;
  }

  /// Copies [file], keeping who may read it (the user's settings are
  /// private).
  static Future<void> _copyKeepingMode(File file, String target) async {
    final mode = (await file.stat()).mode & 0x1ff;
    if (Platform.isWindows) {
      await file.copy(target);
      return;
    }
    final copy = await File(target).create(exclusive: true);
    if (!Libc.chmod(copy.path, mode)) {
      throw FileSystemException('Could not keep the file mode', copy.path);
    }
    await copy.writeAsBytes(await file.readAsBytes(), flush: true);
  }

  Future<Directory> _pluginsDir() async {
    final override = _pluginsDirectory;
    if (override != null) return override();
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/plugins');
  }

  /// Converts a GitHub `blob` URL to its raw form; passes raw URLs through.
  Uri _normalize(String input) {
    final uri = Uri.parse(input.trim());
    if (uri.host == 'github.com' && uri.pathSegments.contains('blob')) {
      final segments = List.of(uri.pathSegments)..remove('blob');
      return Uri.https('raw.githubusercontent.com', '/${segments.join('/')}');
    }
    return uri;
  }

  Future<String> _fetch(Uri uri) async {
    if (uri.scheme != 'https') {
      throw PluginInstallException(AppStrings.t('plugin.err.invalidUrl'));
    }
    final override = _fetchOverride;
    if (override != null) return override(uri);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    policy.attach(client, httpsOnly: true);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'TimbreBox');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw PluginInstallException(
          AppStrings.t(
            'plugin.err.downloadHttp',
          ).replaceFirst('{code}', '${response.statusCode}'),
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw PluginInstallException(AppStrings.t('plugin.err.tooLarge'));
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } on EgressDeniedException catch (error) {
      throw PluginInstallException(error.message);
    } on SocketException {
      throw PluginInstallException(AppStrings.t('plugin.err.network'));
    } on TimeoutException {
      throw PluginInstallException(AppStrings.t('plugin.err.timeout'));
    } finally {
      client.close(force: true);
    }
  }
}

class PluginInstallException implements Exception {
  const PluginInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}
