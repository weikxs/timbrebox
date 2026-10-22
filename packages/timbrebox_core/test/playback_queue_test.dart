import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  final tracks = [_track('one'), _track('two'), _track('three')];

  test('moves through an ordered queue and respects its end', () {
    final queue = PlaybackQueue(tracks)..select(1);

    expect(queue.current?.title, 'two');
    expect(queue.next()?.title, 'three');
    expect(queue.next(), isNull);
    expect(queue.previous()?.title, 'two');
  });

  test('move reorders and keeps the current track selected', () {
    // [one, two, three], playing "two" (index 1). Move "one" to the end.
    final queue = PlaybackQueue(tracks)..select(1);
    queue.move(0, 2);
    expect(queue.tracks.map((t) => t.title).toList(), ['two', 'three', 'one']);
    expect(queue.current?.title, 'two'); // still selected, now at index 0

    // Move the current track itself to the end.
    queue.move(0, 2);
    expect(queue.tracks.map((t) => t.title).toList(), ['three', 'one', 'two']);
    expect(queue.current?.title, 'two');
  });

  test('inserts a requested next item and keeps the current item stable', () {
    final queue = PlaybackQueue(tracks)..select(0);
    queue.add(_track('next'), playNext: true);

    expect(queue.current?.title, 'one');
    expect(queue.next()?.title, 'next');
  });

  test(
    'removing the current item moves naturally to the next remaining item',
    () {
      final queue = PlaybackQueue(tracks)..select(1);

      expect(queue.removeAt(1), isTrue);
      expect(queue.current?.title, 'three');
      expect(queue.tracks.map((track) => track.title), ['one', 'three']);
    },
  );
}

TrackSummary _track(String id) => TrackSummary(
  ref: MediaRef(sourceId: 'fixture', itemId: id),
  title: id,
  artist: 'artist',
);
