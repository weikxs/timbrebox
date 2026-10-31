import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/media_tool_bundle.dart';
import 'package:timbrebox_app/app/plugins/media_extraction_error.dart';

void main() {
  late Directory directory;
  late String resources;
  late String binaries;
  late Map<String, Object?> manifest;
  late String digest;
  Future<void> save() async {
    final text = jsonEncode(manifest);
    await File('$resources/manifest.json').writeAsString(text);
    digest = sha256.convert(utf8.encode(text)).toString();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('media-bundle-test-');
    resources = '${directory.path}/Resources/TimbreBoxMedia';
    binaries = '${directory.path}/Helpers/TimbreBoxMedia.app/Contents/MacOS';
    await Directory(resources).create(recursive: true);
    await Directory(binaries).create(recursive: true);
    await Directory('$resources/Extractor').create();
    await Directory('$resources/Runtime').create();
    manifest = {'schema': 1, 'distribution': 'local-test-only'};
    for (final entry in MediaToolBundle.names.entries) {
      final body = utf8.encode('Demo ${entry.key}');
      final path = entry.key == 'extractor'
          ? '$resources/Extractor/${entry.value}'
          : entry.key == 'runtime'
          ? '$resources/Runtime/${entry.value}'
          : '$binaries/${entry.value}';
      await File(path).writeAsBytes(body);
      manifest[entry.key] = {
        'name': entry.value,
        'sha256': sha256.convert(body).toString(),
      };
    }
    manifest['payload'] = {'yt-dlp': (manifest['extractor'] as Map)['sha256']};
    await Directory('$resources/Licenses').create();
    final licenses = <String, String>{};
    for (final name in MediaToolBundle.licenses) {
      final body = utf8.encode('Fixture license record: $name');
      await File('$resources/Licenses/$name').writeAsBytes(body);
      licenses[name] = sha256.convert(body).toString();
    }
    manifest['licenses'] = licenses;
    await save();
  });
  tearDown(() => directory.delete(recursive: true));
  Matcher integrity() => isA<MediaExtractionException>().having(
    (e) => e.code,
    'code',
    'extractor_integrity',
  );

  test('all executable bytes and mandatory notices are pinned', () async {
    final bundle = await MediaToolBundle.load(digest, directory: directory);
    expect(bundle.supervisor, endsWith('/media-supervisor'));
    expect(bundle.runtime, endsWith('/deno'));
  });
  test('manifest digest mismatch fails closed', () async {
    await expectLater(
      MediaToolBundle.load('0' * 64, directory: directory),
      throwsA(integrity()),
    );
  });
  test('modified runtime cannot borrow a verified launcher identity', () async {
    await File('$resources/Runtime/deno').writeAsString('Changed');
    await expectLater(
      MediaToolBundle.load(digest, directory: directory),
      throwsA(integrity()),
    );
  });
  test(
    'manifest cannot select arbitrary names or traverse outside the bundle',
    () async {
      (manifest['runtime'] as Map)['name'] = '../other';
      await save();
      await expectLater(
        MediaToolBundle.load(digest, directory: directory),
        throwsA(integrity()),
      );
    },
  );
  test('notice corruption is not silently discarded', () async {
    await File('$resources/Licenses/LICENSE').writeAsString('Changed');
    await expectLater(
      MediaToolBundle.load(digest, directory: directory),
      throwsA(integrity()),
    );
  });
  test(
    'extra Python modules are not trusted merely because the launcher matches',
    () async {
      await File('$resources/Extractor/extra.py').writeAsString('fixture');
      await expectLater(
        MediaToolBundle.load(digest, directory: directory),
        throwsA(integrity()),
      );
    },
  );
  test('missing pinned payload files fail closed', () async {
    (manifest['payload'] as Map)['missing.py'] = '0' * 64;
    await save();
    await expectLater(
      MediaToolBundle.load(digest, directory: directory),
      throwsA(integrity()),
    );
  });
  test('an unknown distribution profile is not activated', () async {
    manifest['distribution'] = 'unreviewed';
    await save();
    await expectLater(
      MediaToolBundle.load(digest, directory: directory),
      throwsA(integrity()),
    );
  });
  test('executable symlinks cannot escape the bundle', () async {
    await File('$resources/Runtime/deno').rename('$resources/Runtime/other');
    await Link('$resources/Runtime/deno').create('$resources/Runtime/other');
    await expectLater(
      MediaToolBundle.load(digest, directory: directory),
      throwsA(integrity()),
    );
  }, skip: Platform.isWindows);
}
