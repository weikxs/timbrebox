import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../design/app_strings.dart';
import 'plugin_catalog_source.dart';
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

/// Installs, persists, and loads plugins.
///
/// Each plugin lives under `<appSupport>/plugins/<id>/` as `plugin.js` +
/// `manifest.json`. Installing fetches the raw `.js` from a GitHub URL, runs it
/// once to read its metadata, then stores it. Loading rebuilds a live
/// [PluginCatalogSource] per stored plugin.
final class PluginRepository {
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
      return [await _installSource(content, uri)];
    }
    if (urls.isEmpty) {
      throw PluginInstallException(AppStrings.t('plugin.err.emptySubscription'));
    }
    final installed = <PluginCatalogSource>[];
    final errors = <String>[];
    for (final pluginUrl in urls) {
      try {
        final source = await _fetch(_normalize(pluginUrl));
        installed.add(await _installSource(source, _normalize(pluginUrl)));
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
    return _installSource(content, _normalize(src));
  }

  /// Validates a plugin [source], stores it, and returns a live source.
  Future<PluginCatalogSource> _installSource(String source, Uri origin) async {
    final runtime = PluginRuntime();
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
    );
    await _store(manifest, source);
    return PluginCatalogSource(manifest: manifest, runtime: runtime);
  }

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

  /// Rebuilds live sources for every stored plugin (skips ones that fail).
  Future<List<PluginCatalogSource>> loadInstalled() async {
    final directory = await _pluginsDir();
    if (!await directory.exists()) return const [];
    final sources = <PluginCatalogSource>[];
    for (final entry in await directory.list().toList()) {
      if (entry is! Directory) continue;
      final source = await _loadOne(entry);
      if (source != null) sources.add(source);
    }
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
    await file.writeAsString(jsonEncode(manifest.toJson()), flush: true);
  }

  Future<PluginCatalogSource?> _loadOne(Directory dir) async {
    final manifestFile = File('${dir.path}/manifest.json');
    final scriptFile = File('${dir.path}/plugin.js');
    if (!await manifestFile.exists() || !await scriptFile.exists()) return null;
    PluginRuntime? runtime;
    try {
      final manifest = PluginManifest.fromJson(
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>,
      );
      runtime = PluginRuntime();
      await runtime.load(await scriptFile.readAsString());
      return PluginCatalogSource(manifest: manifest, runtime: runtime);
    } catch (_) {
      runtime?.dispose(); // Don't leak the JS engine on a broken stored plugin.
      return null;
    }
  }

  Future<void> _store(PluginManifest manifest, String source) async {
    final dir = Directory('${(await _pluginsDir()).path}/${manifest.id}');
    await dir.create(recursive: true);
    await File('${dir.path}/plugin.js').writeAsString(source, flush: true);
    await File(
      '${dir.path}/manifest.json',
    ).writeAsString(jsonEncode(manifest.toJson()), flush: true);
  }

  Future<Directory> _pluginsDir() async {
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
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw PluginInstallException(AppStrings.t('plugin.err.invalidUrl'));
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
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
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw PluginInstallException(AppStrings.t('plugin.err.tooLarge'));
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
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
