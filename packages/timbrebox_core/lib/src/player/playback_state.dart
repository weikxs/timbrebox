import '../model/search_models.dart';

enum PlaybackStatus { idle, loading, playing, paused, failed }

class PlaybackState {
  const PlaybackState({
    required this.status,
    this.candidate,
    this.errorMessage,
  });

  const PlaybackState.idle() : this(status: PlaybackStatus.idle);

  final PlaybackStatus status;
  final StreamCandidate? candidate;
  final String? errorMessage;

  bool get isPlaying => status == PlaybackStatus.playing;
}
