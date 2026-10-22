class CancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
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
