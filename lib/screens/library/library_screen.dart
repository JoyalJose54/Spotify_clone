import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../player/now_playing_screen.dart';
import '../playlist/playlist_detail_screen.dart';
import '../ingestion/ingestion_page.dart';
import '../../widgets/track_list_tile.dart';
import '../../widgets/playlist_collage.dart';



class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {

  String _activeFilter = 'All';
  bool   _isGridView   = false;

  final List<String> _filters = ['Playlists', 'Artists', 'Albums'];

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
            title: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: SpotifyColors.surface,
                  child: Icon(Icons.person, color: SpotifyColors.lightGrey, size: 20),
                ),
                SizedBox(width: 12),
                Text('Your Library',
                    style: SpotifyFonts.title(fontSize: 22)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add, size: 28),
                onPressed: () => _showCreateOptions(context),
              ),
            ],
          ),

          // ── Filter chips ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: _filters.map((f) {
                  final active = _activeFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _activeFilter = active ? 'All' : f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: active ? SpotifyColors.white : SpotifyColors.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(f,
                            style: SpotifyFonts.bold(
                              color: active ? SpotifyColors.black : SpotifyColors.white,
                              fontSize: 13,
                            )),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Sort + view toggle ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Row(children: [
                    const Icon(Icons.swap_vert, color: SpotifyColors.white, size: 16),
                    SizedBox(width: 6),
                    Text('Recently added',
                        style: SpotifyFonts.bold(color: SpotifyColors.white, fontSize: 13)),
                  ]),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _isGridView = !_isGridView),
                    child: Icon(_isGridView ? Icons.list : Icons.grid_view,
                        color: SpotifyColors.white, size: 22),
                  ),
                ],
              ),
            ),
          ),

          // ══════════════════════════════════════════════════════════════════
          //  "ALL YOUR SONGS" ENTRY AND PLAYLISTS
          // ══════════════════════════════════════════════════════════════════
          if (_activeFilter == 'All' || _activeFilter == 'Playlists') ...[
            if (!_isGridView)
              SliverToBoxAdapter(
                child: _AllTracksRow(isGridView: _isGridView),
              ),

            // ── Playlists from Firestore ───────────────────────────────────────
            _PlaylistsSection(isGridView: _isGridView),
          ],

          // ── Artists from Firestore Tracks ──────────────────────────────────
          if (_activeFilter == 'All' || _activeFilter == 'Artists')
            _ArtistsSection(isGridView: _isGridView),

          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF282828),
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => CreateOptionsSheet(parentContext: context),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  "All Your Songs" row – shows live track count from Firestore
// ─────────────────────────────────────────────────────────────────────────────
class _AllTracksRow extends StatelessWidget {
  final bool isGridView;
  const _AllTracksRow({required this.isGridView});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Song>>(
      // Shared stream — no extra Firestore connection opened
      stream: FirebaseService.streamAllTracks(),
      builder: (context, snapshot) {
        final songs = snapshot.data ?? [];
        final count = songs.length;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: PlaylistCollage(
            playlist: Playlist(
              id: 'all_songs',
              name: 'All Songs',
              description: '',
              owner: '',
              imageUrl: '',
              tracks: songs,
            ),
            currentTracks: songs,
            size: 56,
          ),
          title: Text('All Songs',
              style: SpotifyFonts.bold(color: SpotifyColors.white, fontSize: 16)),
          subtitle: Row(children: [
            const Icon(Icons.push_pin, color: SpotifyColors.green, size: 13),
            const SizedBox(width: 4),
            Text('Playlist • $count songs',
                style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 13)),
          ]),
          trailing: snapshot.connectionState == ConnectionState.waiting
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: SpotifyColors.green))
              : const Icon(Icons.chevron_right, color: SpotifyColors.lightGrey),
          onTap: songs.isEmpty
              ? null
              : () => showPasswordChallenge(context, Playlist(
                    id: 'all_songs',
                    name: 'All Songs',
                    description: '${songs.length} songs',
                    owner: 'Your Library',
                    imageUrl: '',
                    tracks: songs,
                  ), isFromLibrary: true),
        );
      },
    );
  }
}

void showPasswordChallenge(BuildContext context, Playlist playlist, {bool isFromLibrary = false}) {
  final TextEditingController ctrl = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: SpotifyColors.surface,
      title: Text('Protected Library', 
          style: SpotifyFonts.title(color: Colors.white, fontSize: 18)),
      content: TextField(
        controller: ctrl,
        obscureText: true,
        style: SpotifyFonts.regular(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Enter Password',
          hintStyle: SpotifyFonts.regular(color: SpotifyColors.lightGrey),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: SpotifyColors.green)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: SpotifyFonts.bold(color: SpotifyColors.lightGrey)),
        ),
        TextButton(
          onPressed: () {
            if (ctrl.text == 'm03mj') {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlaylistDetailScreen(
                      playlist: playlist,
                      isFromLibrary: isFromLibrary,
                    ),
                  ));
            } else {
              Navigator.pop(context);
              SpotifyToast.show(context, 'Access Denied', icon: Icons.lock_outline, iconColor: Colors.redAccent);
            }
          },
          child: Text('UNLOCK', style: SpotifyFonts.bold(color: SpotifyColors.green)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Firestore playlists section
// ─────────────────────────────────────────────────────────────────────────────
class _PlaylistsSection extends StatefulWidget {
  final bool isGridView;
  const _PlaylistsSection({required this.isGridView});

  @override
  State<_PlaylistsSection> createState() => _PlaylistsSectionState();
}

class _PlaylistsSectionState extends State<_PlaylistsSection> {
  List<String>? _localPlaylistOrder;
  List<String>? _lastDatabaseOrder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Song>>(
      // Shared stream — reuses the single Firestore WebSocket connection
      stream: FirebaseService.streamAllTracks(),
      builder: (context, tracksSnapshot) {
        final songs = tracksSnapshot.data ?? [];
        final count = songs.length;
        final allSongsPlaylist = Playlist(
          id: 'all_songs',
          name: 'All Songs',
          description: '$count songs',
          owner: 'Your Library',
          imageUrl: '',
          tracks: songs,
        );

        return StreamBuilder<List<String>>(
          stream: FirebaseService.streamPlaylistOrder(),
          builder: (context, orderSnapshot) {
            final order = orderSnapshot.data ?? [];

            // Sync database order changes to local state
            if (!listEquals(order, _lastDatabaseOrder)) {
              _lastDatabaseOrder = order;
              _localPlaylistOrder = order;
            }

            return StreamBuilder<List<Playlist>>(
              stream: FirebaseService.streamPlaylists(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                final allPlaylists = snapshot.data ?? [];

                final sortedPlaylists = List<Playlist>.from(allPlaylists);
                sortedPlaylists.sort((a, b) {
                  final currentOrder = _localPlaylistOrder ?? order;
                  int iA = getPlaylistOrderIndex(a, currentOrder);
                  int iB = getPlaylistOrderIndex(b, currentOrder);
                  if (iA != iB) return iA.compareTo(iB);
                  return a.name.compareTo(b.name);
                });

                if (widget.isGridView) {
                  final combined = [allSongsPlaylist, ...sortedPlaylists];
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final pl = combined[i];
                          return _PlaylistGridCard(playlist: pl);
                        },
                        childCount: combined.length,
                      ),
                    ),
                  );
                }

                if (sortedPlaylists.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

                return SliverReorderableList(
                  itemCount: sortedPlaylists.length,
                  itemBuilder: (context, i) {
                    final pl = sortedPlaylists[i];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(pl.id),
                      index: i,
                      child: _PlaylistTile(playlist: pl),
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = sortedPlaylists.removeAt(oldIndex);
                      sortedPlaylists.insert(newIndex, item);
                      _localPlaylistOrder = sortedPlaylists.map((p) => p.id).toList();
                    });
                    FirebaseService.savePlaylistOrder(_localPlaylistOrder!);
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _PlaylistCoverCollage(playlist: playlist, size: 56),
        title: Text(playlist.name,
            style: SpotifyFonts.bold(color: SpotifyColors.white, fontSize: 15)),
        subtitle: Text('Playlist • ${playlist.trackCount} songs',
            style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 13)),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert, color: SpotifyColors.lightGrey),
          onPressed: () => showPlaylistOptions(context, playlist),
        ),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PlaylistDetailScreen(
              playlist: playlist,
            ))),
      ),
    );
  }
}

void showPlaylistOptions(BuildContext context, Playlist playlist) {
  showModalBottomSheet(
    context: context,
    backgroundColor: SpotifyColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: SpotifyColors.lightGrey, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.edit_outlined, color: SpotifyColors.white),
          title: Text('Rename Playlist', style: SpotifyFonts.bold(color: SpotifyColors.white)),
          onTap: () {
            Navigator.pop(ctx);
            _showRenameDialog(context, playlist);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
          title: Text('Delete Playlist', style: SpotifyFonts.bold(color: Colors.redAccent)),
          onTap: () async {
            Navigator.pop(ctx);
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dCtx) => AlertDialog(
                backgroundColor: SpotifyColors.surface,
                title: Text('Delete Playlist', style: SpotifyFonts.title(color: Colors.white, fontSize: 18)),
                content: Text('Are you sure you want to delete "${playlist.name}"?', style: SpotifyFonts.regular(color: SpotifyColors.lightGrey)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text('Cancel', style: SpotifyFonts.bold(color: SpotifyColors.lightGrey))),
                  TextButton(
                    onPressed: () => Navigator.pop(dCtx, true),
                    child: Text('Delete', style: SpotifyFonts.bold(color: Colors.redAccent)),
                  ),
                ],
              ),
            );

            if (confirmed == true && context.mounted) {
              await FirebaseService.deletePlaylist(playlist.id);
              if (context.mounted) {
                SpotifyToast.show(context, 'Playlist "${playlist.name}" deleted', icon: Icons.delete_outline);
              }
            }
          },
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

void _showRenameDialog(BuildContext context, Playlist playlist) {
  final TextEditingController controller = TextEditingController(text: playlist.name);
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: Text('Rename Playlist', style: SpotifyFonts.title(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: SpotifyFonts.regular(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: SpotifyFonts.regular(color: SpotifyColors.lightGrey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: SpotifyColors.lightGrey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: SpotifyColors.green),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: SpotifyFonts.bold(color: SpotifyColors.lightGrey)),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != playlist.name) {
                await FirebaseService.renamePlaylist(playlist.id, newName);
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (newName.isNotEmpty && newName != playlist.name && context.mounted) {
                  SpotifyToast.show(context, 'Playlist renamed to "$newName"', icon: Icons.edit_note);
                }
              }
            },
            child: Text('Save', style: SpotifyFonts.bold(color: SpotifyColors.green)),
          ),
        ],
      );
    },
  );
}

class _PlaylistGridCard extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistGridCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (playlist.id == 'all_songs') {
          showPasswordChallenge(context, playlist, isFromLibrary: true);
        } else {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist)));
        }
      },
      onLongPress: () {
        if (playlist.id != 'all_songs') showPlaylistOptions(context, playlist);
      },
      child: Container(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: _PlaylistCoverCollage(playlist: playlist, size: double.infinity),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpotifyFonts.bold(color: SpotifyColors.white, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              'Playlist • ${playlist.trackCount} songs',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCoverCollage extends StatelessWidget {
  final Playlist playlist;
  final double size;
  
  const _PlaylistCoverCollage({required this.playlist, required this.size});

  @override
  Widget build(BuildContext context) {
    return PlaylistCollage(
      playlist: playlist,
      currentTracks: playlist.tracks,
      size: size,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Artists Section
// ─────────────────────────────────────────────────────────────────────────────
class _ArtistsSection extends StatelessWidget {
  final bool isGridView;
  const _ArtistsSection({required this.isGridView});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Song>>(
      // Shared stream — reuses the single Firestore connection
      stream: FirebaseService.streamAllTracks(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final allSongs = snapshot.data!;

        
        final Map<String, Song> uniqueArtists = {};
        final Map<String, int> artistSongCounts = {};
        
        for (final song in allSongs.reversed) {
          final artistName = song.artist.trim();
          if (artistName.isEmpty) continue;
          
          artistSongCounts[artistName] = (artistSongCounts[artistName] ?? 0) + 1;
          
          if (!uniqueArtists.containsKey(artistName)) {
            uniqueArtists[artistName] = song;
          } else {
            if (uniqueArtists[artistName]!.imageUrl.isEmpty && song.imageUrl.isNotEmpty) {
              uniqueArtists[artistName] = song;
            }
          }
        }
        
        var artistsList = uniqueArtists.values
            .where((s) => s.imageUrl.isNotEmpty)
            .toList();
            
        artistsList.sort((a, b) => artistSongCounts[b.artist]!.compareTo(artistSongCounts[a.artist]!));
        
        if (artistsList.length > 30) {
          artistsList = artistsList.take(30).toList();
        }

        if (artistsList.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

        if (isGridView) {
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  return _ArtistGridCard(song: artistsList[i]);
                },
                childCount: artistsList.length,
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              return _ArtistTile(song: artistsList[i]);
            },
            childCount: artistsList.length,
          ),
        );
      },
    );
  }
}

class _ArtistTile extends StatelessWidget {
  final Song song;
  const _ArtistTile({required this.song});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: const Color(0xFF282828),
          backgroundImage: song.imageUrl.isNotEmpty
              ? CachedNetworkImageProvider(song.imageUrl)
              : null,

          child: song.imageUrl.isEmpty
              ? const Icon(Icons.person_outline, color: SpotifyColors.lightGrey, size: 28)
              : null,
        ),
        title: Text(song.artist,
            style: SpotifyFonts.bold(color: SpotifyColors.white, fontSize: 15)),
        subtitle: Text('Artist',
            style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 13)),
        onTap: () {},
      ),
    );
  }
}

class _ArtistGridCard extends StatelessWidget {
  final Song song;
  const _ArtistGridCard({required this.song});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF282828),
                      image: song.imageUrl.isNotEmpty
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(song.imageUrl),
                              fit: BoxFit.cover)
                          : null,

                    ),
                    child: song.imageUrl.isEmpty
                        ? const Icon(Icons.person_outline, color: SpotifyColors.lightGrey, size: 48)
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpotifyFonts.bold(color: SpotifyColors.white, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              'Artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────────────────────
//  AllTracksPlaylistScreen
//  ← Full-screen view of EVERY track in `tracks` collection
//     Uses StreamBuilder so it live-updates when songs are added via Python
// ─────────────────────────────────────────────────────────────────────────────
class AllTracksPlaylistScreen extends StatefulWidget {
  final List<Song> songs;          // initial snapshot (may be empty)
  final String     playlistName;

  const AllTracksPlaylistScreen({
    super.key,
    required this.songs,
    this.playlistName = 'All Songs',
  });

  @override
  State<AllTracksPlaylistScreen> createState() => _AllTracksPlaylistScreenState();
}

class _AllTracksPlaylistScreenState extends State<AllTracksPlaylistScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.black,
      body: StreamBuilder<List<Song>>(
        // Shared stream — reuses the single Firestore WebSocket connection
        stream: FirebaseService.streamAllTracks(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print('[AllTracksPlaylistScreen] Firestore Error: ${snapshot.error}');
          }

          // Show stale data while loading or error
          final List<Song> allSongs =
              snapshot.hasData ? snapshot.data! : widget.songs;

          // Apply search filter and sort by match relevance (prefix first)
          final List<Song> filtered;
          if (_query.isEmpty) {
            filtered = allSongs;
          } else {
            final q = _query.toLowerCase();
            filtered = allSongs.where((s) =>
                s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q)).toList();
            
            filtered.sort((a, b) {
              final aTitleLower = a.title.toLowerCase();
              final bTitleLower = b.title.toLowerCase();
              final aArtistLower = a.artist.toLowerCase();
              final bArtistLower = b.artist.toLowerCase();

              int getRank(String title, String artist) {
                if (title.startsWith(q)) return 0;
                if (artist.startsWith(q)) return 1;
                
                final titleWords = title.split(' ');
                for (final word in titleWords) {
                  if (word.startsWith(q)) return 2;
                }
                
                final artistWords = artist.split(' ');
                for (final word in artistWords) {
                  if (word.startsWith(q)) return 3;
                }
                
                if (title.contains(q)) return 4;
                if (artist.contains(q)) return 5;
                return 6;
              }

              final rankA = getRank(aTitleLower, aArtistLower);
              final rankB = getRank(bTitleLower, bArtistLower);

              if (rankA != rankB) {
                return rankA.compareTo(rankB);
              }
              
              // Tie-breaker: sort alphabetically by title
              return aTitleLower.compareTo(bTitleLower);
            });
          }

          return CustomScrollView(
            slivers: [
              // ── Header ──────────────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: const Color(0xFF1DB954).withValues(alpha: 0.9),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1DB954), Color(0xFF148A08), SpotifyColors.black],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 24),
                          Container(
                            width: 160, height: 160,
                            decoration: BoxDecoration(
                              color: const Color(0xFF148A08),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 30, offset: const Offset(0, 12),
                              )],
                            ),
                            child: const Icon(Icons.library_music,
                                color: Colors.white, size: 72),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Playlist info + controls ──────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.playlistName,
                          style: SpotifyFonts.display(color: Colors.white, fontSize: 24)),
                      const SizedBox(height: 4),
                      Row(children: [
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: SpotifyColors.green)),
                        const SizedBox(width: 8),
                        Text('${allSongs.length} songs',
                            style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 13)),
                        if (snapshot.hasData) ...[
                          Text(' • ', style: SpotifyFonts.regular(color: SpotifyColors.lightGrey)),
                          const Icon(Icons.fiber_manual_record,
                              color: SpotifyColors.green, size: 8),
                          const SizedBox(width: 4),
                          Text('Live',
                              style: SpotifyFonts.bold(color: SpotifyColors.green, fontSize: 12)),
                        ],
                      ]),
                      const SizedBox(height: 16),
                      // Controls row
                      Row(children: [
                        const Icon(Icons.favorite_border,
                            color: SpotifyColors.lightGrey, size: 28),
                        const SizedBox(width: 20),
                        const Icon(Icons.arrow_circle_down_outlined,
                            color: SpotifyColors.lightGrey, size: 28),
                        const SizedBox(width: 20),
                        const Icon(Icons.more_horiz,
                            color: SpotifyColors.lightGrey, size: 28),
                        const Spacer(),
                        // Shuffle play
                        Consumer<PlayerProvider>(
                          builder: (ctx, player, _) => GestureDetector(
                            onTap: () {
                              if (allSongs.isEmpty) return;
                              final shuffled = List<Song>.from(allSongs)..shuffle();
                              player.toggleShuffle();
                              player.playSong(shuffled.first, playlist: shuffled);
                              _openPlayer(ctx, shuffled.first, player);
                            },
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: SpotifyColors.green.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.shuffle, color: SpotifyColors.green, size: 22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Play button
                        Consumer<PlayerProvider>(
                          builder: (ctx, player, _) => GestureDetector(
                            onTap: () {
                              if (allSongs.isEmpty) return;
                              player.playSong(allSongs.first, playlist: allSongs);
                              _openPlayer(ctx, allSongs.first, player);
                            },
                            child: Container(
                              width: 56, height: 56,
                              decoration: const BoxDecoration(
                                color: SpotifyColors.green, shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow,
                                  color: SpotifyColors.black, size: 30),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

              // ── Search within playlist ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: SpotifyColors.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.search, color: SpotifyColors.lightGrey, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: SpotifyFonts.regular(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Find in playlist',
                            hintStyle: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 14),
                            border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, color: SpotifyColors.lightGrey, size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36),
                        ),
                    ]),
                  ),
                ),
              ),

              // ── Track list ────────────────────────────────────────────────
              filtered.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              snapshot.connectionState == ConnectionState.waiting
                                  ? Icons.hourglass_empty
                                  : Icons.search_off,
                              color: SpotifyColors.lightGrey, size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              snapshot.connectionState == ConnectionState.waiting
                                  ? 'Loading songs…'
                                  : _query.isNotEmpty
                                      ? 'No results for "$_query"'
                                      : 'No songs in database yet.\nUpload songs using your Python script.',
                              textAlign: TextAlign.center,
                              style: SpotifyFonts.regular(
                                  color: SpotifyColors.lightGrey, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final song = filtered[i];
                          return TrackListTile(
                            song: song,
                            allSongs: filtered,
                            canDelete: true,
                            playlistName: widget.playlistName,
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),

              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          );
        },
      ),
    );
  }

  void _openPlayer(BuildContext context, Song song, PlayerProvider player) {
    openNowPlaying(context, song);
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  Create playlist / blend sheet matching spotify_navigation.dart style
// ─────────────────────────────────────────────────────────────────────────────
class CreateOptionsSheet extends StatelessWidget {
  final BuildContext parentContext;
  const CreateOptionsSheet({super.key, 
    required this.parentContext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Regular playlist ────────────────────────────────────────────
          InkWell(
            onTap: () {
              Navigator.pop(context);
              _showCreatePlaylistDialog(parentContext);
            },
            splashColor: Colors.white10,
            highlightColor: Colors.white10,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3E3E3E),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.music_note,
                      color: SpotifyColors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Playlist',
                        style: SpotifyFonts.bold(
                          color: SpotifyColors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Build a playlist with songs',
                        style: SpotifyFonts.regular(
                          color: SpotifyColors.lightGrey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFF3E3E3E),
            indent: 72,
            endIndent: 16,
          ),
          // ── Blend ───────────────────────────────────────────────────────
          InkWell(
            onTap: () => Navigator.pop(context),
            splashColor: Colors.white10,
            highlightColor: Colors.white10,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3E3E3E),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.people_outline,
                      color: SpotifyColors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Blend',
                        style: SpotifyFonts.bold(
                          color: SpotifyColors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Build a playlist with a friend',
                        style: SpotifyFonts.regular(
                          color: SpotifyColors.lightGrey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFF3E3E3E),
            indent: 72,
            endIndent: 16,
          ),
          // ── Smart Ingestion ─────────────────────────────────────────────
          InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                parentContext,
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const IngestionPage(),
                ),
              );
            },
            splashColor: Colors.white10,
            highlightColor: Colors.white10,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3E3E3E),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bolt,
                      color: SpotifyColors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Smart Ingestion',
                        style: SpotifyFonts.bold(
                          color: SpotifyColors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Import via CSV or YouTube search',
                        style: SpotifyFonts.regular(
                          color: SpotifyColors.lightGrey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final ctrl = TextEditingController();
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: Text('Name your playlist', style: SpotifyFonts.title(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: SpotifyFonts.regular(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'My Playlist #1',
            hintStyle: SpotifyFonts.regular(color: SpotifyColors.lightGrey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: SpotifyFonts.bold(color: SpotifyColors.lightGrey)),
          ),
          StatefulBuilder(
            builder: (ctx, setDialogState) {
              return ElevatedButton(
                onPressed: isCreating ? null : () async {
                  if (ctrl.text.trim().isNotEmpty) {
                    final name = ctrl.text.trim();
                    setDialogState(() => isCreating = true);
                    
                    try {
                      final playlistId = await FirebaseService.createPlaylist(name: name);
                      
                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx); // Success: Close dialog
                      }

                      if (playlistId != null && context.mounted) {
                        final newPlaylist = await FirebaseService.fetchPlaylist(playlistId);
                        if (newPlaylist != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlaylistDetailScreen(playlist: newPlaylist),
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (dialogCtx.mounted) {
                        setDialogState(() => isCreating = false);
                      }
                      if (context.mounted) {
                        SpotifyToast.show(
                          context,
                          'Error: ${e.toString().split(']').last}',
                          icon: Icons.error_outline,
                          iconColor: Colors.redAccent,
                        );
                      }
                    }
                  }
                },
                child: isCreating 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Create'),
              );
            },
          ),
        ],
      ),
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
