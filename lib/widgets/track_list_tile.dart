import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../screens/player/now_playing_screen.dart';


class TrackListTile extends StatelessWidget {
  final Song song;
  final List<Song> allSongs;
  final VoidCallback? onTap;
  final bool canDelete;
  final String? playlistId;
  final String? playlistName;
  final bool showOptions;

  const TrackListTile({
    super.key,
    required this.song,
    required this.allSongs,
    this.onTap,
    this.canDelete = false,
    this.playlistId,
    this.playlistName,
    this.showOptions = true,
  });

  @override
  Widget build(BuildContext context) {
    // Use context.read for the tap handler — no rebuild needed.
    // Use Selector for ONLY the two pieces that react to player state:
    //   1. The thumbnail playing overlay (sound bars / pause icon)
    //   2. The title color (green when current, white otherwise)
    // Everything else (image, artist, duration, options) NEVER rebuilds.
    return Selector<PlayerProvider, (bool, bool)>(
      selector: (_, player) => (
        player.currentSong?.id == song.id,  // isCurrent
        player.isPlaying,                    // isPlaying
      ),
      builder: (context, state, __) {
        final isCurrent = state.$1;
        final isPlaying = isCurrent && state.$2;

        return InkWell(
          onTap: onTap ?? () {
            final player = context.read<PlayerProvider>();
            player.playSong(song, playlist: allSongs, playlistName: playlistName);
            FirebaseService.addRecentlyPlayed(song.id);
            openNowPlaying(context, song);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Thumbnail
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: song.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: song.imageUrl,
                              width: 52, height: 52, fit: BoxFit.cover,
                              memCacheWidth: 150, memCacheHeight: 150,
                              errorWidget: (_, __, ___) => _imgPlaceholder())
                          : _imgPlaceholder(),
                    ),
                    if (isCurrent)
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: isPlaying
                              ? const _SoundBars(color: SpotifyColors.green)
                              : const Icon(Icons.pause, color: SpotifyColors.green, size: 22),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // Title + artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: SpotifyFonts.bold(
                            color: isCurrent ? SpotifyColors.green : SpotifyColors.white,
                            fontSize: 15,
                          )),
                      const SizedBox(height: 2),
                      Row(children: [
                        if (song.isExplicit)
                          Container(
                            margin: const EdgeInsets.only(right: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: SpotifyColors.lightGrey.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text('E',
                                style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 10)),
                          ),
                        Expanded(
                          child: Text(song.artist,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: SpotifyFonts.regular(
                                  color: SpotifyColors.lightGrey, fontSize: 13)),
                        ),
                      ]),
                    ],
                  ),
                ),
                // Duration + more
                Text(song.durationMs > 0 ? song.durationFormatted : '',
                    style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 12)),
                if (showOptions)
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: SpotifyColors.lightGrey, size: 22),
                    onPressed: () => _showTrackOptions(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _imgPlaceholder() => Container(
    width: 52, height: 52,
    color: SpotifyColors.surface,
    child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 22),
  );

  void _showTrackOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => TrackOptionsSheet(
        song: song,
        canDelete: canDelete,
        playlistId: playlistId,
        scaffoldContext: context,
      ),
    );
  }
}

class TrackOptionsSheet extends StatelessWidget {
  final Song song;
  final bool canDelete;
  final String? playlistId;
  final BuildContext scaffoldContext;

  const TrackOptionsSheet({
    super.key,
    required this.song,
    this.canDelete = false,
    this.playlistId,
    required this.scaffoldContext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: SpotifyColors.lightGrey, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: song.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: song.imageUrl,
                      width: 56, height: 56, fit: BoxFit.cover,
                      memCacheWidth: 150, memCacheHeight: 150,
                      errorWidget: (_, __, ___) => Container(width: 56, height: 56, color: SpotifyColors.surface))
                  : Container(width: 56, height: 56, color: SpotifyColors.surface,
                      child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(song.title,
                    style: SpotifyFonts.bold(color: SpotifyColors.white, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(song.artist,
                    style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 13)),
              ]),
            ),
          ]),
        ),
        const Divider(color: SpotifyColors.surfaceLight, height: 1),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SoundBars extends StatefulWidget {
  final Color color;
  const _SoundBars({required this.color});
  @override
  State<_SoundBars> createState() => _SoundBarsState();
}

class _SoundBarsState extends State<_SoundBars> with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400 + i * 100),
      )..repeat(reverse: true);
      return c;
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _ctrls[i],
        builder: (_, __) => Container(
          width: 3, height: 4 + _ctrls[i].value * 12,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      )),
    );
  }
}
