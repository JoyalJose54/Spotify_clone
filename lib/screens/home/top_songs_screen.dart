import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../player/now_playing_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  TopSongsScreen  –  streams the user's most-played songs.
//  Falls back to a shuffled sample when there is no play history yet.
// ─────────────────────────────────────────────────────────────────────────────
class TopSongsScreen extends StatelessWidget {
  const TopSongsScreen({super.key});

  static const _bg = Color(0xFF0A0012);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<List<({Song song, int count})>>(
        stream: FirebaseService.streamTopTracks(limit: 10),
        builder: (context, snap) {
          final hasData = snap.hasData && snap.data!.isNotEmpty;

          // While loading
          if (snap.connectionState == ConnectionState.waiting && !hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFE040FB)),
            );
          }

          // If no play history yet, fall back to a shuffled preview
          if (!hasData) {
            return _FallbackBuilder(bg: _bg);
          }

          final entries = snap.data!;
          final topSong = entries.first.song;

          return Stack(
            children: [
              // ── Blurred background from #1 song cover ───────────────────
              if (topSong.imageUrl.isNotEmpty)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                    child: CachedNetworkImage(
                      imageUrl: topSong.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _bg.withValues(alpha: 0.55),
                        _bg.withValues(alpha: 0.85),
                        _bg,
                      ],
                      stops: const [0.0, 0.4, 0.8],
                    ),
                  ),
                ),
              ),

              // ── Main scrollable content ──────────────────────────────────
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // App bar
                  SliverAppBar(
                    expandedHeight: 300,
                    backgroundColor: Colors.transparent,
                    pinned: true,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding:
                          const EdgeInsets.only(left: 16, bottom: 20),
                      title: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR TOP SONGS',
                            style: TextStyle(
                              fontFamily: 'SpotifyMixMono',
                              fontSize: 10,
                              letterSpacing: 3,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '2026',
                            style: SpotifyFonts.display(
                              color: Colors.white,
                              fontSize: 36,
                            ),
                          ),
                        ],
                      ),
                      background: _HeroBanner(songs: entries.map((e) => e.song).toList()),
                    ),
                  ),

                  // Stats bar
                  SliverToBoxAdapter(
                    child: _StatsBar(entries: entries).animate().fadeIn(delay: 200.ms),
                  ),

                  // Song list
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _TopSongRow(
                          song: entries[i].song,
                          count: entries[i].count,
                          rank: i + 1,
                          maxCount: entries.first.count,
                          playlist: entries.map((e) => e.song).toList(),
                        ).animate().fadeIn(delay: (i * 60).ms).slideX(begin: 0.15, end: 0),
                        childCount: entries.length,
                      ),
                    ),
                  ),
                ],
              ),

              // ── Floating play button ────────────────────────────────────
              Positioned(
                bottom: 32,
                right: 24,
                child: _FloatingPlayBtn(songs: entries.map((e) => e.song).toList()),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Fallback when user has no play history ────────────────────────────────────
class _FallbackBuilder extends StatefulWidget {
  final Color bg;
  const _FallbackBuilder({required this.bg});

  @override
  State<_FallbackBuilder> createState() => _FallbackBuilderState();
}

class _FallbackBuilderState extends State<_FallbackBuilder> {
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    FirebaseService.fetchAllTracks().then((all) {
      all.shuffle();
      if (mounted) setState(() { _songs = all.take(10).toList(); _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE040FB)));
    }
    final entries = _songs
        .asMap()
        .entries
        .map((e) => (song: e.value, count: 0))
        .toList();

    return Stack(children: [
      CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
        SliverAppBar(
          expandedHeight: 280,
          backgroundColor: Colors.transparent,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 16, bottom: 20),
            title: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR TOP SONGS',
                    style: TextStyle(fontFamily: 'SpotifyMixMono', fontSize: 10, letterSpacing: 3, color: Colors.white60)),
                const SizedBox(height: 2),
                Text('2026', style: SpotifyFonts.display(color: Colors.white, fontSize: 36)),
              ],
            ),
            background: _HeroBanner(songs: _songs),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Start playing songs to see your real top chart!',
                style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 120),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _TopSongRow(
                song: entries[i].song,
                count: 0,
                rank: i + 1,
                maxCount: 1,
                playlist: _songs,
              ).animate().fadeIn(delay: (i * 60).ms).slideX(begin: 0.15, end: 0),
              childCount: entries.length,
            ),
          ),
        ),
      ]),
      Positioned(
        bottom: 32, right: 24,
        child: _FloatingPlayBtn(songs: _songs),
      ),
    ]);
  }
}

// ── Hero banner: stacked album art mosaic ────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  final List<Song> songs;
  const _HeroBanner({required this.songs});

  @override
  Widget build(BuildContext context) {
    final imgs = songs.where((s) => s.imageUrl.isNotEmpty).take(4).toList();

    return Stack(fit: StackFit.expand, children: [
      // Mosaic of top 4 cover arts
      if (imgs.length >= 4)
        GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: imgs.map((s) => CachedNetworkImage(
            imageUrl: s.imageUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: const Color(0xFF1A1A2E)),
          )).toList(),
        )
      else if (imgs.isNotEmpty)
        CachedNetworkImage(
          imageUrl: imgs.first.imageUrl,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: const Color(0xFF1A1A2E)),
        ),

      // Gradient overlay
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x220A0012), Color(0xCC0A0012), Color(0xFF0A0012)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
      ),
    ]);
  }
}

// ── Stats bar: total plays + song count ──────────────────────────────────────
class _StatsBar extends StatelessWidget {
  final List<({Song song, int count})> entries;
  const _StatsBar({required this.entries});

  @override
  Widget build(BuildContext context) {
    final totalPlays = entries.fold<int>(0, (s, e) => s + e.count);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(children: [
        _StatChip(icon: Icons.music_note_rounded, label: '${entries.length} songs', color: const Color(0xFFE040FB)),
        const SizedBox(width: 16),
        _StatChip(icon: Icons.play_circle_fill_rounded, label: '$totalPlays total plays', color: const Color(0xFF64FFDA)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)]),
          ),
          child: const Text('2026', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }
}

// ── Individual song row ───────────────────────────────────────────────────────
class _TopSongRow extends StatelessWidget {
  final Song song;
  final int count;
  final int rank;
  final int maxCount;
  final List<Song> playlist;

  const _TopSongRow({
    required this.song,
    required this.count,
    required this.rank,
    required this.maxCount,
    required this.playlist,
  });

  static const _rankGradients = [
    [Color(0xFFFFD700), Color(0xFFFFA000)], // #1 gold
    [Color(0xFFC0C0C0), Color(0xFF9E9E9E)], // #2 silver
    [Color(0xFFCD7F32), Color(0xFF8D6E63)], // #3 bronze
  ];

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    final gradColors = isTop3 ? _rankGradients[rank - 1] : null;
    final barFraction = maxCount > 0 ? (count / maxCount).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () {
        context.read<PlayerProvider>().playSong(song, playlist: playlist, playlistName: 'Top Songs 2026');
        openNowPlaying(context, song);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.04),
          border: isTop3
              ? Border.all(
                  color: gradColors![0].withValues(alpha: 0.4),
                  width: 1,
                )
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(children: [
            // ── Rank-colored bar (width proportional to play count) ───────
            if (count > 0)
              Positioned(
                left: 0, bottom: 0, top: 0,
                width: MediaQuery.of(context).size.width * 0.85 * barFraction,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isTop3
                          ? gradColors!.map((c) => c.withValues(alpha: 0.12)).toList()
                          : [
                              const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                              const Color(0xFFE040FB).withValues(alpha: 0.04),
                            ],
                    ),
                  ),
                ),
              ),

            // ── Content row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                // Rank badge
                SizedBox(
                  width: 34,
                  child: isTop3
                      ? ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: gradColors!,
                          ).createShader(bounds),
                          child: Text(
                            '#$rank',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Text(
                          '#$rank',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),

                const SizedBox(width: 10),

                // Cover art
                Hero(
                  tag: 'top_song_cover_${song.id}',
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: isTop3
                          ? [
                              BoxShadow(
                                color: gradColors![0].withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: song.imageUrl.isNotEmpty
                        ? CachedNetworkImage(imageUrl: song.imageUrl, fit: BoxFit.cover)
                        : Container(color: const Color(0xFF1E1E2E)),
                  ),
                ),

                const SizedBox(width: 14),

                // Title + artist + play bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Play count badge
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🔥', style: TextStyle(fontSize: 10)),
                      const SizedBox(width: 3),
                      Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Floating play button ──────────────────────────────────────────────────────
class _FloatingPlayBtn extends StatelessWidget {
  final List<Song> songs;
  const _FloatingPlayBtn({required this.songs});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (songs.isEmpty) return;
        context.read<PlayerProvider>().playSong(songs.first, playlist: songs, playlistName: 'Top Songs 2026');
        openNowPlaying(context, songs.first);
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
      ),
    );
  }
}
