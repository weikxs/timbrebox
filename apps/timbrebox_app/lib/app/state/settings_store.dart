import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'atomic_file.dart';

/// Persists user preferences (volume, loop, quality, language, toggles) as a
/// small JSON file so they survive restarts.
final class SettingsStore {
  static const _fileName = 'settings.json';

  Future<Map<String, Object?>> load() async {
    final file = await _file();
    if (!await file.exists()) return const {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> save(Map<String, Object?> data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await writeFileAtomically(file, jsonEncode(data));
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }
}
