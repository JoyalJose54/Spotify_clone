import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart' as ja;
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';


// ─────────────────────────────────────────────────────────────────────────────
//  Global helper to open the Now Playing screen with a smooth swipe-down dismiss
// ─────────────────────────────────────────────────────────────────────────────
void openNowPlaying(BuildContext context, Song song) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false, // We'll handle safe area inside the screen
    backgroundColor: Colors.transparent,
    builder: (_) => NowPlayingScreen(song: song),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  NowPlayingScreen
// ─────────────────────────────────────────────────────────────────────────────
class NowPlayingScreen extends StatefulWidget {
  final Song song;
  const NowPlayingScreen({super.key, required this.song});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  // ── Background gradient colours ──────────────────────────────────────────
  Color _bgColor       = const Color(0xFF2E7D8A);
  Color _bgColorDark   = const Color(0xFF1A4A52);
  Color _bgColorBottom = const Color(0xFF121212);

  // ── PageView for album art ────────────────────────────────────────────────
  PageController? _pageController;
  int    _lastKnownIndex          = -1;
  String? _currentExtractedUrl;
  bool   _isProgrammaticPageChange = false;

  @override
  void initState() {
    super.initState();
    _currentExtractedUrl = widget.song.imageUrl;
    if (_currentExtractedUrl != null && _currentExtractedUrl!.isNotEmpty && PaletteCache.contains(_currentExtractedUrl!)) {
      final cached = PaletteCache.get(_currentExtractedUrl!)!;
      _bgColor = cached.bgColor;
      _bgColorDark = cached.bgColorDark;
      _bgColorBottom = cached.bgColorBottom;
    } else if (_currentExtractedUrl != null && _currentExtractedUrl!.isNotEmpty) {
      // Defer palette extraction until route transition completes to prevent transition lag/stutter
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null && route.animation != null) {
          if (route.animation!.isCompleted) {
            _extractPalette(_currentExtractedUrl!);
          } else {
            void listener(AnimationStatus status) {
              if (status == AnimationStatus.completed) {
                if (mounted && _currentExtractedUrl != null) {
                  _extractPalette(_currentExtractedUrl!);
                }
                route.animation!.removeStatusListener(listener);
              }
            }
            route.animation!.addStatusListener(listener);
          }
        } else {
          _extractPalette(_currentExtractedUrl!);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _extractPalette(String url) async {
    if (url.isEmpty) return;
    if (PaletteCache.contains(url)) {
      final cached = PaletteCache.get(url)!;
      if (mounted) {
        setState(() {
          _bgColor = cached.bgColor;
          _bgColorDark = cached.bgColorDark;
          _bgColorBottom = cached.bgColorBottom;
        });
      }
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
          ResizeImage(NetworkImage(url), width: 100), maximumColorCount: 8);
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

      setState(() {
        _bgColor = bgColor;
        _bgColorDark = bgColorDark;
        _bgColorBottom = bgColorBottom;
      });
    } catch (_) {}
  }

  void _dismiss() => Navigator.of(context).maybePop();

  // Called from a postFrameCallback inside build() — safe because it runs
  // AFTER the current frame is committed, not during the build phase.
  void _syncPaletteIfNeeded(String imageUrl) {
    if (!mounted) return;
    if (_currentExtractedUrl == imageUrl) return; // no change
    _currentExtractedUrl = imageUrl;
    if (imageUrl.isNotEmpty && PaletteCache.contains(imageUrl)) {
      final cached = PaletteCache.get(imageUrl)!;
      setState(() {
        _bgColor       = cached.bgColor;
        _bgColorDark   = cached.bgColorDark;
        _bgColorBottom = cached.bgColorBottom;
      });
    } else if (imageUrl.isNotEmpty) {
      _extractPalette(imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(builder: (context, player, _) {
      final current = player.currentSong ?? widget.song;

      // Defer all state mutation to after the frame — never mutate fields
      // directly inside build() as it corrupts the element tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncPaletteIfNeeded(current.imageUrl);
      });

      final qIndex = player.queueIndex;

      if (_pageController == null) {
        _pageController = PageController(initialPage: qIndex, viewportFraction: 1.0);
        _lastKnownIndex = qIndex;
      } else if (_lastKnownIndex != qIndex && !_isProgrammaticPageChange) {
        _lastKnownIndex = qIndex;
        // Defer PageView scroll to after frame — animateToPage requires clients
        // to be attached, which is guaranteed only after build completes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_pageController!.hasClients &&
              _pageController!.page?.round() != qIndex) {
            _isProgrammaticPageChange = true;
            _pageController!
                .animateToPage(
              qIndex,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            )
                .then((_) {
              _isProgrammaticPageChange = false;
            });
          }
        });
      }

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.6, 1.0],
              colors: [_bgColor, _bgColorDark, _bgColorBottom],
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context, player, current),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxHeight = constraints.maxHeight;

                        // Dynamically scale album art size based on available height,
                        // capping it at screen width minus padding.
                        final albumArtSize = (maxHeight * 0.44).clamp(180.0, MediaQuery.of(context).size.width - 48);

                        // Dynamically compute vertical margins/gaps based on available height.
                        final topSpacing = (maxHeight * 0.07).clamp(12.0, 48.0);
                        final artToInfoSpacing = (maxHeight * 0.05).clamp(12.0, 36.0);
                        final infoToProgressSpacing = (maxHeight * 0.03).clamp(8.0, 20.0);
                        final progressToControlsSpacing = (maxHeight * 0.03).clamp(8.0, 24.0);
                        final controlsToBottomSpacing = (maxHeight * 0.04).clamp(12.0, 32.0);

                        if (maxHeight < 580) {
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: topSpacing),
                                _buildAlbumArt(player, albumArtSize),
                                SizedBox(height: artToInfoSpacing),
                                _buildSongInfo(context, current, player),
                                SizedBox(height: infoToProgressSpacing),
                                _buildProgressBar(player),
                                SizedBox(height: progressToControlsSpacing),
                                _buildControls(player),
                                SizedBox(height: controlsToBottomSpacing),
                                _buildBottomRow(player, current),
                                const SizedBox(height: 16),
                              ],
                            ),
                          );
                        } else {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Spacer(flex: 2),
                                _buildAlbumArt(player, albumArtSize),
                                const Spacer(flex: 2),
                                _buildSongInfo(context, current, player),
                                SizedBox(height: infoToProgressSpacing),
                                _buildProgressBar(player),
                                SizedBox(height: progressToControlsSpacing),
                                _buildControls(player),
                                const Spacer(flex: 2),
                                _buildBottomRow(player, current),
                                const SizedBox(height: 56),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // ── HEADER ──────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, PlayerProvider player, Song song) {
    String pName = player.currentPlaylistName ??
        (song.album.isNotEmpty ? song.album : 'All Songs');
    String topText = 'PLAYING FROM PLAYLIST';

    if (pName.startsWith('Search: ')) {
      topText = 'PLAYING FROM SEARCH';
      pName = pName.substring(8);
    } else if (player.currentPlaylistName == null && song.album.isNotEmpty) {
      topText = 'PLAYING FROM ALBUM';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 48, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Down chevron — dismiss
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: 30),
            onPressed: _dismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  topText,
                  style: SpotifyFonts.bold(
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pName,
                  style: SpotifyFonts.bold(color: Colors.white, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 26),
            onPressed: () => _showSongOptions(context, song),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }

  // ── ALBUM ART ───────────────────────────────────────────────────────────────
  Widget _buildAlbumArt(PlayerProvider player, double size) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: PageView.builder(
          controller: _pageController,
          physics: player.queue.length <= 1
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: player.queue.isEmpty ? 1 : player.queue.length,
          onPageChanged: (index) {
            if (_isProgrammaticPageChange) return;
            if (player.queue.isEmpty) return;
            if (index > player.queueIndex) {
              player.skipNext();
            } else if (index < player.queueIndex) {
              player.skipPrevious();
            }
          },
          itemBuilder: (context, index) {
            final song =
                player.queue.isEmpty ? widget.song : player.queue[index];
            return Padding(
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: song.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: song.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: SpotifyColors.surface,
                          child: const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SpotifyColors.green),
                          ),
                        ),
                        errorWidget: (_, __, ___) => _artPlaceholder(),
                      )
                    : _artPlaceholder(),

              ),
            );
          },
        ),
      ),
    );
  }

  Widget _artPlaceholder() => Container(
        color: SpotifyColors.surface,
        child: const Center(
          child: Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 80),
        ),
      );

  // ── SONG INFO ───────────────────────────────────────────────────────────────
  Widget _buildSongInfo(BuildContext context, Song song, PlayerProvider player) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                style: SpotifyFonts.title(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                song.artist,
                style: SpotifyFonts.regular(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── PROGRESS BAR ────────────────────────────────────────────────────────────
  Widget _buildProgressBar(PlayerProvider player) {
    return StreamBuilder<PositionData>(
      stream: player.positionDataStream,
      builder: (context, snapshot) {
        final data = snapshot.data ??
            const PositionData(Duration.zero, Duration.zero, Duration.zero);
        final progress = data.progress.clamp(0.0, 1.0);

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: progress,
                onChanged: (v) {
                  final ms = (data.duration.inMilliseconds * v).round();
                  player.seekTo(Duration(milliseconds: ms));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    data.positionFormatted,
                    style: SpotifyFonts.regular(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    data.durationFormatted,
                    style: SpotifyFonts.regular(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── CONTROLS ────────────────────────────────────────────────────────────────
  Widget _buildControls(PlayerProvider player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Shuffle
        GestureDetector(
          onTap: player.toggleShuffle,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Icon(
                SpoticonIcons.shuffle,
                color: player.isShuffled ? SpotifyColors.green : Colors.white,
                size: 28,
              ),
              if (player.isShuffled)
                Positioned(
                  bottom: -6,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: SpotifyColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Skip previous
        GestureDetector(
          onTap: player.queue.length <= 1 ? null : player.skipPrevious,
          child: Image.asset(
            'assets/images/previous.png',
            color: player.queue.length <= 1
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white,
            width: 42,
            height: 42,
          ),
        ),

        // Play / Pause with buffering spinner
        StreamBuilder<ja.PlayerState>(
          stream: player.playerStateStream,
          builder: (_, snap) {
            final state = snap.data;
            final isPlaying = state?.playing ?? player.isPlaying;
            final processingState = state?.processingState ?? ja.ProcessingState.idle;

            if (processingState == ja.ProcessingState.loading ||
                processingState == ja.ProcessingState.buffering) {
              return SizedBox(
                width: 68,
                height: 68,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: CircularProgressIndicator(
                    color: Colors.white.withAlpha(200),
                    strokeWidth: 3,
                  ),
                ),
              );
            }

            return GestureDetector(
              onTap: player.togglePlayPause,
              child: Image.asset(
                isPlaying ? 'assets/images/pause.png' : 'assets/images/play.png',
                width: 68,
                height: 68,
              ),
            );
          },
        ),

        // Skip next
        GestureDetector(
          onTap: player.queue.length <= 1 ? null : player.skipNext,
          child: Image.asset(
            'assets/images/next.png',
            color: player.queue.length <= 1
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white,
            width: 42,
            height: 42,
          ),
        ),

        // Sleep timer
        GestureDetector(
          onTap: () {},
          child: const Icon(Icons.timer_outlined, color: Colors.white, size: 28),
        ),
      ],
    );
  }

  // ── BOTTOM ROW ───────────────────────────────────────────────────────────────
  Widget _buildBottomRow(PlayerProvider player, Song song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(
            Icons.devices,
            color: Colors.white30,
            size: 24,
          ),
          Row(children: [
            GestureDetector(
              onTap: () {},
              child: const Icon(Icons.share, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 24),
            GestureDetector(
              onTap: () => _showQueue(context, player),
              child: const Icon(Icons.format_list_bulleted,
                  color: Colors.white, size: 26),
            ),
          ]),
        ],
      ),
    );
  }

  // ── QUEUE SHEET ──────────────────────────────────────────────────────────────
  void _showQueue(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotifyColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: SpotifyColors.lightGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Next in queue',
                    style: SpotifyFonts.regular(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: player.queue.length,
                itemBuilder: (_, i) {
                  final s = player.queue[i];
                  final isCurrent = i == player.queueIndex;
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: s.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: s.imageUrl,
                              width: 44, height: 44, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: 44, height: 44,
                                color: SpotifyColors.surface,
                                child: const Icon(Icons.music_note,
                                    color: SpotifyColors.lightGrey)))
                          : Container(
                              width: 44,
                              height: 44,
                              color: SpotifyColors.surface,
                              child: const Icon(Icons.music_note,
                                  color: SpotifyColors.lightGrey)),
                    ),
                    title: Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SpotifyFonts.bold(
                          color: isCurrent
                              ? SpotifyColors.green
                              : SpotifyColors.white,
                          fontSize: 14,
                        )),
                    subtitle: Text(s.artist,
                        style: SpotifyFonts.regular(
                            color: SpotifyColors.lightGrey, fontSize: 12)),
                    onTap: () {
                      player.playSong(s, playlist: player.queue);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── OPTIONS SHEET ─────────────────────────────────────────────────────────────
  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: SpotifyColors.lightGrey,
                borderRadius: BorderRadius.circular(2)),
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
                        errorWidget: (_, __, ___) => Container(
                            width: 56, height: 56, color: SpotifyColors.surface))
                    : Container(
                        width: 56, height: 56, color: SpotifyColors.surface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        style:
                            SpotifyFonts.bold(color: Colors.white, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(song.artist,
                        style: SpotifyFonts.regular(
                            color: SpotifyColors.lightGrey)),
                  ],
                ),
              ),
            ]),
          ),
          const Divider(color: SpotifyColors.surfaceLight, height: 1),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
