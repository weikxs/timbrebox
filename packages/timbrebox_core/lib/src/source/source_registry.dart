import 'dart:async';

import '../model/cancellation_token.dart';
import '../model/search_models.dart';
import '../model/source_descriptor.dart';
import 'music_source.dart';

class SourceRegistry {
  SourceRegistry(Iterable<MusicSource> sources) : _sources = _index(sources);

  static Map<String, MusicSource> _index(Iterable<MusicSource> sources) {
    final list = sources.toList(growable: false);
    final indexed = {for (final source in list) source.descriptor.id: source};
    if (indexed.length != list.length) {
      throw ArgumentError('Source identifiers must be unique.');
    }
    return indexed;
  }

  static const maxConcurrentSearches = 2;

  final Map<String, MusicSource> _sources;
  final Set<String> _disabled = {};

  Iterable<SourceDescriptor> get descriptors =>
      _sources.values.map((source) => source.descriptor);

  Iterable<SourceDescriptor> descriptorsFor(SourceCapability capability) =>
      _sources.values
          .map((source) => source.descriptor)
          .where((descriptor) => descriptor.supports(capability));

  Iterable<SourceDescriptor> get enabledDescriptors => _sources.values
      .map((source) => source.descriptor)
      .where((descriptor) => isEnabled(descriptor.id));

  void setEnabled(String sourceId, bool enabled) {
    if (!_sources.containsKey(sourceId)) {
      throw ArgumentError.value(sourceId, 'sourceId', 'Unknown source.');
    }
    enabled ? _disabled.remove(sourceId) : _disabled.add(sourceId);
  }

  bool isEnabled(String sourceId) => !_disabled.contains(sourceId);

  Stream<SourceSearchResult> searchAll(SearchRequest request) async* {
    final searchable = _sources.values
        .where((source) => isEnabled(source.descriptor.id))
        .where((source) => source.descriptor.supports(SourceCapability.search))
        .toList(growable: false);
    final active = <_SearchJob>[];
    var next = 0;

    while (!request.cancellation.isCancelled &&
        (next < searchable.length || active.isNotEmpty)) {
      while (!request.cancellation.isCancelled &&
          active.length < maxConcurrentSearches &&
          next < searchable.length) {
        final source = searchable[next++];
        active.add(_SearchJob(source.descriptor.id, _search(source, request)));
      }
      if (active.isEmpty) break;

      final result = await Future.any(active.map((job) => job.result));
      active.removeWhere((job) => job.sourceId == result.sourceId);
      if (!request.cancellation.isCancelled && !result.wasCancelled) {
        yield result;
      }
    }
  }

  Future<SearchBatch> searchBatch(SearchRequest request) async {
    final results = await searchAll(request).toList();
    request.cancellation.throwIfCancelled();
    return SearchBatch(
      query: request.query,
      groups: [for (final result in results) result.group],
    );
  }

  Future<SourceSearchResult> _search(
    MusicSource source,
    SearchRequest request,
  ) async {
    try {
      request.cancellation.throwIfCancelled();
      final page = await source.search(request);
      request.cancellation.throwIfCancelled();
      return SourceSearchResult.success(source.descriptor.id, page);
    } on OperationCancelled {
      return SourceSearchResult.cancelled(source.descriptor.id);
    } on TimeoutException {
      return SourceSearchResult.failure(
        source.descriptor.id,
        const SourceFailure('Source timed out.', retryable: true),
      );
    } on SourceException catch (error) {
      return SourceSearchResult.failure(
        source.descriptor.id,
        SourceFailure(
          error.message,
          retryable: error.retryable,
          code: error.code,
        ),
      );
    } catch (_) {
      return SourceSearchResult.failure(
        source.descriptor.id,
        const SourceFailure('Source request failed.', retryable: false),
      );
    }
  }
}

class SourceSearchResult {
  const SourceSearchResult._({
    required this.sourceId,
    this.page,
    this.failure,
    this.wasCancelled = false,
  });

  factory SourceSearchResult.success(String sourceId, SearchPage page) =>
      SourceSearchResult._(sourceId: sourceId, page: page);

  factory SourceSearchResult.failure(String sourceId, SourceFailure failure) =>
      SourceSearchResult._(sourceId: sourceId, failure: failure);

  factory SourceSearchResult.cancelled(String sourceId) =>
      SourceSearchResult._(sourceId: sourceId, wasCancelled: true);

  final String sourceId;
  final SearchPage? page;
  final SourceFailure? failure;
  final bool wasCancelled;

  SourceSearchStatus get status {
    if (wasCancelled) return SourceSearchStatus.cancelled;
    if (failure != null) return SourceSearchStatus.failure;
    if (page?.items.isEmpty ?? true) return SourceSearchStatus.empty;
    return SourceSearchStatus.success;
  }

  SourceSearchGroup get group => SourceSearchGroup(
    sourceId: sourceId,
    status: status,
    page: page,
    failure: failure,
  );
}

class _SearchJob {
  const _SearchJob(this.sourceId, this.result);

  final String sourceId;
  final Future<SourceSearchResult> result;
}
