import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/download_index_store.dart';

import 'support/test_player_engine.dart';

void main() {
  test('a download entry survives a JSON round trip', () {
    final entry = DownloadedEntry(track: _track('r'), path: '/data/r.mp3');
    final restored = DownloadedEntry.fromJson(
      jsonDecode(jsonEncode(entry.toJson())),
    );

    expect(restored, isNotNull);
    expect(restored!.track.id, 'r');
    expect(restored.track.sourceId, 'audius');
    expect(restored.track.duration, const Duration(minutes: 3));
    expect(restored.path, '/data/r.mp3');
  });

  test('the file store persists entries and prunes missing files', () async {
    final dir = await Directory.systemTemp.createTemp('tb_library');
    addTearDown(() => dir.delete(recursive: true));
    final present = File('${dir.path}/present.mp3')
      ..writeAsStringSync('audio');
    final store = FileDownloadIndexStore(directoryProvider: () async => dir);

    await store.save([
      DownloadedEntry(track: _track('present'), path: present.path),
      DownloadedEntry(track: _track('missing'), path: '${dir.path}/missing.mp3'),
    ]);
    final loaded = await store.load();

    expect(
      loaded.map((entry) => entry.track.id),
      ['present'],
      reason: 'a record whose file was deleted is dropped on load',
    );
  });

  test('the persisted local library is restored on startup', () async {
    final track = _track('local');
    final store = _FakeStore([
      DownloadedEntry(track: track, path: '/data/local.m4a'),
    ]);
    final controller = AppController(
      engine: TestPlayerEngine(),
      downloadStore: store,
    );

    await _settle();

    expect(controller.isDownloaded(track), isTrue);
    expect(controller.downloads.map((item) => item.ref), contains(track.ref));
    controller.dispose();
  });
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: '本地文件',
);

class _FakeStore implements DownloadIndexStore {
  _FakeStore(this._entries);

  final List<DownloadedEntry> _entries;

  @override
  Future<List<DownloadedEntry>> load() async => _entries;

  @override
  Future<void> save(List<DownloadedEntry> entries) async {}
}
