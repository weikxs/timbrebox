import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/catalog_download_service.dart';
import 'package:timbrebox_app/app/state/download_index_store.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  late Directory root;
  late Directory library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tb_download_safety');
    library = await Directory('${root.path}/TimbreBox').create();
  });

  tearDown(() => root.delete(recursive: true));

  group('CatalogDownloadService', () {
    test('refuses a file:// stream instead of copying the file', () async {
      final secret = File('${root.path}/id_rsa')..writeAsStringSync('KEY');
      final service = CatalogDownloadService(
        resolver: _FixedResolver(Uri.file(secret.path)),
        directoryProvider: () async => library,
      );

      await expectLater(
        service.download(_track('x')),
        throwsA(isA<StateError>()),
      );
      expect(library.listSync(), isEmpty);
    });
  });

  group('FileDownloadIndexStore', () {
    FileDownloadIndexStore store() =>
        FileDownloadIndexStore(directoryProvider: () async => library);

    File index() => File('${library.path}/library-index.json');

    void writeIndex(List<Map<String, Object?>> entries) =>
        index().writeAsStringSync(jsonEncode(entries));

    Map<String, Object?> raw(String id, String path) => {
      ...DownloadedEntry(track: _track(id), path: path).toJson(),
    };

    test('stores only the file name, not an absolute path', () async {
      final file = File('${library.path}/a.mp3')..writeAsStringSync('audio');

      await store().save([
        DownloadedEntry(track: _track('a'), path: file.path),
      ]);

      final saved = jsonDecode(index().readAsStringSync()) as List;
      expect((saved.single as Map)['path'], 'a.mp3');
    });

    test('loads a stored file name as a path inside the library', () async {
      final file = File('${library.path}/a.mp3')..writeAsStringSync('audio');
      writeIndex([raw('a', 'a.mp3')]);

      final loaded = await store().load();

      expect(loaded.single.path, file.path);
    });

    test('keeps a legacy absolute path that lies inside the library', () async {
      final file = File('${library.path}/old.mp3')..writeAsStringSync('audio');
      writeIndex([raw('old', file.path)]);

      final loaded = await store().load();

      expect(loaded.single.path, file.path);
    });

    test('drops entries that point outside the library', () async {
      final outside = File('${root.path}/document.pdf')
        ..writeAsStringSync('keep me');
      writeIndex([
        raw('abs', outside.path),
        raw('up', '../document.pdf'),
        raw('nested', 'sub/../../document.pdf'),
      ]);

      final loaded = await store().load();

      expect(loaded, isEmpty);
      expect(outside.existsSync(), isTrue);
    });
  });
}

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: 'public',
);

class _FixedResolver implements StreamResolver {
  _FixedResolver(this.uri);

  final Uri uri;

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async =>
      ResolvedStream(uri: uri);
}
