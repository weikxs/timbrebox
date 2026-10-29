import 'dart:async';

/// Reads the playback position on a fixed clock while audio is playing.
///
/// libmpv reports `time-pos` on every audio tick, 10-50 times a second, and
/// each report is a trip into Dart; the UI only shows whole seconds. Sampling
/// a few times a second keeps seek and session precision well under a second
/// at a fraction of the cost, and costs nothing while paused.
final class PositionSampler {
  PositionSampler({
    required this.read,
    required Stream<bool> playing,
    required bool initiallyPlaying,
    this.interval = defaultInterval,
  }) {
    _playingSubscription = playing.listen(_setPlaying);
    _setPlaying(initiallyPlaying);
  }

  /// Four samples a second: the shown second changes at most 250 ms late.
  static const defaultInterval = Duration(milliseconds: 250);

  /// The current position, or null when there is none (nothing loaded).
  final Future<Duration?> Function() read;
  final Duration interval;

  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  late final StreamSubscription<bool> _playingSubscription;
  Timer? _timer;

  Stream<Duration> get positions => _positions.stream;

  void _setPlaying(bool playing) {
    if (playing && _timer == null) {
      _timer = Timer.periodic(interval, (_) => unawaited(_sample()));
    } else if (!playing) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _sample() async {
    final position = await read();
    if (position == null || _positions.isClosed) return;
    _positions.add(position);
  }

  /// Stops reading at once; the streams close in the background.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_playingSubscription.cancel());
    unawaited(_positions.close());
  }
}
