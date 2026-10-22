import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Single source of truth for where downloaded audio and the local-music index
/// live: the OS Downloads folder plus a `TimbreBox` subfolder (e.g.
/// `~/Downloads/TimbreBox`) on desktop, falling back to the app documents dir
/// where the platform has no shared Downloads (iOS/Android). The download
/// service, the index store, and the settings screen all resolve through here,
/// so "下载" and "本地音乐" always point at the same place on every platform.
Future<Directory> resolveDownloadDirectory() async {
  Directory? base;
  try {
    base = await getDownloadsDirectory();
  } catch (_) {
    base = null;
  }
  base ??= await getApplicationDocumentsDirectory();
  return Directory('${base.path}/TimbreBox');
}
