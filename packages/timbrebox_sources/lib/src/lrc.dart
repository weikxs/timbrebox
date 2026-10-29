import 'dart:convert';

/// One line of a lyric: when it starts (for a synced lyric) and its text.
class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

/// A lyric parsed from LRC text (`[mm:ss.xx]words`), as plugins return from
/// `getLyric`. Lines may carry several time stamps; `[offset:ms]` shifts them
/// all; other `[tag:value]` lines are metadata. Text with no time stamps is
/// kept as unsynced lines, still readable.
class Lyric {
  const Lyric._(this.lines, {required this.isSynced});

  factory Lyric.parse(String raw) {
    var offset = Duration.zero;
    final timed = <LyricLine>[];
    final plain = <String>[];
    for (final rawLine in const LineSplitter().convert(raw)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final offsetTag = _offsetTag.firstMatch(line);
      if (offsetTag != null) {
        offset = Duration(milliseconds: int.parse(offsetTag.group(1)!));
        continue;
      }
      final stamps = _leadingStamps.firstMatch(line);
      if (stamps == null) {
        if (!_metadataTag.hasMatch(line)) plain.add(line);
        continue;
      }
      final text = line.substring(stamps.end).trim();
      for (final stamp in _stamp.allMatches(stamps.group(0)!)) {
        timed.add(LyricLine(_time(stamp), text));
      }
    }
    if (timed.isEmpty) {
      return Lyric._([
        for (final text in plain) LyricLine(Duration.zero, text),
      ], isSynced: false);
    }
    final shifted = [
      for (final line in timed)
        if (line.text.isNotEmpty)
          LyricLine(
            line.time + offset < Duration.zero
                ? Duration.zero
                : line.time + offset,
            line.text,
          ),
    ]..sort((a, b) => a.time.compareTo(b.time));
    return Lyric._(shifted, isSynced: true);
  }

  final List<LyricLine> lines;

  /// Whether the lines carry times (and can follow and seek playback).
  final bool isSynced;

  /// The index of the line playing at [position], or -1 before the first.
  int indexAt(Duration position) {
    if (!isSynced) return -1;
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (lines[middle].time <= position) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }

  static Duration _time(RegExpMatch stamp) {
    final minutes = int.parse(stamp.group(1)!);
    final seconds = int.parse(stamp.group(2)!);
    final fraction = stamp.group(3) ?? '';
    final millis = fraction.isEmpty
        ? 0
        : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
  }

  static final _leadingStamps = RegExp(r'^(\[\d+:\d{1,2}(?:[.:]\d{1,3})?\])+');
  static final _stamp = RegExp(r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _offsetTag = RegExp(
    r'^\[offset:\s*([+-]?\d+)\s*\]$',
    caseSensitive: false,
  );
  static final _metadataTag = RegExp(r'^\[[a-zA-Z]+:.*\]$');
}
