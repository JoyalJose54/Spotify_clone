import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../library/library_screen.dart';
import '../player/now_playing_screen.dart';
import '../playlist/playlist_detail_screen.dart';
import 'top_songs_screen.dart';
import 'top_artists_screen.dart';
import '../../widgets/playlist_collage.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _activeChip = 'Music';

  late final Stream<List<String>> _playlistOrderStream;
  late final Stream<List<Playlist>> _playlistsStream;
  late final Stream<List<Song>> _recentlyPlayedStream;

  @override
  void initState() {
    super.initState();
    _playlistOrderStream = FirebaseService.streamPlaylistOrder().asBroadcastStream();
    _playlistsStream = FirebaseService.streamPlaylists().asBroadcastStream();
    _recentlyPlayedStream = FirebaseService.streamRecentlyPlayed().asBroadcastStream();
    // Warm up the shared tracks stream now so the first snapshot is ready
    // before child widgets subscribe. No local reference needed —
    // FirebaseService caches the BehaviorSubject internally.
    FirebaseService.streamAllTracks();
  }

  String _greeting(BuildContext context) {
    final h = DateTime.now().hour;
    final userName = context.watch<AuthProvider>().userName;
    final nameStr = userName.isNotEmpty ? ' $userName' : '';
    if (h < 12) return 'Good morning$nameStr';
    if (h < 18) return 'Good afternoon$nameStr';
    return 'Good evening$nameStr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: const Color(0xFF121212),
            floating: true,
            snap: true,
            title: Text(_greeting(context),
                style: SpotifyFonts.title(
                    fontSize: 22, color: Colors.white))
                .animate()
                .fadeIn(duration: 400.ms),
            actions: [
              IconButton(
                  icon: const Icon(Icons.notifications_outlined), onPressed: () {}),
              IconButton(
                  icon: const Icon(Icons.history), onPressed: () {}),
              IconButton(
                  icon: const Icon(Icons.settings_outlined), onPressed: () {}),
            ],
          ),

          // ── Quick-filter chips ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2), // Reduced bottom from 8 to 2
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: ['Music', 'Podcasts & Shows', 'Audiobooks']
                    .map((c) => _QuickChip(
                          label: c,
                          isSelected: _activeChip == c,
                          onTap: () => setState(() => _activeChip = c),
                        ))
                    .toList()
                    .animate(interval: 70.ms)
                    .fadeIn()
                    .slideX(begin: 0.2, end: 0),
              ),
            ),
          ),

          // ── Top Grid (Playlists & Recently Played) ───────────────────────
          _TopGridSection(
            orderStream: _playlistOrderStream,
            playlistsStream: _playlistsStream,
            recentlyPlayedStream: _recentlyPlayedStream,
            fallbackTracksStream: FirebaseService.streamAllTracks(),
          ),


          // ── Spotify Wrapped card ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFFB74D), Color(0xFFE91E63)]),
                      ),
                      child: Center(
                        child: Text('2026',
                            style: SpotifyFonts.display(
                                color: Colors.white,
                                fontSize: 10))
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('#SPOTIFYWRAPPED',
                          style: TextStyle(
                              fontFamily: 'SpotifyMixMono',
                              color: SpotifyColors.lightGrey,
                              fontSize: 11,
                              letterSpacing: 1)),

                      Text('Your 2026 in review',
                          style: Theme.of(context).textTheme.titleLarge),
                    ]),
                  ]),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 160,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.push(context, 
                              MaterialPageRoute(builder: (_) => const TopSongsScreen())),
                          child: _WrappedCardLive(
                            gradient: const [Color(0xFFF06292), Color(0xFF7C4DFF)],
                            label: 'Your Top Songs',
                            icon: Icons.music_note_rounded,
                            dataStream: FirebaseService.streamTopTracks(limit: 1).map(
                              (entries) => entries.isEmpty ? '' : entries.first.song.title,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const TopArtistsScreen())),
                          child: _WrappedCardLive(
                            gradient: const [Color(0xFF7C4DFF), Color(0xFF00BCD4)],
                            label: 'Your Artists',
                            icon: Icons.person_rounded,
                            dataStream: FirebaseService.streamTopArtists(limit: 1).map(
                              (artists) => artists.isEmpty ? '' : artists.first.artist,
                            ),
                          ),
                        ),
                      ].animate(interval: 100.ms).fadeIn().scale(
                          begin: const Offset(0.9, 0.9)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── All Songs quick-play (live count) ────────────────────────────
          _AllSongsQuickCard(allTracksStream: FirebaseService.streamAllTracks()),

          // ── Jump Back In ───────────────────────────────────────────────
          _JumpBackInCarousel(
            recentlyPlayedStream: _recentlyPlayedStream,
            fallbackTracksStream: FirebaseService.streamAllTracks(),
          ),


          // ── Recommended For Today ───────────────────────────────────────
          _RecommendedForTodayCarousel(playlistsStream: _playlistsStream),

          // ── Made for you ──────────────────────────────────────────────────
          _PlaylistCarousel(
            orderStream: _playlistOrderStream,
            playlistsStream: _playlistsStream,
          ),

          // ── Recommended Stations ──────────────────────────────────────────
          _RecommendedStationsSection(allTracksStream: FirebaseService.streamAllTracks()),

          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top Grid – live stream, 2 columns (Playlists in first row, then Songs)
// ─────────────────────────────────────────────────────────────────────────────
class _TopGridSection extends StatelessWidget {
  final Stream<List<String>> orderStream;
  final Stream<List<Playlist>> playlistsStream;
  final Stream<List<Song>> recentlyPlayedStream;
  // Shared tracks stream (Stream<List<Song>>) used as fallback when no history
  final Stream<List<Song>> fallbackTracksStream;

  const _TopGridSection({
    required this.orderStream,
    required this.playlistsStream,
    required this.recentlyPlayedStream,
    required this.fallbackTracksStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: orderStream,
      builder: (context, orderSnap) {
        final order = orderSnap.data ?? [];
        return StreamBuilder<List<Playlist>>(
          stream: playlistsStream,
          builder: (context, playlistSnap) {
            var playlists = playlistSnap.data ?? [];
            if (playlists.isNotEmpty) {
              playlists = List.from(playlists);
              playlists.sort((a, b) {
                int iA = getPlaylistOrderIndex(a, order);
                int iB = getPlaylistOrderIndex(b, order);
                if (iA != iB) return iA.compareTo(iB);
                return a.name.compareTo(b.name);
              });
            }
            
            return StreamBuilder<List<Song>>(
              stream: recentlyPlayedStream,
              builder: (context, songSnap) {
                // Fall back to all tracks from shared stream when no history exists
                if (!songSnap.hasData || songSnap.data!.isEmpty) {
                  return StreamBuilder<List<Song>>(
                    stream: fallbackTracksStream,
                    builder: (context, snap) {
                      final fallbackSongs = snap.data ?? [];
                      return _buildGrid(context, playlists, fallbackSongs);
                    },
                  );
                }
                return _buildGrid(context, playlists, songSnap.data!);
              },

            );
          },
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, List<Playlist> playlists, List<Song> songs) {
    // Up to 2 playlists for the first row
    final displayPlaylists = playlists.take(2).toList();
    // Fill the rest of an 8-item grid with songs
    final displaySongs = songs.take(8 - displayPlaylists.length).toList();
    
    final items = [...displayPlaylists, ...displaySongs];
    
    if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 3.4,
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            if (item is Playlist) return _PlaylistGridCard(playlist: item);
            return _RecentCard(song: item as Song);
          },
        ),
      ),
    );
  }
}

class _PlaylistGridCard extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistGridCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (playlist.id == 'all_songs') {
          showPasswordChallenge(context, playlist);
        } else {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlist: playlist)));
        }
      },
      child: Container(
        decoration: BoxDecoration(
            color: SpotifyColors.surface,
            borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
            child: PlaylistCollage(
              playlist: playlist,
              currentTracks: playlist.tracks,
              size: 52,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(playlist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SpotifyFonts.bold(
                    color: SpotifyColors.white,
                    fontSize: 12)),
          ),
          const SizedBox(width: 6),
        ]),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final Song song;
  const _RecentCard({required this.song});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final p = context.read<PlayerProvider>();
        p.playSong(song);
        _openPlayer(context, song);
      },
      child: Container(
        decoration: BoxDecoration(
            color: SpotifyColors.surface,
            borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
            child: song.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: song.imageUrl,
                    width: 52, height: 52, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholder())
                : _placeholder(),

          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SpotifyFonts.bold(
                    color: SpotifyColors.white,
                    fontSize: 12)),
          ),
          const SizedBox(width: 6),
        ]),
      ),
    );
  }

  void _openPlayer(BuildContext context, Song song) {
    openNowPlaying(context, song);
  }

  Widget _placeholder() =>
      Container(width: 52, height: 52, color: SpotifyColors.darkGrey);
}

// ─────────────────────────────────────────────────────────────────────────────
//  All Songs quick-play banner (live track count)
// ─────────────────────────────────────────────────────────────────────────────
class _AllSongsQuickCard extends StatelessWidget {
  // Now receives the shared Stream<List<Song>> instead of Stream<QuerySnapshot>
  final Stream<List<Song>> allTracksStream;
  const _AllSongsQuickCard({required this.allTracksStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Song>>(
      stream: allTracksStream,
      builder: (context, snapshot) {
        final songs = snapshot.data ?? [];
        final count = songs.length;

        return SliverToBoxAdapter(
          child: GestureDetector(
            onTap: songs.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PlaylistDetailScreen(
                              playlist: Playlist(
                                id: 'all_songs',
                                name: 'All Your Songs',
                                description: '${songs.length} songs',
                                owner: 'Your Library',
                                imageUrl: '',
                                tracks: songs,
                              ),
                            ))),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    SpotifyColors.green.withValues(alpha: 0.8),
                    const Color(0xFF148A08),
                  ],
                ),
              ),
              child: Row(children: [
                const Icon(Icons.library_music,
                    color: Colors.white, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('All Your Songs',
                            style: TextStyle(
                                fontFamily: 'SpotifyMixUIBold',
                                color: Colors.white,
                                fontSize: 17)),
                        Text(
                            count == 0
                                ? 'Loading…'
                                : '$count songs • Tap to play',
                            style: SpotifyFonts.regular(
                                color: Colors.white70, fontSize: 12)),
                      ]),
                ),
                Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow,
                      color: SpotifyColors.green, size: 28),
                ),
              ]),
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Jump Back In carousel
// ─────────────────────────────────────────────────────────────────────────────
class _JumpBackInCarousel extends StatelessWidget {
  final Stream<List<Song>> recentlyPlayedStream;
  // Shared tracks stream as fallback when user has no history yet
  final Stream<List<Song>> fallbackTracksStream;

  const _JumpBackInCarousel({
    required this.recentlyPlayedStream,
    required this.fallbackTracksStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Song>>(
      stream: recentlyPlayedStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          // Fall back to shared tracks stream — no new Firestore connection
          return StreamBuilder<List<Song>>(
            stream: fallbackTracksStream,
            builder: (context, snap) {
              final fallbackSongs = snap.data ?? [];
              if (fallbackSongs.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
              return _buildCarousel(fallbackSongs.take(5).toList());
            },
          );
        }
        final songs = snapshot.data!.take(5).toList();
        return _buildCarousel(songs);
      },
    );
  }

  Widget _buildCarousel(List<Song> songs) {
    return SliverList(
      delegate: SliverChildListDelegate([
        const _SectionHeaderInline(title: "Jump back in"),
        SizedBox(
          height: 200,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: songs.length,
            itemBuilder: (ctx, i) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _SongCard(
                  song: songs[i],
                  playlist: songs,
                  playlistName: "Jump back in",
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Recommended For Today (1 random song per playlist, seed by day)
// ─────────────────────────────────────────────────────────────────────────────
class _RecommendedForTodayCarousel extends StatelessWidget {
  final Stream<List<Playlist>> playlistsStream;
  const _RecommendedForTodayCarousel({required this.playlistsStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Playlist>>(
      stream: playlistsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        
        final playlists = snapshot.data!;
        final today = DateTime.now().day;
        final List<Song> recommendedSongs = [];
        
        for (var pl in playlists) {
          if (pl.tracks.isNotEmpty) {
            // Pick a song based on today's day
            final index = (today + pl.id.hashCode).abs() % pl.tracks.length;
            recommendedSongs.add(pl.tracks[index]);
          }
        }
        
        if (recommendedSongs.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
        
        return SliverList(
          delegate: SliverChildListDelegate([
            const _SectionHeaderInline(title: "Recommended for today"),
            SizedBox(
              height: 200,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: recommendedSongs.length,
                itemBuilder: (ctx, i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _SongCard(
                      song: recommendedSongs[i],
                      playlist: recommendedSongs,
                      playlistName: "Recommended for today",
                    ),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _SongCard extends StatelessWidget {
  final Song song;
  final List<Song>? playlist;
  final String? playlistName;

  const _SongCard({
    required this.song,
    this.playlist,
    this.playlistName,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final p = context.read<PlayerProvider>();
        p.playSong(song, playlist: playlist, playlistName: playlistName);
        openNowPlaying(context, song);
      },
      child: SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: song.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: song.imageUrl,
                    width: 140, height: 140, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholder())
                : _placeholder(),

          ),
          const SizedBox(height: 6),
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
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
          color: SpotifyColors.surface,
          borderRadius: BorderRadius.circular(6)),
      child: const Icon(Icons.music_note,
          color: SpotifyColors.lightGrey, size: 40));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Playlists carousel (Firestore `playlists` collection)
// ─────────────────────────────────────────────────────────────────────────────
class _PlaylistCarousel extends StatelessWidget {
  final Stream<List<String>> orderStream;
  final Stream<List<Playlist>> playlistsStream;

  const _PlaylistCarousel({
    required this.orderStream,
    required this.playlistsStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: orderStream,
      builder: (context, orderSnap) {
        final order = orderSnap.data ?? [];
        return StreamBuilder<List<Playlist>>(
          stream: playlistsStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            var playlists = snapshot.data!;
            if (playlists.isNotEmpty) {
              playlists = List.from(playlists);
              playlists.sort((a, b) {
                int iA = getPlaylistOrderIndex(a, order);
                int iB = getPlaylistOrderIndex(b, order);
                if (iA != iB) return iA.compareTo(iB);
                return a.name.compareTo(b.name);
              });
            }
            
            return SliverList(
              delegate: SliverChildListDelegate([
                const _SectionHeaderInline(title: "Your Playlists"),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: playlists.length,
                    itemBuilder: (ctx, i) {
                      final pl = playlists[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _PlaylistCard(playlist: pl),
                      );
                    },
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (playlist.id == 'all_songs') {
          showPasswordChallenge(context, playlist);
        } else {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlist: playlist)));
        }
      },
      child: SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: PlaylistCollage(
              playlist: playlist,
              currentTracks: playlist.tracks,
              size: 140,
            ),
          ),
          const SizedBox(height: 6),
          Text(playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpotifyFonts.bold(
                  color: SpotifyColors.white,
                  fontSize: 13)),
          Text(playlist.owner,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpotifyFonts.regular(
                  color: SpotifyColors.lightGrey, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────
class _QuickChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _QuickChip(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected ? SpotifyColors.green : SpotifyColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              fontFamily: isSelected ? 'SpotifyMixUIBold' : 'SpotifyMixUI',
              color: isSelected ? SpotifyColors.black : SpotifyColors.white,
              fontSize: 13,
            )),

      ),
    );
  }
}


class _WrappedCardLive extends StatelessWidget {
  final List<Color> gradient;
  final String label;
  final IconData icon;
  final Stream<String>? dataStream;

  const _WrappedCardLive({
    required this.gradient,
    required this.label,
    required this.icon,
    this.dataStream,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(children: [
        // Background icon watermark
        Positioned(
          right: -12,
          top: -12,
          child: Icon(icon, size: 90, color: Colors.white.withValues(alpha: 0.08)),
        ),

        Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const Spacer(),
            if (dataStream != null)
              StreamBuilder<String>(
                stream: dataStream,
                builder: (context, snap) {
                  final sub = snap.data ?? '';
                  if (sub.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                },
              ),
            Text(
              label,
              style: SpotifyFonts.bold(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Text('Tap to view',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 10)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 9, color: Colors.white.withValues(alpha: 0.6)),
            ]),
          ],
        )),
      ]),
    );
  }
}

// Keep old _WrappedCard for reference (unused but safe)
// ignore: unused_element
class _WrappedCard extends StatelessWidget {
  final List<Color> gradient;
  final String label;
  const _WrappedCard({required this.gradient, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient),
          borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.bottomLeft,
          child: Text(label,
              style: SpotifyFonts.bold(
                  color: Colors.white,
                  fontSize: 14)),

      ),
    );
  }
}



class _SectionHeaderInline extends StatelessWidget {
  final String title;
  const _SectionHeaderInline({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}


int getPlaylistOrderIndex(Playlist playlist, List<String> userOrder) {
  if (userOrder.isNotEmpty) {
    int idx = userOrder.indexWhere((o) =>
        o.trim().toLowerCase() == playlist.id.trim().toLowerCase() ||
        o.trim().toLowerCase() == playlist.name.trim().toLowerCase());
    if (idx != -1) return idx;
  } else {
    const List<String> defaultOrder = [
      '🥹🫶🏻',
      '🥹🫶',
      '🫶🏻🫠',
      '🫶🫠',
      '⚡️⚡️',
      '⚡⚡',
      'QiCFfgk2kGBVXFQfOGBU',
      '🫠 🥹',
      '🫠🥹',
      'Sangeeetham!!',
      '🏋️‍♀️🏋️‍♀️',
      '🏋‍♀️🏋‍♀️',
      '🏋🏋',
    ];
    int idx = defaultOrder.indexWhere((o) =>
        o.trim().toLowerCase() == playlist.id.trim().toLowerCase() ||
        o.trim().toLowerCase() == playlist.name.trim().toLowerCase());
    if (idx != -1) return idx;
  }
  return 999999;
}


// ─────────────────────────────────────────────────────────────────────────────
//  Recommended Stations Section (Radio)
// ─────────────────────────────────────────────────────────────────────────────
class _RecommendedStationsSection extends StatelessWidget {
  final Stream<List<Song>> allTracksStream;
  const _RecommendedStationsSection({required this.allTracksStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Song>>(
      stream: allTracksStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final allSongs = snapshot.data!;
        
        // Group songs by artist
        final Map<String, List<Song>> artistTracks = {};
        for (var song in allSongs) {
          if (song.artist.isEmpty || song.artist == 'Unknown Artist') continue;
          artistTracks.putIfAbsent(song.artist, () => []).add(song);
        }

        if (artistTracks.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        // Distinct list of artists
        final artists = artistTracks.keys.toList();
        
        return SliverList(
          delegate: SliverChildListDelegate([
            _buildHeader(context),
            SizedBox(
              height: 220,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: artists.length,
                itemBuilder: (ctx, i) {
                  final artistName = artists[i];
                  final artistSongs = artistTracks[artistName]!;
                  
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _StationCard(
                      artistName: artistName,
                      artistSongs: artistSongs,
                      allSongs: allSongs,
                    ),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Non-stop music based on your favourite songs and artists.',
            style: SpotifyFonts.regular(
              color: SpotifyColors.lightGrey,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recommended Stations',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                ),
              ),
              Text(
                'Show all',
                style: SpotifyFonts.bold(
                  color: SpotifyColors.lightGrey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  final String artistName;
  final List<Song> artistSongs;
  final List<Song> allSongs;

  const _StationCard({
    required this.artistName,
    required this.artistSongs,
    required this.allSongs,
  });

  @override
  Widget build(BuildContext context) {
    // Generate playlist queue for this station (artist tracks first, then pad up to 15 songs)
    final stationQueue = <Song>[...artistSongs];
    for (var song in allSongs) {
      if (stationQueue.length >= 15) break;
      if (!stationQueue.contains(song)) {
        stationQueue.add(song);
      }
    }

    // Circular images: Center, Left, Right
    final centerImage = artistSongs.isNotEmpty ? artistSongs[0].imageUrl : '';
    String leftImage = '';
    String rightImage = '';

    if (artistSongs.length > 1) {
      leftImage = artistSongs[1].imageUrl;
    } else {
      final idx = (artistName.hashCode + 1).abs() % allSongs.length;
      leftImage = allSongs[idx].imageUrl;
    }

    if (artistSongs.length > 2) {
      rightImage = artistSongs[2].imageUrl;
    } else {
      final idx = (artistName.hashCode + 2).abs() % allSongs.length;
      rightImage = allSongs[idx].imageUrl;
    }

    // Determine deterministic color based on artist name hash code
    final colors = [
      const Color(0xFFE57373), // Red pastel
      const Color(0xFFF06292), // Pink
      const Color(0xFFBA68C8), // Purple
      const Color(0xFF7986CB), // Indigo
      const Color(0xFF64B5F6), // Blue
      const Color(0xFF4DD0E1), // Cyan
      const Color(0xFF4DB6AC), // Teal
      const Color(0xFF81C784), // Green
      const Color(0xFFAED581), // Lime Green
      const Color(0xFFFFD54F), // Amber/Yellow
      const Color(0xFFFFB74D), // Orange
      const Color(0xFFFF8A65), // Deep Orange
    ];
    final cardColor = colors[(artistName.hashCode).abs() % colors.length];

    // Build the "With ..." subtitle text listing featured artists
    final featuredArtists = stationQueue
        .map((s) => s.artist)
        .where((a) => a != artistName && a.isNotEmpty && a != 'Unknown Artist')
        .toSet()
        .take(3)
        .toList();
    final subtitle = 'With ${[artistName, ...featuredArtists].join(', ')}...';

    return GestureDetector(
      onTap: () {
        if (stationQueue.isNotEmpty) {
          final p = context.read<PlayerProvider>();
          p.playSong(stationQueue[0], playlist: stationQueue, playlistName: '$artistName Radio');
          openNowPlaying(context, stationQueue[0]);
        }
      },
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored station card container
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  // Top bar: Spotify-like logo + "RADIO"
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Image.asset(
                          'assets/images/logo.webp',
                          width: 14,
                          height: 14,
                          color: Colors.black.withValues(alpha: 0.65),
                        ),
                        Text(
                          'RADIO',
                          style: SpotifyFonts.bold(
                            color: Colors.black.withValues(alpha: 0.65),
                            fontSize: 9,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Middle: 3 overlapping circular images
                  Align(
                    alignment: const Alignment(0, -0.1),
                    child: SizedBox(
                      width: 130,
                      height: 70,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Left circle
                          Positioned(
                            left: 10,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: cardColor, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 4,
                                    offset: const Offset(-2, 2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: leftImage.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: leftImage,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => _placeholderCircle(),
                                      )
                                    : _placeholderCircle(),
                              ),
                            ),
                          ),

                          // Right circle
                          Positioned(
                            right: 10,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: cardColor, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 4,
                                    offset: const Offset(2, 2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: rightImage.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: rightImage,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => _placeholderCircle(),
                                      )
                                    : _placeholderCircle(),
                              ),
                            ),
                          ),

                          // Center circle (renders on top)
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: cardColor, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: centerImage.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: centerImage,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => _placeholderCircle(),
                                    )
                                  : _placeholderCircle(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom: Station Title
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Text(
                      artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpotifyFonts.bold(
                        color: Colors.black,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Station description below card container
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SpotifyFonts.regular(
                color: SpotifyColors.lightGrey,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderCircle() {
    return Container(
      color: const Color(0xFF333333),
      child: const Icon(
        Icons.music_note,
        color: Colors.grey,
        size: 24,
      ),
    );
  }
}

