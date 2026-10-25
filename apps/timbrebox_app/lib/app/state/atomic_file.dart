import 'dart:io';

final _pendingWrites = <String, Future<void>>{};
final _latestContents = <String, String>{};

/// Replaces [file]'s contents in one step: the data goes to a temporary file
/// next to it, which is then renamed over the original. A crash mid-write
/// leaves the old file intact instead of a truncated one.
///
/// Writes to the same path run one after another, so quick successive saves
/// (dragging the volume slider) cannot interleave. A write that is still
/// queued when a newer one arrives is skipped: only the latest contents reach
/// the disk, and the last call always wins.
Future<void> writeFileAtomically(File file, String contents) {
  final path = file.absolute.path;
  _latestContents[path] = contents;
  final previous = _pendingWrites[path] ?? Future<void>.value();
  final write = previous.catchError((Object _) {}).then((_) {
    final latest = _latestContents.remove(path);
    return latest == null ? null : _replace(file, latest);
  });
  _pendingWrites[path] = write;
  return write.whenComplete(() {
    if (identical(_pendingWrites[path], write)) _pendingWrites.remove(path);
  });
}

Future<void> _replace(File file, String contents) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(contents, flush: true);
  await temporary.rename(file.path);
}
