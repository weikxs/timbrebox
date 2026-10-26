import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'app/image_cache_limits.dart';
import 'app/timbrebox_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  limitImageCache(PaintingBinding.instance.imageCache);
  MediaKit.ensureInitialized();
  runApp(const TimbreBoxApp());
}
