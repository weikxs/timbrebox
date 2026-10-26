import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'app/design/software_rendering.dart';
import 'app/image_cache_limits.dart';
import 'app/timbrebox_app.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  limitImageCache(PaintingBinding.instance.imageCache);
  MediaKit.ensureInitialized();
  runApp(
    TimbreBoxApp(
      softwareRendering: isSoftwareRendering(
        isLinux: Platform.isLinux,
        arguments: arguments,
        environment: Platform.environment,
      ),
    ),
  );
}
