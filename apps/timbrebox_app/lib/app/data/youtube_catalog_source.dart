import 'dart:async';

import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../design/app_strings.dart';
import '../model/catalog_track.dart';
import 'catalog_source.dart';
import 'source_config.dart';
import 'stream_header_proxy.dart';

/// Dedicated, standalone YouTube engine — isolated from the shared adapters.
///
/// youtube_explode resolves a video to a fresh, signed audio-only stream URL on
/// `googlevideo.com`. That URL is directly playable: a plain ranged GET with a
/// browser User-Agent returns `206 Partial Content`, so media_kit (libmpv)
/// streams the DASH/fragmented audio natively and the download service fetches
/// the same URL over HTTP. Playback and download therefore share one resolve
/// path — no temp-file staging. Some videos are region/anti-bot blocked and
/// fail honestly.
final class YouTubeCatalogSource implements CatalogSource {
  YouTubeCatalogSource({yt.YoutubeExplode? client})
    : _yt = client ?? yt.YoutubeExplode();

  final yt.YoutubeExplode _yt;
  final _proxy = StreamHeaderProxy();
  String? _lastQuery;
  yt.VideoSearchList? _lastResults;

  static const _searchTimeout = Duration(seconds: 40);
  static const _resolveTimeout = Duration(seconds: 30);
  static const _browserUserAgent = BuiltInSourceConfig.browserUserAgent;

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    id: 'youtube',
    name: 'YouTube',
    capabilities: const [SourceCapability.search, SourceCapability.streaming],
  );

  // ---- Search (continuation pagination — a real waterfall) ----

  @override
  Future<SearchPage> search(SearchRequest request) async {
    try {
      final yt.VideoSearchList? results;
      if (request.page <= 1 ||
          _lastQuery != request.query ||
          _lastResults == null) {
        results = await _yt.search
            .search(request.query)
            .timeout(_searchTimeout);
        _lastQuery = request.query;
      } else {
        results = await _lastResults!.nextPage().timeout(_searchTimeout);
      }
      if (results == null) {
        _lastResults = null;
        return const SearchPage(items: []);
      }
      _lastResults = results;
      return SearchPage(
        items: [
          for (final video in results)
            TrackSummary(
              ref: MediaRef(sourceId: descriptor.id, itemId: video.id.value),
              title: video.title,
              artist: video.author.isEmpty ? descriptor.name : video.author,
              duration: video.duration,
            ),
        ],
      );
    } on TimeoutException {
      throw SourceException(
        AppStrings.t('source.youtube.searchTimeout'),
        retryable: true,
        code: 'source_timeout',
      );
    } catch (_) {
      throw SourceException(
        AppStrings.t('source.youtube.searchUnavailable'),
        retryable: true,
        code: 'source_error',
      );
    }
  }

  @override
  CatalogTrack toCatalogTrack(TrackSummary summary) => CatalogTrack(
    id: summary.ref.itemId,
    title: summary.title,
    artist: summary.artist,
    sourceId: descriptor.id,
    sourceName: descriptor.name,
    duration: summary.duration ?? Duration.zero,
    quality: AppStrings.t('quality.youtubeAudio'),
  );

  // ---- Playback + download: resolve → fresh signed googlevideo URL ----

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    if (request.ref.sourceId != descriptor.id) {
      throw StateError(AppStrings.t('source.err.refMismatch'));
    }
    request.cancellation.throwIfCancelled();
    final audio = await _bestAudio(request.ref.itemId);
    final isMp4 = audio.container == yt.StreamContainer.mp4;
    // media_kit/ffmpeg can't open the googlevideo URL directly (it omits the
    // Range header that the URL demands → 403), so route it through the local
    // proxy which injects the Range and the browser User-Agent per hop.
    final localUri = await _proxy.publish(audio.url, const {
      'User-Agent': _browserUserAgent,
    }, chunked: true);
    return ResolvedStream(
      uri: localUri,
      mimeType: isMp4 ? 'audio/mp4' : 'audio/webm',
    );
  }

  /// Resolves the highest-bitrate audio-only stream, preferring the mp4 (AAC)
  /// container that both media_kit and AVFoundation handle most reliably.
  Future<yt.AudioOnlyStreamInfo> _bestAudio(String videoId) async {
    final yt.StreamManifest manifest;
    try {
      manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(_resolveTimeout);
    } on TimeoutException {
      throw SourceException(
        AppStrings.t('source.youtube.resolveTimeout'),
        retryable: true,
        code: 'source_timeout',
      );
    } catch (_) {
      throw SourceException(
        AppStrings.t('source.youtube.noAudio'),
        retryable: false,
        code: 'source_stream_unavailable',
      );
    }
    final audios = manifest.audioOnly.toList()
      ..sort(
        (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
      );
    if (audios.isEmpty) {
      throw SourceException(
        AppStrings.t('source.youtube.noAudioStream'),
        retryable: false,
        code: 'source_stream_unavailable',
      );
    }
    return audios.firstWhere(
      (info) => info.container == yt.StreamContainer.mp4,
      orElse: () => audios.first,
    );
  }
}
