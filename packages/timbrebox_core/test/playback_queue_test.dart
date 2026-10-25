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

  test('next after removing the current item plays the following item', () {
    final queue = PlaybackQueue([...tracks, _track('four')])..select(0);

    queue.removeAt(0);

    expect(queue.next()?.title, 'two');
    expect(queue.next()?.title, 'three');
  });

  test('previous after removing the current item plays the one before', () {
    final queue = PlaybackQueue([...tracks, _track('four')])..select(2);

    queue.removeAt(2);

    expect(queue.previous()?.title, 'two');
  });

  test('removing the current last item ends the queue unless it wraps', () {
    final queue = PlaybackQueue(tracks)..select(2);

    queue.removeAt(2);

    expect(queue.next(), isNull);
    final wrapping = PlaybackQueue(tracks)..select(2);
    wrapping.removeAt(2);
    expect(wrapping.next(wrap: true)?.title, 'one');
  });

  test('play-next after removing the current item becomes the next item', () {
    final queue = PlaybackQueue(tracks)..select(0);

    queue.removeAt(0);
    queue.add(_track('inserted'), playNext: true);

    expect(queue.next()?.title, 'inserted');
    expect(queue.next()?.title, 'two');
  });

  test('exposes the selected index, also for repeated tracks', () {
    final queue = PlaybackQueue([tracks[0], tracks[0], tracks[1]])..select(0);

    expect(queue.next()?.title, 'one');
    expect(queue.currentIndex, 1);
    expect(queue.next()?.title, 'two');
    expect(queue.currentIndex, 2);
  });
}

TrackSummary _track(String id) => TrackSummary(
  ref: MediaRef(sourceId: 'fixture', itemId: id),
  title: id,
  artist: 'artist',
);
