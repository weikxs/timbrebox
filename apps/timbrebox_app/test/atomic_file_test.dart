import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/state/atomic_file.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('tb_atomic'));
  tearDown(() => dir.delete(recursive: true));

  test('overlapping writes leave the last value as valid JSON', () async {
    final file = File('${dir.path}/settings.json');

    await Future.wait([
      for (var i = 0; i < 40; i++)
        writeFileAtomically(
          file,
          jsonEncode({'volume': i.isEven ? 0.7999999 : 0.8, 'i': i}),
        ),
    ]);

    final saved = jsonDecode(file.readAsStringSync()) as Map;
    expect(saved['i'], 39);
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), [
      'settings.json',
    ]);
  });

  test('a shorter value fully replaces a longer one', () async {
    final file = File('${dir.path}/session.json');
    await writeFileAtomically(file, '{"positionMs": 123456789}');

    await writeFileAtomically(file, '{"positionMs": 1}');

    expect(file.readAsStringSync(), '{"positionMs": 1}');
  });

  test('creates the parent directory', () async {
    final file = File('${dir.path}/nested/deeper/favorites.json');

    await writeFileAtomically(file, '[]');

    expect(file.readAsStringSync(), '[]');
  });

  test('a failed write leaves no temporary file behind', () async {
    // A directory where the file should be: the final rename fails.
    final blocked = await Directory('${dir.path}/settings.json').create();
    await File('${blocked.path}/inside').writeAsString('x');

    await expectLater(
      writeFileAtomically(File(blocked.path), '{}'),
      throwsA(isA<FileSystemException>()),
    );

    expect(
      dir.listSync().map(
        (entry) => entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
      ),
      ['settings.json'],
    );
  });
}
