part of 'app_controller.dart';

/// The system around playback: the OS media session (media keys, Bluetooth
/// buttons, lock screen), audio route changes, and the sleep timer.
extension AppControllerSystem on AppController {
  Future<void> _initMediaControls() async {
    try {
      await _mediaControls.init();
    } catch (_) {
      return; // Session integration is best-effort; playback works without it.
    }
    _mediaCommandSubscription = _mediaControls.commands.listen(_onMediaCommand);
    _mediaSeekSubscription = _mediaControls.seeks.listen(
      (position) => unawaited(seek(position)),
    );
  }

  // ---- Audio output route (Bluetooth / headphones connect + disconnect) ----

  Future<void> _initRouteMonitor() async {
    try {
      await _routeMonitor.start();
    } catch (_) {
      return; // Best-effort; playback works without route awareness.
    }
    _routeSubscription = _routeMonitor.events.listen(_onRouteEvent);
  }

  Future<void> _onRouteEvent(AudioRouteEvent event) async {
    switch (event) {
      case AudioRouteEvent.outputDisconnected:
        // Bluetooth / headphones went away: pause and remember, so audio does
        // not suddenly blast out of the built-in speakers.
        if (isPlaying) {
          _pausedByRoute = true;
          await _player.pause();
          _syncPlaybackState();
          _notify();
        }
      case AudioRouteEvent.outputConnected:
        // The device came back: resume only what we auto-paused (a manual
        // pause/play in between clears the flag, so we never fight the user).
        final track = _currentTrack;
        if (_pausedByRoute && !isPlaying && track != null) {
          _pausedByRoute = false;
          await _resumeOrReload(track);
          _syncPlaybackState();
          _notify();
        }
    }
  }

  void _onMediaCommand(MediaCommand command) {
    switch (command) {
      case MediaCommand.play:
        if (!isPlaying) unawaited(togglePlayback());
      case MediaCommand.pause:
        if (isPlaying) unawaited(togglePlayback());
      case MediaCommand.stop:
        unawaited(stopPlayback());
      case MediaCommand.next:
        unawaited(next());
      case MediaCommand.previous:
        unawaited(previous());
    }
  }

  // ---- Sleep timer ----

  bool get hasSleepTimer => _sleepTimer != null;
  Duration? get sleepTimerRemaining => _sleepRemaining;
  Duration? get sleepTimerTotal => _sleepTimer == null ? null : _sleepTotal;

  /// The sleep countdown on its own channel (it ticks every second).
  ValueListenable<Duration?> get sleepRemainingListenable =>
      _sleepRemainingNotifier;
  String? get sleepTimerLabel =>
      _sleepRemaining == null ? null : _formatDuration(_sleepRemaining!);

  /// Pauses playback after [total]. Pass null (or non-positive) to cancel.
  void setSleepTimer(Duration? total) {
    _pauseWhenStarted = false;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = null;
    _sleepTotal = null;
    if (total == null || total <= Duration.zero) {
      _notify();
      return;
    }
    _sleepRemaining = total;
    _sleepTotal = total;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next =
          (_sleepRemaining ?? Duration.zero) - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _sleepTimer?.cancel();
        _sleepTimer = null;
        _sleepRemaining = null;
        if (isPlaying) {
          unawaited(_player.pause().then((_) => _persistSession()));
        } else if (isLoading) {
          _pauseWhenStarted = true; // play() pauses once the track starts
        }
        _syncPlaybackState();
        _notify();
      } else {
        _sleepRemaining = next; // Only the countdown label listens to this.
      }
    });
    _notify();
  }

  /// Stops playback and clears the OS media session (headset/OS "stop").
  Future<void> stopPlayback() async {
    await _player.stop();
    _persistSession();
    _syncPlaybackState();
    _notify();
  }

  void _syncNowPlaying() {
    final track = _currentTrack;
    if (track == null) return;
    _mediaControls.setNowPlaying(
      NowPlayingInfo(
        id: track.ref.toString(),
        title: track.title,
        artist: track.artist,
        album: track.sourceName,
        artUri: track.artworkUrl == null
            ? null
            : Uri.tryParse(track.artworkUrl!),
        duration: _playbackDuration > Duration.zero
            ? _playbackDuration
            : (track.hasKnownDuration ? track.duration : null),
      ),
    );
  }

  void _syncPlaybackState() {
    _mediaControls.setPlaybackState(
      playing: isPlaying,
      position: _position,
      duration: _playbackDuration == Duration.zero ? null : _playbackDuration,
    );
  }
}
