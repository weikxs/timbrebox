import 'package:flutter/material.dart';

/// A full color palette for one theme. Every surface/text color the app uses is
/// read through [TimbreColors], which points at the active palette, so swapping
/// this one object re-themes the whole app (light / dark / black).
class TimbrePalette {
  const TimbrePalette({
    required this.brightness,
    required this.canvas,
    required this.canvasRaised,
    required this.ink,
    required this.muted,
    required this.gold,
    required this.line,
    required this.panel,
    required this.panelStrong,
  });

  final Brightness brightness;
  final Color canvas;
  final Color canvasRaised;
  final Color ink;
  final Color muted;
  final Color gold;
  final Color line;
  final Color panel;
  final Color panelStrong;
}

/// Dark (default) — warm near-black with light ink.
const kDarkPalette = TimbrePalette(
  brightness: Brightness.dark,
  canvas: Color(0xff10110f),
  canvasRaised: Color(0xff181914),
  ink: Color(0xfff0eee8),
  muted: Color(0xffaaa7a0),
  gold: Color(0xffe1b27b),
  line: Color(0x24ffffff),
  panel: Color(0x12ffffff),
  panelStrong: Color(0x1cffffff),
);

/// Light — a soft warm-neutral ground with clean white cards. Panels brighten
/// toward white (white-alpha, not the muddy black-alpha a dark theme would
/// use) so surfaces read as crisp cards over the greige canvas, with a hairline
/// border and a deep amber-gold accent that holds contrast on white.
const kLightPalette = TimbrePalette(
  brightness: Brightness.light,
  canvas: Color(0xffeeebe6),
  canvasRaised: Color(0xfffbfaf7),
  ink: Color(0xff201f1b),
  muted: Color(0xff726d64),
  gold: Color(0xffa9741f),
  line: Color(0x1f1a1712),
  panel: Color(0x8cffffff),
  panelStrong: Color(0xc7ffffff),
);

/// Pure black (AMOLED) — true black ground, same warm ink as dark.
const kBlackPalette = TimbrePalette(
  brightness: Brightness.dark,
  canvas: Color(0xff000000),
  canvasRaised: Color(0xff0c0c0b),
  ink: Color(0xfff0eee8),
  muted: Color(0xff9a968f),
  gold: Color(0xffe1b27b),
  line: Color(0x1fffffff),
  panel: Color(0x10ffffff),
  panelStrong: Color(0x1affffff),
);

/// The app's color tokens, resolved against [active]. Not `const` — reading a
/// token returns the current palette's color, so a palette swap re-themes the
/// whole UI on the next rebuild.
abstract final class TimbreColors {
  static TimbrePalette active = kDarkPalette;

  static Color get canvas => active.canvas;
  static Color get canvasRaised => active.canvasRaised;
  static Color get ink => active.ink;
  static Color get muted => active.muted;
  static Color get gold => active.gold;
  static Color get line => active.line;
  static Color get panel => active.panel;
  static Color get panelStrong => active.panelStrong;
}
