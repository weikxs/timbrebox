import 'dart:io';
import 'dart:math';

import '../native/libc.dart';

/// rw------- (0600).
const userOnlyFileMode = 0x180;

final _random = Random.secure();

/// Writes [contents] to [target] so that only the user can read it, even for
/// a moment: a new file is made private while still empty (mode 0600 on
/// macOS, Linux, Android and iOS; on Windows the per-user AppData folder is
/// private already), then filled and renamed into place. Throws when the
/// file cannot be made private, leaving [target] as it was.
Future<void> writePrivateFile(File target, String contents) async {
  await target.parent.create(recursive: true);
  final suffix = _random.nextInt(1 << 32).toRadixString(16);
  final temporary = File('${target.path}.$suffix.tmp');
  await temporary.create(exclusive: true);
  try {
    if (!Platform.isWindows && !Libc.chmod(temporary.path, userOnlyFileMode)) {
      throw FileSystemException(
        'Could not make the file private',
        temporary.path,
      );
    }
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}
