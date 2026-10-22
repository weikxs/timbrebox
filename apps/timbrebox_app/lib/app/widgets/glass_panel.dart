import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/app_effects.dart';
import '../design/timbre_colors.dart';

/// A liquid-glass surface: the content behind is frosted by a backdrop blur, a
/// translucent tinted fill sits on top, a bright hairline traces the glass edge,
/// and a soft drop shadow lifts it off the page. Tint + shadow adapt to the
/// active light/dark palette.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding,
    this.radius = 22,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final light = TimbreColors.active.brightness == Brightness.light;
    final rounded = BorderRadius.circular(radius);
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TimbreColors.panelStrong, TimbreColors.panel],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: light ? .55 : .12),
          width: .8,
        ),
      ),
      child: content,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: rounded,
        // "Reduce visual effects" also drops the (relatively costly) shadow.
        boxShadow: AppEffects.reduced
            ? null
            : [
                BoxShadow(
                  color: light
                      ? const Color(0x1f101826)
                      : const Color(0x59000000),
                  blurRadius: light ? 26 : 32,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: rounded,
        // Skip the backdrop blur when effects are reduced — it's the heaviest
        // part of the glass look.
        child: AppEffects.reduced
            ? surface
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: surface,
              ),
      ),
    );
  }
}
