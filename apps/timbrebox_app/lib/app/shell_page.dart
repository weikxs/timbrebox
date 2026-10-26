import 'dart:io';

import 'package:flutter/material.dart';
import 'design/app_strings.dart';
import 'design/timbre_colors.dart';
import 'state/app_controller.dart';
import 'views/home_view.dart';
import 'views/hot_view.dart';
import 'views/library_views.dart';
import 'views/search_view.dart';
import 'widgets/mini_player.dart';
import 'widgets/settings_view.dart';
import 'widgets/side_navigation.dart';
import 'widgets/top_bar.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  List<String> get _sections => [
    AppStrings.t('nav.home'),
    AppStrings.t('nav.search'),
    AppStrings.t('nav.hot'),
    AppStrings.t('nav.myMusic'),
    AppStrings.t('nav.localMusic'),
    AppStrings.t('nav.recent'),
    AppStrings.t('nav.settings'),
  ];
  var _activeIndex = 0;
  late final AppController _controller = widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_showNotice);
  }

  @override
  void dispose() {
    _controller.removeListener(_showNotice);
    super.dispose();
  }

  /// Shows a one-off message from the controller (e.g. a failed save).
  void _showNotice() {
    final notice = _controller.takeNotice();
    if (notice == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(notice)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
        body: _Background(
          skinPath: _controller.skinImagePath,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 16,
                    12,
                    compact ? 12 : 16,
                    14,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (!compact) ...[
                              SideNavigation(
                                activeIndex: _activeIndex,
                                onSelected: _select,
                                controller: _controller,
                              ),
                              const SizedBox(width: 16),
                            ],
                            Expanded(
                              child: Column(
                                children: [
                                  TopBar(
                                    sectionName: _sections[_activeIndex],
                                    compact: compact,
                                    activeIndex: _activeIndex,
                                    sections: _sections,
                                    onSectionSelected: _select,
                                    onSearch: (query) {
                                      _controller.search(query);
                                      _select(1);
                                    },
                                  ),
                                  Expanded(child: _pageFor(_activeIndex)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      MiniPlayer(controller: _controller),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _select(int index) => setState(() => _activeIndex = index);

  Widget _pageFor(int index) => switch (index) {
    0 => HomeView(controller: _controller, onOpenSearch: () => _select(1)),
    1 => SearchView(
      key: ValueKey('search-${_controller.query}'),
      controller: _controller,
    ),
    2 => HotView(controller: _controller),
    3 => LibraryView(controller: _controller),
    4 => DownloadsView(controller: _controller),
    5 => RecentView(controller: _controller),
    6 => SettingsView(controller: _controller),
    _ => const SizedBox.shrink(),
  };
}

/// The app background: the built-in gradient, or the user's skin image dimmed
/// under a scrim so panels and text stay legible over any picture.
class _Background extends StatelessWidget {
  const _Background({required this.skinPath, required this.child});

  final String? skinPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = skinPath;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [TimbreColors.canvasRaised, TimbreColors.canvas],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: path == null
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(path),
                  // Decode no larger than the display (a photo can be many
                  // times that). The display, not the window, so resizing
                  // the window does not decode the image again.
                  cacheWidth: _displayLongestSide(context),
                  fit: BoxFit.cover,
                  excludeFromSemantics: true, // Decorative background.
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xd90c0d0a), Color(0xf20c0d0a)],
                    ),
                  ),
                ),
                child,
              ],
            ),
    );
  }
}

/// The display's longest side in physical pixels (null when unknown): wide
/// enough to keep a cover-fitted background sharp in any window on it, while
/// capping the memory of a large photo.
int? _displayLongestSide(BuildContext context) {
  final side = View.of(context).display.size.longestSide.round();
  return side > 0 ? side : null;
}
