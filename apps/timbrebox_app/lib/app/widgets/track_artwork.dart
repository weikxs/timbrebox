import 'package:flutter/material.dart';

import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';

/// Cover tile for a track. When the source provides real cover art (Audius) it
/// loads that image; otherwise it derives a deterministic placeholder from the
/// title — never fabricated imagery.
class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    required this.track,
    required this.size,
    this.radius = 8,
    super.key,
  });

  final CatalogTrack? track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final artworkUrl = track?.artworkUrl;
    final placeholder = _Placeholder(track: track, size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: artworkUrl == null || artworkUrl.isEmpty
            ? placeholder
            : Image.network(
                artworkUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // Decorative: the track title/artist text always sits alongside.
                excludeFromSemantics: true,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
                errorBuilder: (context, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.track, required this.size});

  final CatalogTrack? track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = _initial(track?.title);
    final light = TimbreColors.active.brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? const [Color(0xffe7e3da), Color(0xffd9d4ca)]
              : const [Color(0xff2a2b24), Color(0xff16170f)],
        ),
      ),
      child: Center(
        child: initial == null
            ? Icon(
                Icons.music_note_rounded,
                size: size * .44,
                color: TimbreColors.muted,
              )
            : Text(
                initial,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: size * .42,
                  color: TimbreColors.gold,
                ),
              ),
      ),
    );
  }

  String? _initial(String? title) {
    final trimmed = title?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed.characters.first.toUpperCase();
  }
}
