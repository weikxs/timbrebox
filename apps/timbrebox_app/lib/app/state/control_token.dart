import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../native/libc.dart';

/// The request header that carries the control API token.
const controlTokenHeader = 'X-TimbreBox-Token';

/// The control API's per-run token, kept in a file only the user can read.
///
/// Each start of the API writes a new random token to `control-token` in
/// the app's support directory (mode 0600 on macOS and Linux; on Windows the
/// per-user AppData folder is private already). The CLI, the MCP server and
/// `tools/timbrebox-ctl` read it from there and send it with every request,
/// so another user's process — or anything that cannot read the user's
/// files — cannot drive the player.
final class ControlTokenFile {
  ControlTokenFile({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const fileName = 'control-token';

  final Future<Directory> Function() _directory;
  final _random = Random.secure();

  /// Where the token is (or will be) written.
  Future<File> file() async => File('${(await _directory()).path}/$fileName');

  /// Writes a fresh 256-bit token and returns it. The file is made private
  /// while still empty, then filled and renamed into place, so the token is
  /// never readable by others, even for a moment. Throws when the file
  /// cannot be made private.
  Future<String> issue() async {
    final target = await file();
    await target.parent.create(recursive: true);
    final token = _hex(32);
    final temporary = File('${target.path}.${_hex(6)}.tmp');
    await temporary.create(exclusive: true);
    try {
      if (!Platform.isWindows && !Libc.chmod(temporary.path, _userOnly)) {
        throw FileSystemException(
          'Could not make the control token private',
          temporary.path,
        );
      }
      await temporary.writeAsString(token, flush: true);
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    return token;
  }

  /// Deletes the token file (the API stopped).
  Future<void> revoke() async {
    try {
      final target = await file();
      if (await target.exists()) await target.delete();
    } on FileSystemException {
      // Best effort: the next start replaces it anyway.
    }
  }

  /// rw------- (0600).
  static const _userOnly = 0x180;

  String _hex(int bytes) => [
    for (var i = 0; i < bytes; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Compares [given] with [expected] in time independent of where they first
/// differ.
bool controlTokenMatches(String? given, String expected) {
  if (expected.isEmpty) return false; // No token issued: nothing matches.
  if (given == null || given.length != expected.length) return false;
  var difference = 0;
  for (var i = 0; i < expected.length; i++) {
    difference |= given.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return difference == 0;
}
