import '../model/search_models.dart';

enum PlaybackStatus { idle, loading, playing, paused, failed }

class PlaybackState {
  const PlaybackState({
    required this.status,
    this.candidate,
    this.errorMessage,
    this.errorCode,
  });

  const PlaybackState.idle() : this(status: PlaybackStatus.idle);

  final PlaybackStatus status;
  final StreamCandidate? candidate;
  final String? errorMessage;
  final String? errorCode;

  bool get isPlaying => status == PlaybackStatus.playing;
}
