import 'package:flutter/painting.dart';

/// Decoded images kept for reuse: Flutter's defaults (1000 images, 100 MB)
/// suit photo apps. TimbreBox shows small covers decoded at their shown size,
/// so 32 MB holds every cover on screen with room for scrolling back.
const imageCacheMaxBytes = 32 * 1024 * 1024;
const imageCacheMaxImages = 300;

void limitImageCache(ImageCache cache) {
  cache
    ..maximumSizeBytes = imageCacheMaxBytes
    ..maximumSize = imageCacheMaxImages;
}
