import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/state/position_sampler.dart';

/// libmpv's per-tick `time-pos` reports are replaced by a few reads a second,
/// and none while paused.
void main() {
  late StreamController<bool> playing;
  late List<Duration> samples;
  late int reads;
  Duration? current;

  PositionSampler startSampler({required bool initiallyPlaying}) {
    playing = StreamController<bool>.broadcast();
    samples = [];
    reads = 0;
    current = const Duration(seconds: 3);
    final sampler = PositionSampler(
      read: () async {
        reads++;
        return current;
      },
      playing: playing.stream,
      initiallyPlaying: initiallyPlaying,
    );
    sampler.positions.listen(samples.add);
    return sampler;
  }

  testWidgets('reads the position four times a second while playing', (
    tester,
  ) async {
    final sampler = startSampler(initiallyPlaying: true);

    await tester.pump(const Duration(seconds: 1));

    expect(reads, 4);
    expect(samples, List.filled(4, const Duration(seconds: 3)));
    sampler.dispose();
  });

  testWidgets('does not read while paused, and resumes on play', (
    tester,
  ) async {
    final sampler = startSampler(initiallyPlaying: false);

    await tester.pump(const Duration(seconds: 2));
    expect(reads, 0);

    playing.add(true);
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 4);

    playing.add(false);
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 4);
    sampler.dispose();
  });

  testWidgets('skips reads with no position', (tester) async {
    final sampler = startSampler(initiallyPlaying: true);
    current = null;

    await tester.pump(const Duration(seconds: 1));

    expect(reads, 4);
    expect(samples, isEmpty);
    sampler.dispose();
  });

  testWidgets('stops reading once disposed', (tester) async {
    final sampler = startSampler(initiallyPlaying: true);
    sampler.dispose();

    await tester.pump(const Duration(seconds: 1));

    expect(reads, 0);
  });
}
