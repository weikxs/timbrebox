import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

void main() {
  final tracks = [_track('alpha'), _track('bravo'), _track('charlie')];

  test(
    'shares playback, queue, favourites and download intent in one session',
    () async {
      final controller = AppController(engine: TestPlayerEngine());

      await controller.play(tracks.first);
      controller.addNext(tracks[2]);
      controller.toggleFavorite(tracks.first);
      controller.toggleDownload(tracks.first);

      expect(controller.isPlaying, isTrue);
      expect(controller.currentTrack?.ref, tracks.first.ref);
      expect(controller.queue[1].ref, tracks[2].ref);
      expect(controller.isFavorite(tracks.first), isTrue);
      expect(controller.isDownloaded(tracks.first), isTrue);
      controller.dispose();
    },
  );

  test('returns live source results and honours the source switch', () async {
    final controller = AppController(
      engine: TestPlayerEngine(),
      catalog: _Catalog(tracks),
    );

    await controller.search('anything');
    expect(controller.searchResults, hasLength(3));

    controller.setSourceEnabled('audius', false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.searchResults, isEmpty);
    controller.dispose();
  });

  test(
    'next and previous keep the mini-player selection inside the queue',
    () async {
      final controller = AppController(engine: TestPlayerEngine());
      await controller.play(tracks[1]);
      controller.addNext(tracks[2]);

      await controller.next();
      expect(controller.currentTrack?.ref, tracks[2].ref);

      await controller.previous();
      expect(controller.currentTrack?.ref, tracks[1].ref);
      controller.dispose();
    },
  );

  test('keeps settings controls in the same observable session state', () {
    final controller = AppController(engine: TestPlayerEngine());

    controller
      ..setSettingsSection(SettingsSection.downloads)
      ..setLanguage('English')
      ..setAutoPlay(false)
      ..setVolume(.35)
      ..setLoop(PlaybackLoop.track)
      ..setDiagnosticLogging(true);

    expect(controller.settingsSection, SettingsSection.downloads);
    expect(controller.language, 'English');
    expect(controller.autoPlay, isFalse);
    expect(controller.volume, .35);
    expect(controller.loop, PlaybackLoop.track);
    expect(controller.diagnosticLogging, isTrue);
    controller.dispose();
  });

  test('respects sequence and shuffle rules when advancing', () async {
    final controller = AppController(
      engine: TestPlayerEngine(),
      random: Random(7),
    );

    await controller.play(tracks.first);
    controller.addNext(tracks.last);
    await controller.play(tracks.last);
    controller.setLoop(PlaybackLoop.off);
    await controller.next();
    expect(controller.currentTrack?.ref, tracks.last.ref);

    controller.setLoop(PlaybackLoop.queue);
    await controller.next();
    expect(controller.currentTrack?.ref, tracks.first.ref);

    controller.setLoop(PlaybackLoop.shuffle);
    await controller.next();
    expect(controller.currentTrack?.ref, isNot(tracks.first.ref));
    controller.dispose();
  });

  test('restarts the current track after a single-repeat completion', () async {
    final engine = _CompletingPlayerEngine();
    final controller = AppController(engine: engine);

    controller.setLoop(PlaybackLoop.track);
    await controller.play(tracks.first);
    engine.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(engine.playCalls, 2);
    expect(controller.currentTrack?.ref, tracks.first.ref);
    controller.dispose();
  });
}

CatalogTrack _track(String id) => CatalogTrack(
  id: id,
  title: 'Track $id',
  artist: 'Test artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: const Duration(minutes: 3),
  quality: '待解析',
);

class _Catalog implements MusicCatalog {
  _Catalog(this.tracks);
  final List<CatalogTrack> tracks;

  @override
  Iterable<SourceDescriptor> get sources => [
    SourceDescriptor(
      id: 'audius',
      name: 'Audius',
      capabilities: [SourceCapability.search, SourceCapability.streaming],
    ),
  ];

  var enabled = true;

  @override
  bool isEnabled(String sourceId) => sourceId == 'audius' && enabled;

  @override
  Future<List<CatalogTrack>> search(
    String query, {
    required CancellationToken cancellation,
  }) async => enabled ? tracks : [];

  @override
  void setEnabled(String sourceId, bool value) => enabled = value;
}

class _CompletingPlayerEngine
    implements PlayerEngine, PlaybackCompletionEvents {
  final StreamController<void> _events = StreamController.broadcast();
  var playCalls = 0;

  @override
  Stream<void> get completed => _events.stream;

  void complete() => _events.add(null);

  @override
  Future<void> load(StreamCandidate candidate) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> release() => _events.close();

  @override
  Future<void> stop() async {}
}
