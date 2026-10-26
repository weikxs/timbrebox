import 'cancellation_token.dart';
import 'media_ref.dart';

class SourceFailure {
  const SourceFailure(
    this.message, {
    required this.retryable,
    this.code = 'source_error',
  });

  final String message;
  final bool retryable;
  final String code;
}

class SourceException implements Exception {
  const SourceException(
    this.message, {
    required this.retryable,
    this.code = 'source_error',
  });

  final String message;
  final bool retryable;
  final String code;

  /// The message alone: it is written for the user and shown as is.
  @override
  String toString() => message;
}

class SearchRequest {
  SearchRequest({
    required String query,
    required this.cancellation,
    this.page = 1,
  }) : query = query.trim() {
    if (this.query.isEmpty) {
      throw ArgumentError.value(
        query,
        'query',
        'Search query cannot be empty.',
      );
    }
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'Page must be 1 or greater.');
    }
  }

  final String query;
  final CancellationToken cancellation;

  /// 1-based page index. Sources that cannot paginate return an empty page for
  /// any value greater than 1 so the caller stops requesting more.
  final int page;
}

class SearchPage {
  const SearchPage({required this.items, this.nextCursor});

  final List<TrackSummary> items;
  final String? nextCursor;
}

/// The result of one source in an all-source search.
///
/// Keeping this status beside the items prevents a slow or unavailable source
/// from being mistaken for a global empty result.
enum SourceSearchStatus { success, empty, failure, cancelled }

class SearchBatch {
  const SearchBatch({required this.query, required this.groups});

  final String query;
  final List<SourceSearchGroup> groups;

  bool get hasItems => groups.any((group) => group.items.isNotEmpty);
  bool get hasFailures => groups.any((group) => group.failure != null);

  SourceSearchGroup? groupFor(String sourceId) {
    for (final group in groups) {
      if (group.sourceId == sourceId) return group;
    }
    return null;
  }
}

class SourceSearchGroup {
  const SourceSearchGroup({
    required this.sourceId,
    required this.status,
    this.page,
    this.failure,
  });

  final String sourceId;
  final SourceSearchStatus status;
  final SearchPage? page;
  final SourceFailure? failure;

  List<TrackSummary> get items => page?.items ?? const [];
}

class TrackSummary {
  const TrackSummary({
    required this.ref,
    required this.title,
    required this.artist,
    this.duration,
  });

  final MediaRef ref;
  final String title;
  final String artist;
  final Duration? duration;
}

class StreamCandidate {
  const StreamCandidate({
    required this.ref,
    required this.id,
    required this.label,
  });

  final MediaRef ref;
  final String id;
  final String label;
}
