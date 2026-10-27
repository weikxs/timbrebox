import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _Malloc = Pointer<Uint8> Function(int size);
typedef _MallocNative = Pointer<Uint8> Function(IntPtr size);
typedef _Free = void Function(Pointer<Uint8> pointer);
typedef _FreeNative = Void Function(Pointer<Uint8> pointer);

/// The few C library calls Dart has no API for, on macOS and Linux. Each
/// returns false (or throws [UnsupportedError] on Windows) instead of
/// crashing when the call is unavailable.
abstract final class Libc {
  static final _library = DynamicLibrary.process();
  static final _malloc = _library.lookupFunction<_MallocNative, _Malloc>(
    'malloc',
  );
  static final _free = _library.lookupFunction<_FreeNative, _Free>('free');

  /// Sets the file mode of [path] (e.g. `0x180` for 0600).
  static bool chmod(String path, int mode) {
    _requirePosix();
    // mode_t is 16 bits on Apple platforms and 32 bits on Linux.
    final int Function(Pointer<Uint8>, int) call =
        Platform.isMacOS || Platform.isIOS
        ? _library.lookupFunction<
            Int32 Function(Pointer<Uint8>, Uint16),
            int Function(Pointer<Uint8>, int)
          >('chmod')
        : _library.lookupFunction<
            Int32 Function(Pointer<Uint8>, Uint32),
            int Function(Pointer<Uint8>, int)
          >('chmod');
    return _withCString(path, (cPath) => call(cPath, mode)) == 0;
  }

  /// Sets an environment variable of this process (for native libraries
  /// that read their options from it).
  static bool setenv(String name, String value) {
    _requirePosix();
    final call = _library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32),
          int Function(Pointer<Uint8>, Pointer<Uint8>, int)
        >('setenv');
    return _withCString(
          name,
          (cName) => _withCString(value, (cValue) => call(cName, cValue, 1)),
        ) ==
        0;
  }

  static void _requirePosix() {
    if (Platform.isWindows) throw UnsupportedError('No POSIX libc here.');
  }

  /// Runs [use] with [value] as a NUL-terminated UTF-8 string, then frees it.
  static T _withCString<T>(String value, T Function(Pointer<Uint8>) use) {
    final bytes = utf8.encode(value);
    final pointer = _malloc(bytes.length + 1);
    if (pointer == nullptr) throw const OutOfMemoryError();
    try {
      pointer.asTypedList(bytes.length + 1)
        ..setAll(0, bytes)
        ..[bytes.length] = 0;
      return use(pointer);
    } finally {
      _free(pointer);
    }
  }
}
