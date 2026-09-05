import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../player/now_playing_screen.dart';


class AlbumScreen extends StatefulWidget {
  final String albumId;
  final String albumTitle;
  final String albumArtist;
  final String albumImage;
  final int    albumYear;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.albumTitle,
    this.albumArtist = '',
    this.albumImage  = '',
    this.albumYear   = 0,
  });

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen>
    with SingleTickerProviderStateMixin {
  Color _dominantColor = SpotifyColors.surface;
  List<Song> _tracks   = [];
  bool _isLoading      = true;
  bool _isLiked        = false;
  final ScrollController _scrollCtrl = ScrollController();
  double _scrollOffset = 0;
  late AnimationController _headerCtrl;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _scrollCtrl.addListener(
        () => setState(() => _scrollOffset = _scrollCtrl.offset));
    _loadData();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final tracks = await FirebaseService.fetchTracksByAlbum(widget.albumId);
    if (!mounted) return;
    setState(() {
      _tracks    = tracks;
      _isLoading = false;
    });
    if (widget.albumImage.isNotEmpty) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
            NetworkImage(widget.albumImage));
        if (mounted) {
          setState(() =>
              _dominantColor = palette.dominantColor?.color ?? SpotifyColors.surface);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarOpacity = (_scrollOffset / 200).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: SpotifyColors.black,
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          // ── Sliver app bar ───────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor:
                Color.lerp(_dominantColor, const Color(0xFF121212), appBarOpacity),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: AnimatedOpacity(
              opacity: appBarOpacity,
              duration: Duration.zero,
              child: Text(widget.albumTitle,
                  style: SpotifyFonts.bold(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _dominantColor,
                      _dominantColor.withValues(alpha: 0.5),
                      SpotifyColors.black,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      ScaleTransition(
                        scale: CurvedAnimation(
                            parent: _headerCtrl, curve: Curves.easeOutBack),
                        child: Container(
                          width: 185,
                          height: 185,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                  spreadRadius: 4)
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: widget.albumImage.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: widget.albumImage,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => _imgPlaceholder())
                                : _imgPlaceholder(),

                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Album info ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.albumTitle,
                      style: SpotifyFonts.display(
                          color: Colors.white,
                          fontSize: 22))
                      .animate()
                      .fadeIn(duration: 400.ms),
                  const SizedBox(height: 4),
                  Text(widget.albumArtist,
                      style: SpotifyFonts.bold(
                          color: Colors.white,
                          fontSize: 13))
                      .animate(delay: 60.ms)
                      .fadeIn(),
                  const SizedBox(height: 4),
                  Text(
                      'Album${widget.albumYear > 0 ? ' • ${widget.albumYear}' : ''}',
                      style: SpotifyFonts.regular(
                          color: SpotifyColors.lightGrey, fontSize: 13))
                      .animate(delay: 100.ms)
                      .fadeIn(),
                  const SizedBox(height: 20),
                  // Action row
                  Row(children: [
                    GestureDetector(
                      onTap: () => setState(() => _isLiked = !_isLiked),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            key: ValueKey(_isLiked),
                            color: _isLiked
                                ? SpotifyColors.green
                                : SpotifyColors.lightGrey,
                            size: 28),
                      ),
                    ),
                    const SizedBox(width: 20),
                    const Icon(Icons.arrow_circle_down_outlined,
                        color: SpotifyColors.lightGrey, size: 28),
                    const SizedBox(width: 20),
                    const Icon(Icons.more_horiz,
                        color: SpotifyColors.lightGrey, size: 28),
                    const Spacer(),
                    // Shuffle
                    Consumer<PlayerProvider>(
                      builder: (ctx, player, _) => GestureDetector(
                        onTap: () {
                          if (_tracks.isEmpty) return;
                          final shuffled = List<Song>.from(_tracks)..shuffle();
                          player.toggleShuffle();
                          player.playSong(shuffled.first, playlist: shuffled);
                          _openPlayer(ctx, shuffled.first);
                        },
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: SpotifyColors.green.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shuffle,
                              color: SpotifyColors.green, size: 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Consumer<PlayerProvider>(
                      builder: (ctx, player, _) {
                        final isPlayingAlbum = _tracks.isNotEmpty &&
                            player.hasCurrentSong &&
                            player.currentSong!.albumId == widget.albumId;
                        return GestureDetector(
                          onTap: () {
                            if (_tracks.isEmpty) return;
                            if (isPlayingAlbum) {
                              player.togglePlayPause();
                            } else {
                              player.playSong(_tracks.first, playlist: _tracks);
                              _openPlayer(ctx, _tracks.first);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                                color: SpotifyColors.green, shape: BoxShape.circle),
                            child: StreamBuilder<bool>(
                              stream: player.playingStream,
                              builder: (_, snap) => Icon(
                                (snap.data ?? player.isPlaying) && isPlayingAlbum
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: SpotifyColors.black, size: 30,
                              ),
                            ),
                          ),
                        ).animate().scale(
                            begin: const Offset(0.8, 0.8),
                            duration: 300.ms,
                            curve: Curves.easeOutBack);
                      },
                    ),
                  ]).animate(delay: 160.ms).fadeIn(),
                ],
              ),
            ),
          ),

          // ── Track list ───────────────────────────────────────────────────
          _isLoading
              ? SliverList(
                  delegate: SliverChildBuilderDelegate(
                      (_, i) => _ShimmerTile(), childCount: 6))
              : _tracks.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text('No tracks found for this album.',
                              style: SpotifyFonts.regular(
                                  color: SpotifyColors.lightGrey, fontSize: 15)),
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final song = _tracks[i];
                          return _TrackTile(
                            song: song,
                            onTap: () {
                              final p = ctx.read<PlayerProvider>();
                              p.playSong(song, playlist: _tracks);
                              _openPlayer(ctx, song);
                            },
                          )
                              .animate(delay: (i * 55).ms)
                              .fadeIn(duration: 300.ms)
                              .slideX(begin: 0.05, end: 0);
                        },
                        childCount: _tracks.length,
                      ),
                    ),

          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

  void _openPlayer(BuildContext context, Song song) {
    openNowPlaying(context, song);
  }

  Widget _imgPlaceholder() => Container(
      color: SpotifyColors.surface,
      child: const Center(
          child: Icon(Icons.album, color: SpotifyColors.lightGrey, size: 60)));
}

// ── Single track tile ────────────────────────────────────────────────────────
class _TrackTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  const _TrackTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(builder: (_, player, __) {
      final isCurrent = player.currentSong?.id == song.id;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (isCurrent && player.isPlaying)
                  const _SoundBars(color: SpotifyColors.green),
                Row(children: [
                  const Icon(Icons.download_done,
                      color: SpotifyColors.green, size: 14),
                  const SizedBox(width: 4),
                  if (song.isExplicit)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                          color: SpotifyColors.lightGrey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2)),
                      child: Text('E',
                          style: SpotifyFonts.bold(
                              color: SpotifyColors.lightGrey,
                              fontSize: 10)),
                    ),
                ]),
                Text(
                  song.title,
                  style: SpotifyFonts.bold(
                      color: isCurrent ? SpotifyColors.green : SpotifyColors.white,
                      fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(song.artist,
                    style: SpotifyFonts.regular(
                        color: SpotifyColors.lightGrey, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (song.durationMs > 0)
              Text(song.durationFormatted,
                  style: SpotifyFonts.regular(
                      color: SpotifyColors.lightGrey, fontSize: 12)),
            IconButton(
              icon: const Icon(Icons.more_vert,
                  color: SpotifyColors.lightGrey, size: 22),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: SpotifyColors.surface,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                  builder: (ctx) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: song.imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: song.imageUrl,
                                    width: 56, height: 56, fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(width: 56, height: 56, color: SpotifyColors.surface))
                                : Container(width: 56, height: 56, color: SpotifyColors.surface,
                                    child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(song.title,
                                  style: SpotifyFonts.bold(color: Colors.white, fontSize: 16),
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
                  ),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ]),
        ),
      );
    });
  }
}

// ── Animated sound bars ──────────────────────────────────────────────────────
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
    _ctrls = List.generate(3, (i) => AnimationController(
        vsync: this, duration: Duration(milliseconds: 400 + i * 100))
      ..repeat(reverse: true));
  }
  @override
  void dispose() { for (final c in _ctrls) {
    c.dispose();
  } super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) => AnimatedBuilder(
          animation: _ctrls[i],
          builder: (_, __) => Container(
            width: 3,
            height: 4 + _ctrls[i].value * 10,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
                color: widget.color, borderRadius: BorderRadius.circular(1.5)),
          ),
        )),
      ),
    );
  }
}

// ── Shimmer loading tile ─────────────────────────────────────────────────────
class _ShimmerTile extends StatefulWidget {
  @override
  State<_ShimmerTile> createState() => _ShimmerTileState();
}

class _ShimmerTileState extends State<_ShimmerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final op = 0.3 + _ctrl.value * 0.3;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 15, width: 200,
                    decoration: BoxDecoration(
                        color: SpotifyColors.surface.withValues(alpha: op + 0.2),
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 6),
                Container(height: 12, width: 120,
                    decoration: BoxDecoration(
                        color: SpotifyColors.surface.withValues(alpha: op),
                        borderRadius: BorderRadius.circular(4))),
              ]),
            ),
            Container(width: 24, height: 24,
                decoration: BoxDecoration(
                    color: SpotifyColors.surface.withValues(alpha: op),
                    shape: BoxShape.circle)),
          ]),
        );
      },
    );
  }
}
