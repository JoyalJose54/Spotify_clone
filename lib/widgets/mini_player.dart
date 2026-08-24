import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:just_audio/just_audio.dart' as ja;
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../screens/player/now_playing_screen.dart';


class MiniPlayer extends StatefulWidget {
  final PlayerProvider player;
  const MiniPlayer({super.key, required this.player});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  Color _bgColor = SpotifyColors.surface;
  String? _currentExtractedUrl;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Kick off palette for the song that's already playing when widget mounts.
    final song = widget.player.currentSong;
    if (song != null && song.imageUrl.isNotEmpty) {
      _currentExtractedUrl = song.imageUrl;
      _applyOrFetchPalette(song.imageUrl, fromBuild: false);
    }
  }

  @override
  void didUpdateWidget(MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // React to song changes (triggered by PlayerProvider.notifyListeners).
    final newUrl = widget.player.currentSong?.imageUrl ?? '';
    if (newUrl != _currentExtractedUrl) {
      _currentExtractedUrl = newUrl;
      if (newUrl.isEmpty) {
        setState(() => _bgColor = SpotifyColors.surface);
      } else {
        _applyOrFetchPalette(newUrl, fromBuild: false);
      }
    }
  }

  /// Either reads from cache immediately or triggers async extraction.
  /// [fromBuild] must always be false — this must never be called from build().
  void _applyOrFetchPalette(String url, {required bool fromBuild}) {
    assert(!fromBuild, '_applyOrFetchPalette must not be called from build()');
    if (PaletteCache.contains(url)) {
      final cached = PaletteCache.get(url)!;
      final hsl = HSLColor.fromColor(cached.dominant);
      final color = hsl
          .withSaturation((hsl.saturation * 0.9).clamp(0, 1))
          .withLightness((hsl.lightness * 0.35).clamp(0.15, 0.45))
          .toColor();
      // Safe to call setState here — we are in a lifecycle method, not build().
      if (mounted) setState(() => _bgColor = color);
    } else {
      // Reset to neutral first so the old color doesn't linger.
      if (mounted) setState(() => _bgColor = SpotifyColors.surface);
      _extractPalette(url);
    }
  }


  Future<void> _extractPalette(String url) async {
    if (url.isEmpty) return;
    if (PaletteCache.contains(url)) {
      final cached = PaletteCache.get(url)!;
      final hsl = HSLColor.fromColor(cached.dominant);
      if (mounted) {
        setState(() {
          _bgColor = hsl.withSaturation((hsl.saturation * 0.9).clamp(0, 1))
                        .withLightness((hsl.lightness * 0.35).clamp(0.15, 0.45))
                        .toColor();
        });
      }
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(url), maximumColorCount: 8);
      if (!mounted) return;
      
      final dominant = palette.dominantColor?.color ?? const Color(0xFF2E7D8A);
      final vibrant = palette.vibrantColor?.color ?? dominant;
      final muted = palette.mutedColor?.color ??
          palette.darkMutedColor?.color ??
          const Color(0xFF1A4A52);

      final hslDominant = HSLColor.fromColor(dominant);
      final hslMuted   = HSLColor.fromColor(muted);

      final bgColor = hslDominant
          .withSaturation((hslDominant.saturation * 1.0).clamp(0, 1))
          .withLightness((hslDominant.lightness * 0.8).clamp(0.2, 0.5))
          .toColor();
      final bgColorDark = hslMuted
          .withSaturation((hslMuted.saturation * 0.8).clamp(0, 1))
          .withLightness((hslMuted.lightness * 0.4).clamp(0.1, 0.3))
          .toColor();
      final bgColorBottom = hslMuted
          .withSaturation((hslMuted.saturation * 0.5).clamp(0, 1))
          .withLightness(0.05)
          .toColor();

      PaletteCache.set(url, PaletteColors(
        dominant: dominant,
        vibrant: vibrant,
        muted: muted,
        bgColor: bgColor,
        bgColorDark: bgColorDark,
        bgColorBottom: bgColorBottom,
      ));

      final hsl = HSLColor.fromColor(dominant);
      setState(() {
        _bgColor = hsl.withSaturation((hsl.saturation * 0.9).clamp(0, 1))
                      .withLightness((hsl.lightness * 0.35).clamp(0.15, 0.45))
                      .toColor();
      });
    } catch (_) {}
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  // NOTE: build() is now pure — no setState, no side-effects, no scheduling.
  //       All palette logic lives in initState / didUpdateWidget above.

  @override
  Widget build(BuildContext context) {
    if (!widget.player.hasCurrentSong) return const SizedBox.shrink();
    final song = widget.player.currentSong!;

    return GestureDetector(
      onTap: () => _expand(context, song),
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null && d.primaryVelocity! < -200) {
          _expand(context, song);
        }
      },
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          height: 58,
          decoration: BoxDecoration(
            color: _bgColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // ── Real progress bar from just_audio ─────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: StreamBuilder<PositionData>(
                  stream: widget.player.positionDataStream,
                  builder: (_, snap) {
                    final progress = snap.data?.progress ?? 0.0;
                    return ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation(SpotifyColors.white),
                      ),
                    );
                  },
                ),
              ),

              // ── Row ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Album art
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: song.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: song.imageUrl,
                              width: 40, height: 40, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _imgPlaceholder())
                          : _imgPlaceholder(),
                    ),
                    const SizedBox(width: 12),
                    // Song info
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SpotifyFonts.bold(
                            color: SpotifyColors.white,
                            fontSize: 13)),
                    Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SpotifyFonts.regular(
                            color: SpotifyColors.lightGrey, fontSize: 12)),
                        ],
                      ),
                    ),

                    // Controls (Prev, Play/Pause, Next)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Image.asset(
                            'assets/images/mini_previous.png',
                            color: widget.player.queue.length <= 1
                                ? SpotifyColors.white.withValues(alpha: 0.3)
                                : SpotifyColors.white,
                            width: 24,
                            height: 24,
                          ),
                          onPressed: widget.player.queue.length <= 1
                              ? null
                              : () => widget.player.skipPrevious(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        StreamBuilder<ja.PlayerState>(
                          stream: widget.player.playerStateStream,
                          builder: (_, snap) {
                            final state = snap.data;
                            final playing = state?.playing ?? widget.player.isPlaying;
                            final processingState = state?.processingState ?? ja.ProcessingState.idle;

                            if (processingState == ja.ProcessingState.loading ||
                                processingState == ja.ProcessingState.buffering) {
                              return const SizedBox(
                                width: 40,
                                height: 40,
                                child: Padding(
                                  padding: EdgeInsets.all(10.0),
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }

                            return IconButton(
                              icon: Image.asset(
                                playing ? 'assets/images/mini_pause.png' : 'assets/images/mini_play.png',
                                color: SpotifyColors.white, 
                                width: 28,
                                height: 28,
                              ),
                              onPressed: () => widget.player.togglePlayPause(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                            );
                          },
                        ),
                        IconButton(
                          icon: Image.asset(
                            'assets/images/mini_next.png',
                            color: widget.player.queue.length <= 1
                                ? SpotifyColors.white.withValues(alpha: 0.3)
                                : SpotifyColors.white,
                            width: 24,
                            height: 24,
                          ),
                          onPressed: widget.player.queue.length <= 1
                              ? null
                              : () => widget.player.skipNext(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _expand(BuildContext context, Song song) {
    openNowPlaying(context, song);
  }

  Widget _imgPlaceholder() => Container(
    width: 40, height: 40,
    color: SpotifyColors.surface,
    child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 20),
  );
}
