import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/stream_header_proxy.dart';
import '../design/app_strings.dart';
import '../net/egress_policy.dart';
import '../state/atomic_file.dart';
import 'plugin_catalog_source.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

/// Installs, persists, and loads plugins.
///
/// Each plugin lives under `<appSupport>/plugins/<id>/` as `plugin.js` +
/// `manifest.json`. Installing fetches the raw `.js` from a GitHub URL, runs it
/// once to read its metadata, then stores it. Loading rebuilds a
/// [PluginCatalogSource] per stored plugin whose JS engine starts on first use.
final class PluginRepository {
  PluginRepository({
    this.policy = const EgressPolicy(),
    Future<Directory> Function()? pluginsDirectory,
    PluginRuntime Function()? createRuntime,
    this.idleTimeout = PluginCatalogSource.defaultIdleTimeout,
  }) : _createRuntime = createRuntime ?? PluginRuntime.new,
       // ignore: prefer_initializing_formals
       _pluginsDirectory = pluginsDirectory,
       streamProxy = StreamHeaderProxy(policy: policy);

  /// Plugin code is fetched over https from public hosts only, on every
  /// redirect hop too: a plain-http or LAN source could hand us any script.
  /// Plugin stream URLs are held to the same public-hosts rule.
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
  final PluginRuntime Function() _createRuntime;

  static const _maxBytes = 6 * 1024 * 1024;

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
      throw PluginInstallException(AppStrings.t('plugin.err.emptySubscription'));
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
      throw PluginInstallException(AppStrings.t('plugin.err.subscriptionAllFailed').replaceFirst('{e}', errors.take(2).join('；')));
    }
    return installed;
  }

  /// Re-fetches a plugin from its `srcUrl` and reinstalls only when the content
  /// changed (SHA differs). Returns the fresh source, or null if up to date.
  Future<PluginCatalogSource?> update(PluginManifest manifest) async {
    final src = manifest.srcUrl;
    if (src == null || src.isEmpty) return null;
    final content = await _fetch(_normalize(src));
    if (sha256.convert(utf8.encode(content)).toString() == manifest.sha256) {
      return null; // Unchanged.
    }
    return installSource(content, _normalize(src));
  }

  /// Validates a plugin [source], stores it, and returns its catalog source.
  /// The engine that read the metadata is released; like a stored plugin,
  /// the source starts a fresh one on first use.
  @visibleForTesting
  Future<PluginCatalogSource> installSource(String source, Uri origin) async {
    final runtime = _createRuntime();
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
      id: PluginManifest.idFor(platform),
      platform: platform,
      version: runtime.meta('version') ?? '0.0.0',
      author: runtime.meta('author'),
      srcUrl: runtime.meta('srcUrl') ?? origin.toString(),
      sha256: sha256.convert(utf8.encode(source)).toString(),
      functions: PluginCatalogSource.exportedFunctions(runtime).toList(),
    );
    runtime.dispose();
    final directory = await _store(manifest, source);
    return _lazySource(manifest, File('${directory.path}/plugin.js'));
  }

  PluginCatalogSource _lazySource(PluginManifest manifest, File script) =>
      PluginCatalogSource.lazy(
        manifest: manifest,
        functions: (manifest.functions ?? const []).toSet(),
        loadRuntime: () async => _startRuntime(await script.readAsString()),
        proxy: streamProxy,
        policy: policy,
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
    final sources = <PluginCatalogSource>[];
    for (final entry in await directory.list().toList()) {
      if (entry is! Directory) continue;
      final source = await _loadOne(entry);
      if (source != null) {
        sources.add(source);
      } else {
        _skipped.add(entry.uri.pathSegments.where((s) => s.isNotEmpty).last);
      }
    }
    _skipped.sort();
    return sources;
  }

  Future<void> remove(String id) async {
    final dir = Directory('${(await _pluginsDir()).path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
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

  Future<PluginRuntime> _startRuntime(String script) async {
    final runtime = _createRuntime();
    try {
      await runtime.load(script);
      return runtime;
    } catch (_) {
      runtime.dispose(); // Don't leak the JS engine on a broken plugin.
      rethrow;
    }
  }

  Future<Directory> _store(PluginManifest manifest, String source) async {
    final dir = Directory('${(await _pluginsDir()).path}/${manifest.id}');
    await dir.create(recursive: true);
    // Each file is replaced in one step, so a crash mid-install leaves the
    // previous version readable instead of a truncated script or manifest.
    await writeFileAtomically(File('${dir.path}/plugin.js'), source);
    await writeFileAtomically(
      File('${dir.path}/manifest.json'),
      jsonEncode(manifest.toJson()),
    );
    return dir;
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    policy.attach(client, httpsOnly: true);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'TimbreBox');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw PluginInstallException(
          AppStrings.t('plugin.err.downloadHttp')
              .replaceFirst('{code}', '${response.statusCode}'),
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
