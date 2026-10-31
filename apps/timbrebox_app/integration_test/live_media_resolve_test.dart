import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timbrebox_app/app/plugins/media_extraction_error.dart';
import 'package:timbrebox_app/app/plugins/platform_media_backend.dart';

import 'support/media_phase_metrics.dart';

/// Explicit same-reference diagnostics. Byte verification is not audio playback.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('LIVE_MEDIA_REFERENCES_BASE64');
  test(
    're-resolve requested stable references with real byte verification',
    () async {
      final references = jsonDecode(utf8.decode(base64Decode(encoded))) as List;
      expect(references.length, lessThanOrEqualTo(6));
      for (var index = 0; index < references.length; index++) {
        // Each sample owns its metrics; a cancelled phase may complete late.
        final metrics = MediaPhaseMetrics();
        final backend = DesktopPlatformMediaBackend(
          runner: metrics.runner(),
          probe: metrics.probe(),
          youtubeAudio:
              const bool.fromEnvironment('TIMBREBOX_YOUTUBE_DART_AUDIO_TEST')
              ? metrics.audio()
              : null,
        );
        addTearDown(backend.dispose);
        final request = Map<String, Object?>.from(references[index] as Map);
        final clock = Stopwatch()..start();
        try {
          final result = await backend.call({
            ...request,
            'operation': 'resolve',
          });
          final media = result['media'] as Map;
          // ignore: avoid_print
          print(
            jsonEncode({
              'referenceIndex': index,
              'resolved': true,
              'phases': metrics.samples,
              'mime': media['mimeType'],
              'boundedRanges': media['boundedRanges'],
              'elapsedMs': clock.elapsedMilliseconds,
              'playbackAccepted': false,
            }),
          );
        } on MediaExtractionException catch (error) {
          // ignore: avoid_print
          print(
            jsonEncode({
              'referenceIndex': index,
              'resolved': false,
              'phases': metrics.samples,
              'activePhase': metrics.active,
              'code': error.code,
              'elapsedMs': clock.elapsedMilliseconds,
              'playbackAccepted': false,
            }),
          );
        } finally {
          backend.dispose();
        }
      }
    },
    skip: encoded.isEmpty,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
