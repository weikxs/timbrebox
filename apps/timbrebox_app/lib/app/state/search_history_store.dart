import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists recent search queries (plain strings only) so they survive restarts.
abstract interface class SearchHistoryStore {
  Future<List<String>> load();
  Future<void> save(List<String> queries);
}

final class FileSearchHistoryStore implements SearchHistoryStore {
  static const _fileName = 'search-history.json';

  @override
  Future<List<String>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final list = jsonDecode(await file.readAsString()) as List? ?? const [];
      return [for (final entry in list) '$entry'];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<String> queries) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(queries), flush: true);
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }
}
