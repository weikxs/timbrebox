import 'dart:io';

/// The file name the app writes its control API token to, in its support
/// directory (user-only, new each run).
const controlTokenFileName = 'control-token';

/// The request header that carries the token.
const controlTokenHeader = 'X-TimbreBox-Token';

const _macBundleId = 'io.timbrebox.timbreboxApp';
const _linuxAppId = 'io.timbrebox.timbrebox_app';
const _linuxBinary = 'timbrebox_app';

/// Where the running app may keep its token on [os] (default: this one), in
/// the order to try: macOS's sandbox container first, then its plain support
/// folder; Linux's XDG data home; Windows's roaming AppData.
List<String> controlTokenPaths(Map<String, String> environment, {String? os}) {
  final home = environment['HOME'] ?? '';
  switch (os ?? Platform.operatingSystem) {
    case 'macos':
      return [
        '$home/Library/Containers/$_macBundleId/Data/Library/'
            'Application Support/$_macBundleId/$controlTokenFileName',
        '$home/Library/Application Support/$_macBundleId/$controlTokenFileName',
      ];
    case 'linux':
      final dataHome = environment['XDG_DATA_HOME']?.isNotEmpty == true
          ? environment['XDG_DATA_HOME']!
          : '$home/.local/share';
      return [
        '$dataHome/$_linuxAppId/$controlTokenFileName',
        '$dataHome/$_linuxBinary/$controlTokenFileName',
      ];
    case 'windows':
      final appData = environment['APPDATA'] ?? '';
      return ['$appData\\io.timbrebox\\TimbreBox\\$controlTokenFileName'];
    default:
      return const [];
  }
}

/// The running app's control token: `TIMBREBOX_TOKEN` if set, else the file
/// named by `TIMBREBOX_TOKEN_FILE`, else the first of [controlTokenPaths]
/// that exists. Null when none is found (the app is not running, or Agent
/// control is off).
String? readControlToken({Map<String, String>? environment, String? os}) {
  final env = environment ?? Platform.environment;
  final direct = env['TIMBREBOX_TOKEN']?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final named = env['TIMBREBOX_TOKEN_FILE'];
  final candidates = named != null && named.isNotEmpty
      ? [named]
      : controlTokenPaths(env, os: os);
  for (final path in candidates) {
    try {
      final token = File(path).readAsStringSync().trim();
      if (token.isNotEmpty) return token;
    } on FileSystemException {
      // Not there (or not readable): try the next place.
    }
  }
  return null;
}
