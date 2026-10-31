import 'package:flutter/material.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../state/app_controller.dart';
import '../widgets/glass_panel.dart';
import '../widgets/track_list.dart';

class SearchView extends StatefulWidget {
  const SearchView({required this.controller, super.key});
  final AppController controller;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  String? _selectedSourceId;
  final _scroll = ScrollController();

  /// The source + result count the last autofill check ran for.
  String? _autofillCheckedFor;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.controller.visibleSearchSources;
    final selectedSource = _sourceFor(sources);
    final query = widget.controller.query;
    final emptyResults =
        query.isNotEmpty &&
        sources.isEmpty &&
        widget.controller.searchableSources.isNotEmpty;

    _scheduleAutofill(selectedSource);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) => _onScroll(notification, selectedSource),
      child: CustomScrollView(
        controller: _scroll,
        key: const PageStorageKey('search-workspace'),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(
            child: emptyResults
                ? const SizedBox.shrink()
                : _SourceTabs(
                    sources: sources,
                    selectedSourceId: selectedSource?.id,
                    onSelected: (sourceId) =>
                        setState(() => _selectedSourceId = sourceId),
                  ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 12),
              child: _ResultHeader(
                query: query,
                emptyResults: emptyResults,
                source: selectedSource,
                isSearching:
                    selectedSource != null &&
                    widget.controller.isSearchingSource(selectedSource.id),
              ),
            ),
          ),
          if (query.isEmpty && widget.controller.searchHistory.isNotEmpty)
            SliverToBoxAdapter(
              child: _RecentSearches(controller: widget.controller),
            ),
          _resultSliver(widget.controller, selectedSource),
          SliverToBoxAdapter(
            child: _LoadMoreFooter(
              controller: widget.controller,
              source: selectedSource,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
      ),
    );
  }

  bool _onScroll(ScrollNotification notification, SourceDescriptor? source) {
    if (source == null) return false;
    final controller = widget.controller;
    if (!controller.hasMoreResults(source.id)) return false;
    if (controller.isLoadingMore(source.id)) return false;
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 500) {
      controller.loadMore(source.id);
    }
    return false;
  }

  /// Checks once per new page (or tab) whether the list is still too short to
  /// scroll, instead of after every build.
  void _scheduleAutofill(SourceDescriptor? source) {
    if (source == null) return;
    final controller = widget.controller;
    if (!controller.hasMoreResults(source.id)) return;
    if (controller.isLoadingMore(source.id)) return;
    final key = '${source.id}:${controller.searchResultCount(source.id)}';
    if (key == _autofillCheckedFor) return;
    _autofillCheckedFor = key;
    WidgetsBinding.instance.addPostFrameCallback((_) => _autofill(source));
  }

  /// Keeps loading pages until the list is long enough to scroll (or the source
  /// is exhausted), so a short first page still becomes a real waterfall.
  void _autofill(SourceDescriptor source) {
    if (!mounted || !_scroll.hasClients) return;
    final controller = widget.controller;
    if (!controller.hasMoreResults(source.id)) return;
    if (controller.isLoadingMore(source.id)) return;
    if (_scroll.position.maxScrollExtent <= 0) {
      controller.loadMore(source.id);
    }
  }

  SourceDescriptor? _sourceFor(List<SourceDescriptor> sources) {
    if (sources.isEmpty) return null;
    for (final source in sources) {
      if (source.id == _selectedSourceId) return source;
    }
    return sources.firstWhere(
      (source) => widget.controller.searchResultCount(source.id) > 0,
      orElse: () => sources.first,
    );
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppStrings.t('search.recent'),
              style: TextStyle(
                color: TimbreColors.gold,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: controller.clearSearchHistory,
              child: Text(AppStrings.t('search.clearRecent')),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final query in controller.searchHistory)
              ActionChip(
                label: Text(query),
                onPressed: () => controller.search(query),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    ),
  );
}

class _SourceTabs extends StatelessWidget {
  const _SourceTabs({
    required this.sources,
    required this.selectedSourceId,
    required this.onSelected,
  });

  final List<SourceDescriptor> sources;
  final String? selectedSourceId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return _SearchNotice(
        icon: Icons.extension_off_rounded,
        title: AppStrings.t('search.noSourcesTitle'),
        detail: AppStrings.t('search.noSourcesDetail'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.t('search.sourceLabel'),
          style: TextStyle(color: TimbreColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sources.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final source = sources[index];
              return _SourceTab(
                label: source.name,
                selected: selectedSourceId == source.id,
                onPressed: () => onSelected(source.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SourceTab extends StatelessWidget {
  const _SourceTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: label,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? TimbreColors.ink : TimbreColors.muted,
        backgroundColor: selected
            ? TimbreColors.gold.withValues(alpha: .12)
            : TimbreColors.panel,
        side: BorderSide(
          color: selected ? TimbreColors.gold : TimbreColors.line,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const StadiumBorder(),
      ),
      child: Text(label),
    ),
  );
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    required this.query,
    required this.source,
    required this.isSearching,
    required this.emptyResults,
  });

  final bool emptyResults;
  final String query;
  final SourceDescriptor? source;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final title = query.isEmpty
        ? AppStrings.t('search.startTitle')
        : '“$query”';
    final sourceName = source?.name;
    final detail = sourceName == null
        ? AppStrings.t(
            emptyResults ? 'search.noMatchesTitle' : 'search.sourceDisabled',
          )
        : isSearching
        ? AppStrings.t('search.searchingFmt').replaceFirst('{name}', sourceName)
        : AppStrings.t('search.fromFmt').replaceFirst('{name}', sourceName);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontFamily: 'Georgia'),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(color: TimbreColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (isSearching)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: TimbreColors.gold,
            ),
          ),
      ],
    );
  }
}

/// The selected source's results as a lazily built sliver, or a notice.
Widget _resultSliver(AppController controller, SourceDescriptor? source) {
  Widget notice(IconData icon, String title, String detail) =>
      SliverToBoxAdapter(
        child: _SearchNotice(icon: icon, title: title, detail: detail),
      );
  if (controller.searchError case final error?) {
    return notice(
      Icons.wifi_off_rounded,
      AppStrings.t('search.errorTitle'),
      error,
    );
  }
  if (source == null &&
      controller.query.isNotEmpty &&
      controller.searchableSources.isNotEmpty &&
      !controller.isSearching) {
    return notice(
      Icons.search_off_rounded,
      AppStrings.t('search.noMatchesTitle'),
      AppStrings.t('search.noMatchesDetail'),
    );
  }
  if (source == null) {
    return notice(
      Icons.tune_rounded,
      AppStrings.t('search.pickSourceTitle'),
      AppStrings.t('search.pickSourceDetail'),
    );
  }
  if (controller.query.isEmpty) {
    return notice(
      Icons.travel_explore_rounded,
      AppStrings.t('search.readyTitle'),
      AppStrings.t('search.readyDetailFmt').replaceFirst('{name}', source.name),
    );
  }
  if (controller.searchFailureFor(source.id) case final failure?) {
    return notice(
      Icons.cloud_off_rounded,
      AppStrings.t(
        'search.sourceUnavailableFmt',
      ).replaceFirst('{name}', source.name),
      failure.message,
    );
  }
  final tracks = controller.searchResultsFor(source.id);
  if (tracks.isEmpty && controller.isSearchingSource(source.id)) {
    // Other sources may already show results; the header shows this one is
    // still searching, so no "no match" yet.
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
  return SliverTrackList(
    tracks: tracks,
    controller: controller,
    emptyTitle: AppStrings.t(
      'search.noMatchFmt',
    ).replaceFirst('{name}', source.name),
    emptyDetail: AppStrings.t('search.noMatchDetail'),
  );
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.controller, required this.source});

  final AppController controller;
  final SourceDescriptor? source;

  @override
  Widget build(BuildContext context) {
    final selected = source;
    if (selected == null || controller.query.isEmpty) {
      return const SizedBox.shrink();
    }
    if (controller.searchResultsFor(selected.id).isEmpty) {
      return const SizedBox.shrink();
    }
    if (controller.isLoadingMore(selected.id)) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: TimbreColors.gold,
            ),
          ),
        ),
      );
    }
    if (!controller.hasMoreResults(selected.id)) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            AppStrings.t('search.allLoaded'),
            style: TextStyle(color: TimbreColors.muted, fontSize: 11),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: OutlinedButton(
          onPressed: () => controller.loadMore(selected.id),
          style: OutlinedButton.styleFrom(
            foregroundColor: TimbreColors.gold,
            side: BorderSide(color: TimbreColors.line),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          ),
          child: Text(AppStrings.t('search.loadMore')),
        ),
      ),
    );
  }
}

class _SearchNotice extends StatelessWidget {
  const _SearchNotice({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => GlassPanel(
    radius: 18,
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        Icon(icon, color: TimbreColors.gold),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(color: TimbreColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
