import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  test('download task updates lifecycle without changing stable ref', () {
    const ref = MediaRef(sourceId: 'youtube', itemId: 'video-1');
    const task = DownloadTask(
      id: 'task-1',
      ref: ref,
      status: DownloadStatus.resolving,
    );
    final completed = task.copyWith(
      status: DownloadStatus.completed,
      progress: 1,
      relativePath: 'downloads/task-1.m4a',
    );

    expect(completed.ref, ref);
    expect(completed.status, DownloadStatus.completed);
    expect(completed.relativePath, 'downloads/task-1.m4a');
    expect(completed.errorMessage, isNull);
  });
}
