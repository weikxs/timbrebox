import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/image_cache_limits.dart';

void main() {
  test('the decoded-image cache is capped well below Flutter defaults', () {
    final cache = ImageCache();

    limitImageCache(cache);

    expect(cache.maximumSizeBytes, 32 * 1024 * 1024);
    expect(cache.maximumSize, 300);
  });
}
