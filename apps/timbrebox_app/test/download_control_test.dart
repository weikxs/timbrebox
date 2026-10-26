import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/catalog_download_service.dart';

import 'support/test_player_engine.dart';

void main() {
  late Directory root;
  late Directory library;
  late HttpServer server;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tb_download_control');
    library = await Directory('${root.path}/TimbreBox').create();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/whole.mp3':
          response.contentLength = 4000;
          for (var part = 0; part < 4; part++) {
            response.add(List.filled(1000, part));
            await response.flush();
          }
          await response.close();
        case '/stalls.mp3':
          response.contentLength = 4 * _chunk;
          response.add(List.filled(_chunk, 1));
          await response.flush(); // ...and never sends the rest.
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  CatalogDownloadService service({
    String path = '/whole.mp3',
    Duration idleTimeout = const Duration(seconds: 30),
    Future<Directory> Function()? directory,
  }) => CatalogDownloadService(
    resolver: _FixedResolver(Uri.parse('http://127.0.0.1:${server.port}$path')),
    directoryProvider: directory ?? () async => library,
    idleTimeout: idleTimeout,
  );

  bool hasPartFiles() =>
      library.listSync().any((entry) => entry.path.endsWith('.part'));

  test('reports progress as the body arrives', () async {
    final progress = <(int, int?)>[];

    await service().download(
      _track('a'),
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(progress, isNotEmpty);
    expect(progress.last, (4000, 4000));
  });

  test('gives up on a body that stops arriving', () async {
    await expectLater(
      service(
        path: '/stalls.mp3',
        idleTimeout: const Duration(milliseconds: 150),
      ).download(_track('a')).timeout(const Duration(seconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
    expect(hasPartFiles(), isFalse);
  });

  test('a cancelled download stops and leaves no partial file', () async {
    final cancellation = CancellationToken();
    final running = service(
      path: '/stalls.mp3',
    ).download(_track('a'), cancellation: cancellation);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    cancellation.cancel();

    await expectLater(
      running.timeout(const Duration(seconds: 3)),
      throwsA(isA<OperationCancelled>()),
    );
    expect(hasPartFiles(), isFalse);
  });

  test('refuses a stream on a private network address', () async {
    final download = CatalogDownloadService(
      resolver: _FixedResolver(Uri.parse('http://10.20.30.40/a.mp3')),
      directoryProvider: () async => library,
    ).download(_track('a'));

    await expectLater(
      download.timeout(const Duration(seconds: 3)),
      throwsA(isNot(isA<TimeoutException>())),
    );
  });

  test('clears partial files left by an earlier run', () async {
    final stale = File('${library.path}/old [1234].mp3.part')
      ..writeAsStringSync('half')
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final kept = File('${library.path}/done [5678].mp3')
      ..writeAsStringSync('audio');

    await service().removeStaleParts();

    expect(stale.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
  });

  test('tapping a running download cancels it', () async {
    final controller = AppController(
      engine: TestPlayerEngine(),
      downloadService: service(path: '/stalls.mp3'),
    );
    addTearDown(controller.dispose);
    final track = _track('a');

    controller.toggleDownload(track);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.isDownloading(track), isTrue);
    expect(controller.downloadProgressFor(track), closeTo(.25, .01));

    controller.toggleDownload(track);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(controller.isDownloading(track), isFalse);
    expect(controller.downloadErrorFor(track), isNull);
    expect(controller.isDownloaded(track), isFalse);
  });

  test('a failed download names no local path', () async {
    final blocker = File('${root.path}/not-a-folder')..writeAsStringSync('');
    final controller = AppController(
      engine: TestPlayerEngine(),
      downloadService: service(
        directory: () async => Directory('${blocker.path}/TimbreBox'),
      ),
    );
    addTearDown(controller.dispose);
    final track = _track('a');

    controller.toggleDownload(track);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final error = controller.downloadErrorFor(track);
    expect(error, isNotNull);
    expect(error, isNot(contains(root.path)));
    expect(error, isNot(contains('not-a-folder')));
  });
}

const _chunk = 64 * 1024;

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Artist',
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
      ResolvedStream(uri: uri, mimeType: 'audio/mpeg');
}
