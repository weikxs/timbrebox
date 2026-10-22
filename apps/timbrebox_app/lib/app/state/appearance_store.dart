import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists the user's appearance choices: the selected built-in theme id and
/// an optional custom background skin image.
///
/// The picked image is copied into the app support directory so it survives
/// restarts. Only one skin exists at a time; each save replaces the previous
/// one with a freshly-named file (so Flutter's image cache never serves a stale
/// bitmap for a reused path). The theme id lives in a small text file alongside.
final class AppearanceStore {
  static const _skinPrefix = 'skin-';
  static const _themeFileName = 'theme.txt';

  Future<String?> loadThemeId() async {
    final file = File('${(await _directory()).path}/$_themeFileName');
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  Future<void> saveThemeId(String id) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    await File('${directory.path}/$_themeFileName').writeAsString(id, flush: true);
  }

  /// Returns the current skin file, or null if none has been set.
  Future<File?> loadSkin() async {
    final directory = await _directory();
    if (!await directory.exists()) return null;
    final skins = await _skins(directory);
    return skins.isEmpty ? null : skins.first;
  }

  /// Copies [sourcePath] into the app directory and returns the stored file.
  Future<File> saveSkin(String sourcePath) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    for (final existing in await _skins(directory)) {
      await existing.delete();
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final target = File(
      '${directory.path}/$_skinPrefix$stamp${_extension(sourcePath)}',
    );
    return File(sourcePath).copy(target.path);
  }

  Future<void> clearSkin() async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    for (final skin in await _skins(directory)) {
      await skin.delete();
    }
  }

  Future<Directory> _directory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/appearance');
  }

  Future<List<File>> _skins(Directory directory) async {
    final entries = await directory.list().toList();
    return entries
        .whereType<File>()
        .where((file) => file.uri.pathSegments.last.startsWith(_skinPrefix))
        .toList();
  }

  String _extension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot).toLowerCase();
  }
}
