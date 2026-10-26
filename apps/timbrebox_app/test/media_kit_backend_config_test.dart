import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/state/media_kit_backend.dart';

/// libmpv's defaults in media_kit are sized for video: a 32 MB demuxer cache
/// ahead and another 32 MB behind the playhead.
void main() {
  test('libmpv is set up for audio, with a small demuxer cache', () {
    const configuration = MediaKitBackend.configuration;

    expect(configuration.bufferSize, 8 * 1024 * 1024);
    // media_kit opens with vid=no unless a video view attaches (none does)
    // and no video output at all.
    expect(configuration.vo, 'null');
    expect(MediaKitBackend.mpvProperties, {
      'demuxer-max-back-bytes': '${2 * 1024 * 1024}',
      'vid': 'no',
    });
  });
}
