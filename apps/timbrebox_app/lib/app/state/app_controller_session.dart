part of 'app_controller.dart';

/// Saving and restoring settings and the listening session, and the local
/// control API that drives the player.
extension AppControllerSession on AppController {
  Future<void> _restoreSettings() async {
    final store = _settingsStore;
    if (store == null) return;
    final data = await store.load();
    _volume = ((data['volume'] as num?)?.toDouble() ?? _volume).clamp(0, 1);
    _rate = ((data['rate'] as num?)?.toDouble() ?? _rate).clamp(0.25, 3.0);
    _loop = PlaybackLoop.values.firstWhere(
      (loop) => loop.name == data['loop'],
      orElse: () => _loop,
    );
    _quality = QualityPreference.values.firstWhere(
      (quality) => quality.name == data['quality'],
      orElse: () => _quality,
    );
    _language = data['language'] as String? ?? _language;
    AppStrings.lang = AppStrings.fromName(_language);
    _autoPlay = data['autoPlay'] as bool? ?? _autoPlay;
    _reducedEffects = data['reducedEffects'] as bool? ?? _reducedEffects;
    _releaseAfterPause =
        data['releaseAfterPause'] as bool? ?? _releaseAfterPause;
    _diagnosticLogging =
        data['diagnosticLogging'] as bool? ?? _diagnosticLogging;
    _agentControl = data['agentControl'] as bool? ?? _agentControl;
    _shortcuts
      ..clear()
      ..addAll(shortcutsFromJson(data['shortcuts']));
    AppEffects.reduced = _reducedEffects;
    DiagnosticLog.enabled = _diagnosticLogging;
    if (_agentControl) unawaited(_startControlServer());
    await _player.setVolume(_volume);
    await _player.setRate(_rate);
    await _player.setReleaseAfterPause(_releaseAfterPause);
    _notify();
  }

  void _persistSettings() {
    _watchWrite(
      _settingsStore?.save({
        'volume': _volume,
        'rate': _rate,
        'loop': _loop.name,
        'quality': _quality.name,
        'language': _language,
        'autoPlay': _autoPlay,
        'reducedEffects': _reducedEffects,
        'releaseAfterPause': _releaseAfterPause,
        'diagnosticLogging': _diagnosticLogging,
        'agentControl': _agentControl,
        'shortcuts': shortcutsToJson(_shortcuts),
      }),
    );
  }

  Future<void> _restoreSession() async {
    // "Restore last session" is gated by the autoPlay preference.
    if (!_autoPlay) return;
    final store = _sessionStore;
    if (store == null) return;
    final session = await store.load();
    if (session == null || session.queue.isEmpty) return;
    for (final track in session.queue) {
      _knownTracks[track.ref.toString()] = track;
    }
    _queue.replace([
      for (final track in session.queue) track.summary,
    ], initialIndex: session.currentIndex);
    final current = _queue.current;
    if (current != null) {
      _currentTrack = _trackFor(current);
      // Show the saved position and resume there on the next play of this track.
      if (session.positionMs > 0) {
        _position = Duration(milliseconds: session.positionMs);
        _resumePosition = _position;
        _resumeRef = current.ref;
      }
      _syncNowPlaying();
    }
    _notify();
  }

  void _persistSession() => _watchWrite(_saveSession());

  /// Saves what must survive a quit — the session (queue and position) —
  /// and waits for every file write still in flight.
  Future<void> prepareToQuit() async {
    _savedQueueKey = null; // Write the whole session, not just the position.
    await _saveSession();
    await pendingAtomicWrites();
  }

  Future<void> _saveSession() async {
    final store = _sessionStore;
    if (store == null) return;
    _savedPosition = _position;
    final currentRef = _currentTrack?.ref;
    final summaries = _queue.tracks;
    final found = currentRef == null
        ? 0
        : summaries.indexWhere((track) => track.ref == currentRef);
    final index = found < 0 ? 0 : found;
    final key = '$index\n${summaries.map((track) => track.ref).join('\n')}';
    final positionMs = _position.inMilliseconds;
    if (key == _savedQueueKey) return store.savePosition(positionMs);
    _savedQueueKey = key;
    return store.save(queue, index, positionMs: positionMs);
  }

  Future<void> setAgentControlEnabled(bool value) async {
    _agentControl = value;
    if (value) {
      await _startControlServer();
    } else {
      _agentControlError = null;
      await _controlServer.stop();
    }
    _persistSettings();
    _notify();
  }

  Future<void> _startControlServer() async {
    try {
      await _controlServer.start();
      _agentControlError = null;
    } catch (error) {
      DiagnosticLog.record('control API did not start: $error');
      _agentControlError = AppStrings.t('agent.startFailed');
    }
    if (!_isDisposed) _notify();
  }

  /// Plays a track already seen this session, identified by source + item id.
  /// Used by the control API so an agent can play a prior search result.
  Future<bool> playByRef(String sourceId, String itemId) async {
    final key = MediaRef(sourceId: sourceId, itemId: itemId).toString();
    final track = _knownTracks[key];
    if (track == null) return false;
    await play(track);
    return true;
  }

  /// Plays the queue entry at [index] (for the control API).
  Future<bool> playQueueIndex(int index) async {
    final tracks = queue;
    if (index < 0 || index >= tracks.length) return false;
    await play(tracks[index], queueIndex: index);
    return true;
  }

  /// A message for the user that the shell shows once (as a snack bar), or
  /// null. Reading it clears it.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  /// Watches a save of user data: a failure is logged, and reported to the
  /// user once per session (a full disk fails every later save as well).
  void _watchWrite(Future<void>? write) {
    if (write == null) return;
    unawaited(
      write.catchError((Object error) {
        DiagnosticLog.record('save failed: $error');
        if (_storageFailureReported || _isDisposed) return;
        _storageFailureReported = true;
        _notice = AppStrings.t('storage.writeFailed');
        _notify();
      }),
    );
  }
}
