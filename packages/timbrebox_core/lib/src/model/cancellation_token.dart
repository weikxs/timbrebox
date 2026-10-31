import 'dart:async';

class CancellationToken {
  bool _isCancelled = false;
  Completer<void>? _cancelled;

  /// Created only for callers that need asynchronous cancellation; no polling.
  Future<void> get whenCancelled => _isCancelled
      ? Future<void>.value()
      : (_cancelled ??= Completer<void>()).future;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled?.complete();
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const OperationCancelled();
    }
  }
}

class OperationCancelled implements Exception {
  const OperationCancelled();
}
