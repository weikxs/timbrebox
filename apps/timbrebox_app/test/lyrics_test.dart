import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/network_player_engine.dart';
import 'package:timbrebox_app/app/widgets/lyrics_view.dart';

void main() {
  group('LRC', () {
    test('reads timed lines in order, several stamps per line', () {
      final lyric = Lyric.parse('''
[ti:Song]
[ar:Artist]
[00:12.50]second
[00:01.00][00:20]first and last
plain words without a time
''');

      expect(lyric.isSynced, isTrue);
      expect(lyric.lines.map((line) => (line.time, line.text)), [
        (const Duration(seconds: 1), 'first and last'),
        (const Duration(milliseconds: 12500), 'second'),
        (const Duration(seconds: 20), 'first and last'),
      ]);
    });

    test('applies the offset tag', () {
      final lyric = Lyric.parse('[offset:500]\n[00:02.00]a');

      expect(lyric.lines.single.time, const Duration(milliseconds: 2500));
    });

    test('text without time stamps stays readable but unsynced', () {
      final lyric = Lyric.parse('line one\n\nline two');

      expect(lyric.isSynced, isFalse);
      expect(lyric.lines.map((line) => line.text), ['line one', 'line two']);
    });

    test('finds the line playing at a position', () {
      final lyric = Lyric.parse('[00:01.00]a\n[00:05.00]b\n[00:09.00]c');

      expect(lyric.indexAt(Duration.zero), -1);
      expect(lyric.indexAt(const Duration(seconds: 1)), 0);
      expect(lyric.indexAt(const Duration(seconds: 7)), 1);
      expect(lyric.indexAt(const Duration(minutes: 3)), 2);
    });
  });

  testWidgets('highlights the current line and seeks to a tapped one', (
    tester,
  ) async {
    final engine = _SeekingEngine();
    final controller = AppController(engine: engine);
    addTearDown(controller.dispose);
    await controller.play(_track);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsView(
            controller: controller,
            lyric: Lyric.parse('[00:01.00]first\n[00:05.00]second'),
          ),
        ),
      ),
    );
    engine.emit(const Duration(seconds: 6));
    await tester.pump();

    expect(_isCurrent(tester, 'second'), isTrue);
    expect(_isCurrent(tester, 'first'), isFalse);

    await tester.tap(find.text('first'));
    await tester.pump();

    expect(engine.seeks, [const Duration(seconds: 1)]);
    expect(_isCurrent(tester, 'first'), isTrue);
  });
}

bool _isCurrent(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.fontWeight == FontWeight.w700;

const _track = CatalogTrack(
  id: 'a',
  title: 'Song',
  artist: 'Artist',
  sourceId: 'plugin_p',
  sourceName: 'P',
  duration: Duration(minutes: 3),
  quality: 'high',
);

final class _SeekingEngine
    implements PlayerEngine, PlaybackProgressEvents, PauseReleaseConfig {
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final seeks = <Duration>[];

  void emit(Duration value) => _positions.add(value);

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<Duration> get durations => const Stream.empty();

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> load(StreamCandidate candidate) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> release() async {}

  @override
  Future<void> setReleaseAfterPause(bool enabled) async {}
}
