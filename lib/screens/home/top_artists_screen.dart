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
//  TopArtistsScreen  –  streams the user's most-played artists.
// ─────────────────────────────────────────────────────────────────────────────
class TopArtistsScreen extends StatelessWidget {
  const TopArtistsScreen({super.key});

  static const _bg = Color(0xFF060818);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<List<({String artist, int totalPlays, List<Song> songs, String imageUrl})>>(
        stream: FirebaseService.streamTopArtists(limit: 5),
        builder: (context, snap) {
          final loading = snap.connectionState == ConnectionState.waiting && !snap.hasData;
          if (loading) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00BCD4)),
            );
          }

          final artists = snap.data ?? [];

          if (artists.isEmpty) {
            return _EmptyState();
          }

          return Stack(children: [
            // ── Blurred ambient background ─────────────────────────────
            if (artists.first.imageUrl.isNotEmpty)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                  child: CachedNetworkImage(
                    imageUrl: artists.first.imageUrl,
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
                      _bg.withValues(alpha: 0.6),
                      _bg.withValues(alpha: 0.9),
                      _bg,
                    ],
                    stops: const [0.0, 0.35, 0.7],
                  ),
                ),
              ),
            ),

            // ── Scrollable content ─────────────────────────────────────
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _ArtistsAppBar(topArtist: artists.first),
                SliverToBoxAdapter(
                  child: Column(children: [
                    // Podium (top 3)
                    if (artists.length >= 3)
                      _PodiumSection(artists: artists.take(3).toList())
                          .animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),

                    const SizedBox(height: 24),

                    // Bar chart list for all artists
                    _ArtistBarList(artists: artists),

                    const SizedBox(height: 100),
                  ]),
                ),
              ],
            ),
          ]);
        },
      ),
    );
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────
class _ArtistsAppBar extends StatelessWidget {
  final ({String artist, int totalPlays, List<Song> songs, String imageUrl}) topArtist;
  const _ArtistsAppBar({required this.topArtist});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 240,
      backgroundColor: Colors.transparent,
      pinned: true,
      elevation: 0,
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
            Text(
              'YOUR TOP ARTISTS',
              style: TextStyle(
                fontFamily: 'SpotifyMixMono',
                fontSize: 9,
                letterSpacing: 3,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '2026',
              style: SpotifyFonts.display(color: Colors.white, fontSize: 34),
            ),
          ],
        ),
        background: _HeroMosaic(songs: topArtist.songs),
      ),
    );
  }
}

// ── Hero Mosaic: top artist's songs ──────────────────────────────────────────
class _HeroMosaic extends StatelessWidget {
  final List<Song> songs;
  const _HeroMosaic({required this.songs});

  @override
  Widget build(BuildContext context) {
    final imgs = songs.where((s) => s.imageUrl.isNotEmpty).take(6).toList();

    return Stack(fit: StackFit.expand, children: [
      if (imgs.length >= 4)
        GridView.count(
          crossAxisCount: 3,
          physics: const NeverScrollableScrollPhysics(),
          children: imgs.map((s) => CachedNetworkImage(
            imageUrl: s.imageUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: const Color(0xFF111130)),
          )).toList(),
        )
      else if (imgs.isNotEmpty)
        CachedNetworkImage(
          imageUrl: imgs.first.imageUrl,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: const Color(0xFF111130)),
        ),
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x30060818), Color(0xBB060818), Color(0xFF060818)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
      ),
    ]);
  }
}

// ── Podium (ranks 1–3) ───────────────────────────────────────────────────────
class _PodiumSection extends StatelessWidget {
  final List<({String artist, int totalPlays, List<Song> songs, String imageUrl})> artists;
  const _PodiumSection({required this.artists});

  @override
  Widget build(BuildContext context) {
    // Order: 2nd, 1st, 3rd (classic podium)
    final order = artists.length >= 3
        ? [artists[1], artists[0], artists[2]]
        : artists;
    final heights = [130.0, 170.0, 110.0]; // podium column heights
    final ringColors = [
      const Color(0xFFC0C0C0), // silver
      const Color(0xFFFFD700), // gold
      const Color(0xFFCD7F32), // bronze
    ];
    final ranks = [2, 1, 3];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        const SizedBox(height: 8),
        Text(
          'Hall of Fame',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            letterSpacing: 3,
            fontFamily: 'SpotifyMixMono',
          ),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(order.length, (i) {
            final a = order[i];
            return _PodiumSlot(
              artist: a,
              height: heights[i],
              ringColor: ringColors[i],
              rank: ranks[i],
            )
                .animate(delay: (i * 120).ms)
                .fadeIn()
                .slideY(begin: 0.3, end: 0);
          }),
        ),
      ]),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  final ({String artist, int totalPlays, List<Song> songs, String imageUrl}) artist;
  final double height;
  final Color ringColor;
  final int rank;

  const _PodiumSlot({
    required this.artist,
    required this.height,
    required this.ringColor,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Avatar with ring
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [ringColor, ringColor.withValues(alpha: 0.5)],
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: artist.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: artist.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _ArtistInitialCircle(name: artist.artist, color: ringColor),
                    )
                  : _ArtistInitialCircle(name: artist.artist, color: ringColor),
            ),
          ),
          const SizedBox(height: 6),

          // Artist name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              artist.artist,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Play count
          Text(
            '${artist.totalPlays} plays',
            style: TextStyle(color: ringColor, fontSize: 10, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // Podium block
          Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ringColor.withValues(alpha: 0.3),
                  ringColor.withValues(alpha: 0.08),
                ],
              ),
              border: Border(
                top: BorderSide(color: ringColor.withValues(alpha: 0.6), width: 2),
                left: BorderSide(color: ringColor.withValues(alpha: 0.2)),
                right: BorderSide(color: ringColor.withValues(alpha: 0.2)),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: TextStyle(
                color: ringColor,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Artist initial circle (fallback avatar) ───────────────────────────────────
class _ArtistInitialCircle extends StatelessWidget {
  final String name;
  final Color color;
  const _ArtistInitialCircle({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.2),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: color,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ── Bar chart list for all artists ───────────────────────────────────────────
class _ArtistBarList extends StatelessWidget {
  final List<({String artist, int totalPlays, List<Song> songs, String imageUrl})> artists;
  const _ArtistBarList({required this.artists});

  @override
  Widget build(BuildContext context) {
    final maxPlays = artists.isEmpty ? 1 : artists.first.totalPlays;
    final gradients = [
      [const Color(0xFFFFD700), const Color(0xFFFFA000)],
      [const Color(0xFFC0C0C0), const Color(0xFF78909C)],
      [const Color(0xFFCD7F32), const Color(0xFF8D6E63)],
      [const Color(0xFF7C4DFF), const Color(0xFF00BCD4)],
      [const Color(0xFFE040FB), const Color(0xFF7C4DFF)],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Play Distribution',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                letterSpacing: 2,
                fontFamily: 'SpotifyMixMono',
              ),
            ),
          ),
          ...artists.asMap().entries.map((entry) {
            final i = entry.key;
            final a = entry.value;
            final fraction = maxPlays > 0 ? a.totalPlays / maxPlays : 0.0;
            final grad = gradients[i % gradients.length];

            return _ArtistBarCard(
              artist: a,
              rank: i + 1,
              barFraction: fraction,
              gradColors: grad,
            )
                .animate(delay: (200 + i * 80).ms)
                .fadeIn()
                .slideX(begin: 0.2, end: 0);
          }),
        ],
      ),
    );
  }
}

class _ArtistBarCard extends StatelessWidget {
  final ({String artist, int totalPlays, List<Song> songs, String imageUrl}) artist;
  final int rank;
  final double barFraction;
  final List<Color> gradColors;

  const _ArtistBarCard({
    required this.artist,
    required this.rank,
    required this.barFraction,
    required this.gradColors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (artist.songs.isEmpty) return;
        context.read<PlayerProvider>().playSong(
          artist.songs.first,
          playlist: artist.songs,
          playlistName: artist.artist,
        );
        openNowPlaying(context, artist.songs.first);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: gradColors[0].withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: gradColors[0], width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: artist.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: artist.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _ArtistInitialCircle(name: artist.artist, color: gradColors[0]),
                    )
                  : _ArtistInitialCircle(name: artist.artist, color: gradColors[0]),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  // Rank badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(colors: gradColors),
                    ),
                    child: Text(
                      '#$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      artist.artist,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  '${artist.totalPlays} plays  •  ${artist.songs.length} songs',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                ),
              ]),
            ),

            Icon(Icons.play_circle_fill_rounded, color: gradColors[0], size: 28),
          ]),

          const SizedBox(height: 10),

          // Play count bar
          LayoutBuilder(builder: (context, constraints) {
            return Stack(children: [
              // Background track
              Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              // Filled portion
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOut,
                height: 4,
                width: constraints.maxWidth * barFraction,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(colors: gradColors),
                  boxShadow: [
                    BoxShadow(
                      color: gradColors[0].withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ]);
          }),
        ]),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060818),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF7C4DFF), Color(0xFF00BCD4)],
              ),
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 52),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 0.95, end: 1.05, duration: 1500.ms),
          const SizedBox(height: 24),
          Text(
            'No Artists Yet',
            style: SpotifyFonts.display(color: Colors.white, fontSize: 22),
          ),
          const SizedBox(height: 10),
          Text(
            'Play some songs to see your\ntop artists revealed here!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ]),
      ),
    );
  }
}
