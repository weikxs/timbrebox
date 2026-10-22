import 'package:flutter/material.dart';

import '../design/timbre_colors.dart';

/// Shared editorial page header: a restrained eyebrow, a compact serif title,
/// a quiet subtitle line, and an optional trailing action. Type sizes are kept
/// deliberately small so the content — not the chrome — carries the page.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    required this.kicker,
    required this.title,
    required this.detail,
    required this.child,
    this.trailing,
    this.compact = false,
    super.key,
  });

  final String kicker;
  final String title;
  final String detail;
  final Widget child;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: ListView(
      padding: EdgeInsets.fromLTRB(2, compact ? 14 : 18, 2, 14),
      children: [
        Text(
          kicker,
          style: TextStyle(
            color: TimbreColors.gold,
            fontSize: 10,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: compact ? 5 : 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: compact ? 19 : 23,
                  height: 1.05,
                  letterSpacing: -.4,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          detail,
          style: TextStyle(
            color: TimbreColors.muted,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        SizedBox(height: compact ? 14 : 20),
        child,
      ],
    ),
  );
}
