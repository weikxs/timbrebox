import 'package:flutter/material.dart';

import '../design/app_strings.dart';
import '../design/timbre_colors.dart';
import '../model/catalog_track.dart';
import '../state/app_controller.dart';
import 'glass_panel.dart';

/// Prompts for a playlist name (used for create and rename).
Future<String?> promptPlaylistName(
  BuildContext context, {
  String initial = '',
}) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      content: TextField(
        controller: field,
        autofocus: true,
        decoration: InputDecoration(
          hintText: AppStrings.t('library.playlistNameHint'),
        ),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.t('common.cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, field.text.trim()),
          child: Text(AppStrings.t('common.confirm')),
        ),
      ],
    ),
  );
}

/// A per-track button that adds the track to a playlist (or a new one).
class AddToPlaylistButton extends StatelessWidget {
  const AddToPlaylistButton({
    required this.controller,
    required this.track,
    super.key,
  });

  final AppController controller;
  final CatalogTrack track;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: AppStrings.t('library.addToPlaylist'),
    icon: Icon(Icons.playlist_add, size: 20, color: TimbreColors.muted),
    onSelected: (value) async {
      if (value == '__new__') {
        final name = await promptPlaylistName(context);
        if (name != null && name.isNotEmpty) {
          controller.createPlaylist(name, seed: track);
        }
        return;
      }
      controller.addToPlaylist(value, track);
    },
    itemBuilder: (context) => [
      for (final playlist in controller.playlists)
        PopupMenuItem(value: playlist.id, child: Text(playlist.name)),
      PopupMenuItem(
        value: '__new__',
        child: Text(AppStrings.t('library.newPlaylist')),
      ),
    ],
  );
}

/// Playlists section for the "My Music" page: create, play, rename, delete, and
/// expand to manage tracks.
class PlaylistsPanel extends StatelessWidget {
  const PlaylistsPanel({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final playlists = controller.playlists;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppStrings.t('library.playlists'),
                style: TextStyle(
                  color: TimbreColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final name = await promptPlaylistName(context);
                  if (name != null && name.isNotEmpty) {
                    controller.createPlaylist(name);
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(AppStrings.t('library.newPlaylist')),
              ),
            ],
          ),
          if (playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                AppStrings.t('library.playlistsEmpty'),
                style: TextStyle(color: TimbreColors.muted, fontSize: 12),
              ),
            )
          else
            for (final playlist in playlists)
              _PlaylistTile(controller: controller, playlistId: playlist.id),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.controller, required this.playlistId});

  final AppController controller;
  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final playlist = controller.playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => throw StateError('playlist removed'),
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(playlist.name),
        subtitle: Text(
          AppStrings.t(
            'library.playlistCountFmt',
          ).replaceFirst('{n}', '${playlist.tracks.length}'),
          style: TextStyle(color: TimbreColors.muted, fontSize: 11),
        ),
        leading: IconButton(
          tooltip: AppStrings.t('common.play'),
          icon: Icon(Icons.play_circle_fill, color: TimbreColors.gold),
          onPressed: playlist.tracks.isEmpty
              ? null
              : () => controller.playPlaylist(playlist.id),
        ),
        children: [
          for (final track in playlist.tracks)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 8, right: 0),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => controller.play(track),
              trailing: IconButton(
                tooltip: AppStrings.t('library.removeFromPlaylist'),
                icon: Icon(
                  Icons.remove_circle_outline,
                  size: 18,
                  color: TimbreColors.muted,
                ),
                onPressed: () =>
                    controller.removeFromPlaylist(playlist.id, track.ref),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (playlist.tracks.isNotEmpty)
                TextButton.icon(
                  onPressed: () => controller.shufflePlay(playlist.tracks),
                  icon: const Icon(Icons.shuffle_rounded, size: 16),
                  label: Text(AppStrings.t('library.shuffle')),
                ),
              TextButton(
                onPressed: () async {
                  final name = await promptPlaylistName(
                    context,
                    initial: playlist.name,
                  );
                  if (name != null && name.isNotEmpty) {
                    controller.renamePlaylist(playlist.id, name);
                  }
                },
                child: Text(AppStrings.t('library.renamePlaylist')),
              ),
              TextButton(
                onPressed: () => controller.deletePlaylist(playlist.id),
                child: Text(AppStrings.t('common.delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
