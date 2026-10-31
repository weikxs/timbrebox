import 'package:timbrebox_app/app/plugins/media_extractor_process.dart';
import 'package:timbrebox_app/app/plugins/media_stream_probe.dart';
import 'package:timbrebox_app/app/plugins/youtube_audio_manifest.dart';

/// Timing only, for opt-in real-network diagnostics. Never captures arguments,
/// metadata, addresses or exceptions' raw messages.
final class MediaPhaseMetrics {
  final samples = <Map<String, Object?>>[];
  String? active;
  Future<T> measure<T>(String phase, Future<T> Function() operation) async {
    final watch = Stopwatch()..start();
    active = phase;
    String? failure;
    try {
      return await operation();
    } catch (error) {
      failure = error is MediaExtractionException ? error.code : 'test_error';
      rethrow;
    } finally {
      samples.add({
        'phase': phase,
        'elapsedMs': watch.elapsedMilliseconds,
        'success': failure == null,
        'code': ?failure,
      });
      if (active == phase) active = null;
    }
  }

  MediaExtractionRunner runner() => _Runner(this);
  MediaStreamProbe probe() => _Probe(this);
  YouTubeAudioManifest audio() => _Audio(this);
}

class _Runner implements MediaExtractionRunner {
  _Runner(this.metrics);
  final MediaPhaseMetrics metrics;
  final delegate = PinnedMediaExtractionRunner();
  @override
  Future<String> run(List<String> arguments) =>
      metrics.measure('metadata', () => delegate.run(arguments));
  @override
  void cancel() => delegate.cancel();
  @override
  void dispose() => delegate.dispose();
}

class _Probe implements MediaStreamProbe {
  _Probe(this.metrics);
  final MediaPhaseMetrics metrics;
  final delegate = GuardedMediaStreamProbe();
  @override
  Future<Map<String, Object?>> select(List<Map<String, Object?>> candidates) =>
      metrics.measure('byte_probe', () => delegate.select(candidates));
  @override
  void cancel() => delegate.cancel();
  @override
  void dispose() => delegate.dispose();
}

class _Audio implements YouTubeAudioManifest {
  _Audio(this.metrics);
  final MediaPhaseMetrics metrics;
  final delegate = DartYouTubeAudioManifest();
  @override
  Future<List<Map<String, Object?>>> resolve(String videoId, num duration) =>
      metrics.measure(
        'original_audio',
        () => delegate.resolve(videoId, duration),
      );
  @override
  void cancel() => delegate.cancel();
  @override
  void dispose() => delegate.dispose();
}
