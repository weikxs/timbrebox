import '../model/media_ref.dart';

enum DownloadStatus {
  queued,
  resolving,
  downloading,
  verifying,
  completed,
  failed,
  cancelled,
}

/// Persistent-safe download state. It stores a stable media ref and a
/// relative file key, never an expiring stream URL or provider credentials.
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.ref,
    required this.status,
    this.progress = 0,
    this.relativePath,
    this.errorMessage,
  }) : assert(progress >= 0 && progress <= 1);

  final String id;
  final MediaRef ref;
  final DownloadStatus status;
  final double progress;
  final String? relativePath;
  final String? errorMessage;

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? relativePath,
    String? errorMessage,
  }) => DownloadTask(
    id: id,
    ref: ref,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    relativePath: relativePath ?? this.relativePath,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

/// Small lifecycle boundary for a real platform download implementation.
/// Implementations resolve the stream just before transfer and may emit
/// immutable task snapshots to the UI.
abstract interface class DownloadManager {
  Stream<DownloadTask> get changes;

  DownloadTask? taskFor(MediaRef ref);

  Future<DownloadTask> enqueue(MediaRef ref);

  Future<void> cancel(String taskId);

  Future<void> retry(String taskId);
}
