import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import '../state/app_controller.dart';

/// A lyric that follows playback: the line playing now is highlighted and
/// kept in view, and tapping a line seeks there. It follows the position
/// notifier, which changes once per shown second. A lyric without time
/// stamps is shown as plain text, with a note that it cannot follow.
class LyricsView extends StatefulWidget {
  const LyricsView({
    required this.controller,
    required this.lyric,
    this.scrollController,
    super.key,
  });

  final AppController controller;
  final Lyric lyric;
  final ScrollController? scrollController;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _currentKey = GlobalKey();
  var _shownIndex = -1;

  @override
  Widget build(BuildContext context) {
    final lyric = widget.lyric;
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.controller.positionListenable,
      builder: (context, position, _) {
        final current = lyric.indexAt(position);
        if (current != _shownIndex) {
          _shownIndex = current;
          WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
        }
        return ListView(
          controller: widget.scrollController,
          children: [
            if (!lyric.isSynced)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  AppStrings.t('player.lyricsUnsynced'),
                  style: TextStyle(color: TimbreColors.muted, fontSize: 12),
                ),
              ),
            for (var index = 0; index < lyric.lines.length; index++)
              _line(lyric.lines[index], isCurrent: index == current),
          ],
        );
      },
    );
  }

  Widget _line(LyricLine line, {required bool isCurrent}) {
    final text = Text(
      line.text,
      key: isCurrent ? _currentKey : null,
      style: TextStyle(
        fontSize: isCurrent ? 16 : 15,
        height: 1.7,
        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
        color: isCurrent ? TimbreColors.gold : TimbreColors.ink,
      ),
    );
    if (!widget.lyric.isSynced) return text;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => widget.controller.seek(line.time),
      child: text,
    );
  }

  /// Keeps the current line in view (a third of the way down).
  void _reveal() {
    final context = _currentKey.currentContext;
    if (!mounted || context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: .35,
      duration: const Duration(milliseconds: 250),
    );
  }
}

/// Opens a bottom sheet with the current track's lyric (plugin-provided),
/// synced to playback when it has time stamps.
void showLyricsSheet(BuildContext context, AppController controller) {
  final title = controller.currentTrack?.title ?? AppStrings.t('player.lyrics');
  // Resolve once — the sheet's builder runs every drag frame, so calling
  // currentLyric() inside it would re-fetch continuously.
  final lyricFuture = controller.currentLyric();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: TimbreColors.canvasRaised,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .9,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: FutureBuilder<String?>(
          future: lyricFuture,
          builder: (context, snapshot) {
            final Widget body;
            final lyric = Lyric.parse(snapshot.data ?? '');
            if (snapshot.connectionState != ConnectionState.done) {
              body = const Center(child: CircularProgressIndicator());
            } else if (lyric.lines.isEmpty) {
              body = Center(
                child: Text(
                  AppStrings.t('player.noLyrics'),
                  style: TextStyle(color: TimbreColors.muted),
                ),
              );
            } else {
              body = LyricsView(
                controller: controller,
                lyric: lyric,
                scrollController: scrollController,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 20),
                ),
                const SizedBox(height: 12),
                Expanded(child: body),
              ],
            );
          },
        ),
      ),
    ),
  );
}
