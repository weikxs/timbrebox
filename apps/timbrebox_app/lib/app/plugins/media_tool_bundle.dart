import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'media_extraction_error.dart';

/// Opt-in, locally prepared components. No discovery, downloads or PATH lookup.
final class MediaToolBundle {
  const MediaToolBundle(this.supervisor, this.runtime, this.supervisorSha256);
  final String supervisor;
  final String runtime;
  final String supervisorSha256;

  static final _sha = RegExp(r'^[a-f0-9]{64}$');
  static const names = {
    'supervisor': 'media-supervisor',
    'extractor': 'yt-dlp',
    'runtime': 'deno',
  };
  static const licenses = [
    'LICENSE',
    'THIRD_PARTY_LICENSES.txt',
    'GPL-3.0.txt',
    'DENO-LICENSE.md',
  ];

  static Future<MediaToolBundle> load(
    String expectedManifestSha256, {
    Directory? directory,
    void Function()? checkCancelled,
  }) async {
    Future<String> fileDigest(File file) async =>
        (await sha256
                .bind(
                  file.openRead().map((chunk) {
                    checkCancelled?.call();
                    return chunk;
                  }),
                )
                .first)
            .toString();
    checkCancelled?.call();
    Never invalid() => throw const MediaExtractionException(
      'extractor_integrity',
      'The prepared media component bundle is invalid.',
    );
    if (!_sha.hasMatch(expectedManifestSha256)) invalid();
    final folder =
        directory ??
        Directory.fromUri(
          File(Platform.resolvedExecutable).parent.uri.resolve('../'),
        );
    final root = await folder.resolveSymbolicLinks();
    final resources = '$root/Resources/TimbreBoxMedia';
    final binaries = '$root/Helpers/TimbreBoxMedia.app/Contents/MacOS';
    final manifestFile = File('$resources/manifest.json');
    if (await manifestFile.length() > 64 * 1024 ||
        await manifestFile.resolveSymbolicLinks() != manifestFile.path) {
      invalid();
    }
    final bytes = await manifestFile.readAsBytes();
    if (sha256.convert(bytes).toString() != expectedManifestSha256) invalid();
    final Object? value;
    try {
      value = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      invalid();
    }
    if (value is! Map ||
        value['schema'] != 1 ||
        value['distribution'] != 'local-test-only') {
      invalid();
    }
    final paths = <String, String>{};
    for (final entry in names.entries) {
      final record = value[entry.key];
      if (record is! Map ||
          record['name'] != entry.value ||
          record['sha256'] is! String ||
          !_sha.hasMatch(record['sha256'] as String)) {
        invalid();
      }
      final file = File(switch (entry.key) {
        'extractor' => '$resources/Extractor/${entry.value}',
        'runtime' => '$resources/Runtime/${entry.value}',
        _ => '$binaries/${entry.value}',
      });
      if (await file.resolveSymbolicLinks() != file.path ||
          await file.length() > 256 * 1024 * 1024) {
        invalid();
      }
      final actual = await fileDigest(file);
      if (actual != record['sha256']) invalid();
      paths[entry.key] = file.path;
    }
    // Freeze the entire Python payload, not only its launcher. Extra modules,
    // missing files and links must never borrow a verified executable identity.
    final payload = value['payload'];
    if (payload is! Map || payload.isEmpty || payload.length > 512) invalid();
    final payloadRoot = '$resources/Extractor/';
    final found = <String>{};
    var entries = 0;
    var payloadBytes = 0;
    await for (final entity in Directory(
      payloadRoot,
    ).list(recursive: true, followLinks: false)) {
      checkCancelled?.call();
      if (++entries > 1024 || entity is Link) invalid();
      if (entity is! File) continue;
      final name = entity.path.substring(payloadRoot.length);
      final expected = payload[name];
      payloadBytes += await entity.length();
      if (expected is! String ||
          !_sha.hasMatch(expected) ||
          payloadBytes > 256 * 1024 * 1024) {
        invalid();
      }
      if (await fileDigest(entity) != expected) invalid();
      found.add(name);
    }
    if (found.length != payload.length) invalid();
    final notices = value['licenses'];
    if (notices is! Map) invalid();
    for (final name in licenses) {
      final file = File('$resources/Licenses/$name');
      if (await file.resolveSymbolicLinks() != file.path ||
          await file.length() > 1024 * 1024) {
        invalid();
      }
      if (await fileDigest(file) != notices[name]) {
        invalid();
      }
    }
    return MediaToolBundle(
      paths['supervisor']!,
      paths['runtime']!,
      (value['supervisor'] as Map)['sha256'] as String,
    );
  }
}
