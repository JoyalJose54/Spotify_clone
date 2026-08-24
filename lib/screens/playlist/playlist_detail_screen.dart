import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/firebase_service.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mini_player.dart';
import '../player/now_playing_screen.dart';
import 'playlist_actions.dart';

import '../../widgets/playlist_collage.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;
  final bool isFromLibrary;
  const PlaylistDetailScreen({super.key, required this.playlist, this.isFromLibrary = false});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final ScrollController _sc = ScrollController();
  final ValueNotifier<double> _scrollNotifier = ValueNotifier(0.0);
  Color _dominantColor = const Color(0xFF121212);
  String? _lastCoverUrl;
  PlaylistSortOrder _sortOrder = PlaylistSortOrder.custom;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSelectionMode = false;
  final Set<String> _selectedSongIds = {};

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.hasClients) _scrollNotifier.value = _sc.offset;
    });
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
    // Warm up the palette for the initial playlist cover (if available)
    final initialTracks = widget.playlist.tracks;
    if (initialTracks.isNotEmpty && initialTracks.first.imageUrl.isNotEmpty) {
      _scheduleColorUpdate(initialTracks.first.imageUrl);
    }
  }

  // Schedules a palette extraction safely outside the build phase.
  // Only runs when the cover URL has actually changed to avoid redundant work.
  void _scheduleColorUpdate(String url) {
    if (url.isEmpty || url == _lastCoverUrl) return;
    _lastCoverUrl = url;
    if (PaletteCache.contains(url)) {
      // Already cached — apply synchronously (safe here: called from lifecycle,
      // not from build).
      _dominantColor = PaletteCache.get(url)!.dominant;
    } else {
      // Heavy extraction — defer to after the current frame finishes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updatePalette(url);
      });
    }
  }


  Future<void> _updatePalette(String url) async {
    if (url.isEmpty) return;
    if (PaletteCache.contains(url)) {
      final cached = PaletteCache.get(url)!;
      if (mounted) {
        setState(() {
          _dominantColor = cached.dominant;
        });
      }
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(NetworkImage(url), width: 100),
      );
      if (palette.dominantColor != null && mounted) {
        final dominant = palette.dominantColor!.color;
        final vibrant = palette.vibrantColor?.color ?? dominant;
        final muted = palette.mutedColor?.color ?? palette.darkMutedColor?.color ?? const Color(0xFF1A4A52);
        
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
          _dominantColor = dominant;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    _scrollNotifier.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }


  void _showMultiCopyMoveSheet(BuildContext context, {required bool isMove}) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF282828),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              Container(
                width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  isMove ? 'Move selected songs' : 'Copy selected songs',
                  style: SpotifyFonts.regular(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Playlist>>(
                  stream: FirebaseService.streamPlaylists(),
                  builder: (sCtx, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: SpotifyColors.green));
                    }
                    final pls = snapshot.data!.where((p) => p.id != 'all_songs' && (!isMove || p.id != widget.playlist.id)).toList();
                    return ListView(
                      controller: scrollCtrl,
                      children: [
                        ListTile(
                          leading: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.add, color: SpotifyColors.green, size: 24),
                          ),
                          title: Text('Create playlist', style: SpotifyFonts.regular(color: Colors.white, fontWeight: FontWeight.bold)),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await Future.delayed(const Duration(milliseconds: 300));
                            if (context.mounted) {
                              _showCreatePlaylistDialogForMultiSelection(context, isMove: isMove);
                            }
                          },
                        ),
                        ...pls.map((pl) => ListTile(
                          leading: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(color: SpotifyColors.surface, borderRadius: BorderRadius.circular(4)),
                            child: pl.imageUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: CachedNetworkImage(
                                      imageUrl: pl.imageUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 150, memCacheHeight: 150,
                                      errorWidget: (_, __, ___) => const Icon(Icons.queue_music, color: SpotifyColors.lightGrey),
                                    ),
                                  )
                                : const Icon(Icons.queue_music, color: SpotifyColors.lightGrey),
                          ),
                          title: Text(pl.name, style: SpotifyFonts.regular(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text('${pl.trackCount} songs', style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 12)),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await Future.delayed(const Duration(milliseconds: 300));
                            if (context.mounted) {
                              _executeMultiCopyMove(context, destinationPlaylist: pl, isMove: isMove);
                            }
                          },
                        )),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _executeMultiCopyMove(BuildContext context, {required Playlist destinationPlaylist, required bool isMove}) async {
    int addedCount = 0;
    int skippedCount = 0;
    final List<String> currentTrackIds = destinationPlaylist.trackIds;
    final List<String> toAddIds = [];

    for (final songId in _selectedSongIds) {
      if (currentTrackIds.contains(songId)) {
        skippedCount++;
      } else {
        toAddIds.add(songId);
        addedCount++;
      }
    }

    print('[PlaylistDetailScreen] Copy/Move diagnostic:\n'
          '  Source Playlist: ${widget.playlist.name} (${widget.playlist.id})\n'
          '  Destination Playlist: ${destinationPlaylist.name} (${destinationPlaylist.id})\n'
          '  Selected IDs: $_selectedSongIds\n'
          '  Destination Existing IDs: $currentTrackIds\n'
          '  To Add IDs: $toAddIds\n'
          '  Is Move: $isMove');

    if (toAddIds.isEmpty) {
      // No DB work needed, just update UI and notify directly (avoids race condition with showDialog)
      setState(() {
        _isSelectionMode = false;
        _selectedSongIds.clear();
      });
      if (context.mounted) {
        String msg;
        if (skippedCount > 0) {
          msg = 'Skipped: Song(s) already exist in ${destinationPlaylist.name}';
          SpotifyToast.show(context, msg, icon: Icons.warning_amber_rounded, iconColor: Colors.amber);
        } else {
          msg = 'No songs selected';
          SpotifyToast.show(context, msg, icon: Icons.info_outline);
        }
      }
      return;
    }

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingCtx) {
        dialogContext = loadingCtx;
        return const Center(
          child: CircularProgressIndicator(color: SpotifyColors.green),
        );
      },
    );

    try {
      await FirebaseService.addTracksToPlaylist(destinationPlaylist.id, toAddIds);

      if (isMove) {
        // Only remove the tracks that were successfully added to the destination playlist (do not remove skipped duplicates)
        await FirebaseService.removeTracksFromPlaylist(widget.playlist.id, toAddIds);
      }

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }

      setState(() {
        _isSelectionMode = false;
        _selectedSongIds.clear();
      });

      if (context.mounted) {
        String msg = isMove
            ? 'Successfully moved $addedCount song(s) to ${destinationPlaylist.name}'
            : 'Successfully copied $addedCount song(s) to ${destinationPlaylist.name}';
        if (skippedCount > 0) {
          msg += ' ($skippedCount duplicate(s) skipped)';
        }
        SpotifyToast.show(context, msg, icon: isMove ? Icons.swap_horiz : Icons.copy_all);
      }
    } catch (e) {
      print('[PlaylistDetailScreen] executeMultiCopyMove error: $e');
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
      setState(() {
        _isSelectionMode = false;
        _selectedSongIds.clear();
      });
      if (context.mounted) {
        final actionStr = isMove ? 'move' : 'copy';
        SpotifyToast.show(context, 'Failed to $actionStr: $e', icon: Icons.error_outline, iconColor: Colors.redAccent);
      }
    }
  }

  void _showCreatePlaylistDialogForMultiSelection(BuildContext context, {required bool isMove}) {
    FocusManager.instance.primaryFocus?.unfocus();
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
                      await FirebaseService.createPlaylist(
                        name: name,
                        trackIds: _selectedSongIds.toList(),
                      );
                      
                      if (isMove) {
                        await FirebaseService.removeTracksFromPlaylist(widget.playlist.id, _selectedSongIds.toList());
                      }

                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                      }

                      setState(() {
                        _isSelectionMode = false;
                        _selectedSongIds.clear();
                      });

                      if (context.mounted) {
                        final actionStr = isMove ? 'Moved' : 'Copied';
                        SpotifyToast.show(
                          context,
                          '$actionStr songs to new playlist "$name"',
                          icon: isMove ? Icons.swap_horiz : Icons.copy_all,
                        );
                      }
                    } catch (e) {
                      if (dialogCtx.mounted) {
                        setDialogState(() => isCreating = false);
                        SpotifyToast.show(dialogCtx, 'Error: $e', icon: Icons.error_outline, iconColor: Colors.redAccent);
                      }
                    }
                  }
                },
                child: isCreating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text('Create', style: SpotifyFonts.bold(color: Colors.black)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget? _buildSelectionActionBar() {
    if (!_isSelectionMode) return null;
    final isAllSongs = widget.playlist.id == 'all_songs';
    return Container(
      margin: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionButton(
            icon: Icons.close,
            label: 'Cancel',
            onTap: () {
              setState(() {
                _isSelectionMode = false;
                _selectedSongIds.clear();
              });
            },
          ),
          _actionButton(
            icon: Icons.copy_all,
            label: 'Copy',
            enabled: _selectedSongIds.isNotEmpty,
            onTap: () => _showMultiCopyMoveSheet(context, isMove: false),
          ),
          if (!isAllSongs) ...[
            _actionButton(
              icon: Icons.swap_horiz,
              label: 'Move',
              enabled: _selectedSongIds.isNotEmpty,
              onTap: () => _showMultiCopyMoveSheet(context, isMove: true),
            ),
            _actionButton(
              icon: Icons.delete_outline,
              label: 'Remove',
              color: Colors.redAccent,
              enabled: _selectedSongIds.isNotEmpty,
              onTap: () => _executeMultiDelete(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
    bool enabled = true,
  }) {
    final finalColor = enabled ? color : Colors.white24;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: finalColor, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: SpotifyFonts.regular(color: finalColor, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _executeMultiDelete(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: Text('Remove from playlist', style: SpotifyFonts.title(color: Colors.white, fontSize: 18)),
        content: Text(
          'Are you sure you want to remove the ${_selectedSongIds.length} selected songs from this playlist?',
          style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: SpotifyFonts.bold(color: SpotifyColors.lightGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Remove', style: SpotifyFonts.bold(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingCtx) {
        dialogContext = loadingCtx;
        return const Center(
          child: CircularProgressIndicator(color: SpotifyColors.green),
        );
      },
    );

    try {
      final List<String> toRemoveIds = _selectedSongIds.toList();
      await FirebaseService.removeTracksFromPlaylist(widget.playlist.id, toRemoveIds);

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }

      setState(() {
        _isSelectionMode = false;
        _selectedSongIds.clear();
      });

      if (context.mounted) {
        SpotifyToast.show(
          context,
          'Successfully removed ${toRemoveIds.length} song(s) from playlist',
          icon: Icons.delete_outline,
        );
      }
    } catch (e) {
      print('[PlaylistDetailScreen] executeMultiDelete error: $e');
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
      setState(() {
        _isSelectionMode = false;
        _selectedSongIds.clear();
      });
      if (context.mounted) {
        SpotifyToast.show(context, 'Failed to remove: $e', icon: Icons.error_outline, iconColor: Colors.redAccent);
      }
    }
  }

  void _checkDuplicates(BuildContext context, List<Song> songs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => _DuplicateResolverSheet(scrollController: scrollCtrl),
      ),
    );
  }

  String _totalDuration(List<Song> songs) {
    final ms = songs.fold<int>(0, (s, t) => s + t.durationMs);
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;

    if (h > 0) {
      return '$h hr $m min';
    } else if (m > 0) {
      return '$m min $s sec';
    } else {
      return '$s sec';
    }
  }

  List<Song> _getDisplaySongs(List<Song> songs) {
    // 1. Search Filter & Relevance Sort
    var filtered = songs;
    if (_searchQuery.isNotEmpty) {
      filtered = songs.where((s) => 
        s.title.toLowerCase().contains(_searchQuery) || 
        s.artist.toLowerCase().contains(_searchQuery)
      ).toList();

      filtered.sort((a, b) {
        final aTitleLower = a.title.toLowerCase();
        final bTitleLower = b.title.toLowerCase();
        final aArtistLower = a.artist.toLowerCase();
        final bArtistLower = b.artist.toLowerCase();

        int getRank(String title, String artist) {
          if (title.startsWith(_searchQuery)) return 0;
          if (artist.startsWith(_searchQuery)) return 1;
          
          final titleWords = title.split(' ');
          for (final word in titleWords) {
            if (word.startsWith(_searchQuery)) return 2;
          }
          
          final artistWords = artist.split(' ');
          for (final word in artistWords) {
            if (word.startsWith(_searchQuery)) return 3;
          }
          
          if (title.contains(_searchQuery)) return 4;
          if (artist.contains(_searchQuery)) return 5;
          return 6;
        }

        final rankA = getRank(aTitleLower, aArtistLower);
        final rankB = getRank(bTitleLower, bArtistLower);

        if (rankA != rankB) {
          return rankA.compareTo(rankB);
        }
        
        // Secondary sort order when rank is same
        switch (_sortOrder) {
          case PlaylistSortOrder.title:
            return aTitleLower.compareTo(bTitleLower);
          case PlaylistSortOrder.artist:
            return aArtistLower.compareTo(bArtistLower);
          case PlaylistSortOrder.album:
            return a.album.toLowerCase().compareTo(b.album.toLowerCase());
          case PlaylistSortOrder.recentlyAdded:
            final timeA = a.createdAt;
            final timeB = b.createdAt;
            if (timeA != null && timeB != null) return timeB.compareTo(timeA);
            if (timeA != null) return -1;
            if (timeB != null) return 1;
            return b.id.compareTo(a.id);
          case PlaylistSortOrder.custom:
            return aTitleLower.compareTo(bTitleLower);
        }
      });
      return filtered;
    }

    // 2. Regular Sort (when not searching)
    final sorted = List<Song>.from(filtered);
    switch (_sortOrder) {
      case PlaylistSortOrder.title:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case PlaylistSortOrder.artist:
        sorted.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case PlaylistSortOrder.album:
        sorted.sort((a, b) => a.album.toLowerCase().compareTo(b.album.toLowerCase()));
        break;
      case PlaylistSortOrder.recentlyAdded:
        sorted.sort((a, b) {
          final timeA = a.createdAt;
          final timeB = b.createdAt;
          if (timeA != null && timeB != null) {
            return timeB.compareTo(timeA); // Newest first
          }
          if (timeA != null) return -1;
          if (timeB != null) return 1;
          return b.id.compareTo(a.id);
        });
        break;
      case PlaylistSortOrder.custom:
        break;
    }
    return sorted;
  }

  // Cover shrinks from 260 → 100 as you scroll 0 → 300
  double _getCoverSize(double offset) => (260 - (offset * 0.53).clamp(0, 160));
  // App bar bg opacity
  double _getAppBarAlpha(double offset) => (offset / 300).clamp(0.0, 1.0);
  // Title in app bar appears after scroll > 280
  double _getTitleAlpha(double offset) => ((offset - 280) / 60).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedSongIds.clear();
          });
        }
      },
      child: Scaffold(
      backgroundColor: SpotifyColors.black,
      bottomNavigationBar: _buildSelectionActionBar(),
      body: StreamBuilder<List<Song>>(
        stream: widget.playlist.id == 'all_songs'
            ? FirebaseService.streamAllSongs()
            : FirebaseService.streamPlaylistSongs(widget.playlist.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
             print('[PlaylistDetailScreen] Error: ${snapshot.error}');
          }
          final songs = _getDisplaySongs(snapshot.data ?? widget.playlist.tracks);
          final rawSongs = snapshot.data ?? widget.playlist.tracks;

          // Schedule palette update outside build — safe, won't dirty the tree
          if (rawSongs.isNotEmpty && rawSongs.first.imageUrl.isNotEmpty) {
            // _scheduleColorUpdate is a no-op when URL hasn't changed
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scheduleColorUpdate(rawSongs.first.imageUrl);
            });
          }

          return Stack(
            children: [
              // ── Gradient background that scrolls up ──
              ValueListenableBuilder<double>(
                valueListenable: _scrollNotifier,
                builder: (context, offset, child) {
                  return Positioned(
                    top: -offset, // Scrolls up with the list
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 420,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_dominantColor, _dominantColor.withValues(alpha: 0.5), SpotifyColors.black],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  );
                },
              ),

              // ── Scrollable content ──
              CustomScrollView(
                controller: _sc,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  // Top spacing for status bar + back button
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          const SizedBox(height: 50),
                          // Search bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A).withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: TextField(
                                controller: _searchCtrl,
                                focusNode: _searchFocusNode,
                                style: SpotifyFonts.regular(color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  prefixIcon: const Icon(Icons.search, color: SpotifyColors.lightGrey, size: 20),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? GestureDetector(
                                          onTap: () {
                                            _searchCtrl.clear();
                                            _searchFocusNode.unfocus();
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8),
                                            child: Icon(Icons.close, color: SpotifyColors.lightGrey, size: 20),
                                          ),
                                        )
                                      : null,
                                  hintText: 'Find in playlist',
                                  hintStyle: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 14),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Cover art (shrinks on scroll)
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: ValueListenableBuilder<double>(
                                valueListenable: _scrollNotifier,
                                builder: (context, offset, child) {
                                  return SizedBox(
                                    width: _getCoverSize(offset),
                                    height: _getCoverSize(offset),
                                    child: PlaylistCollage(
                                      playlist: widget.playlist,
                                      currentTracks: songs,
                                      size: _getCoverSize(offset),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Playlist name
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                widget.playlist.name,
                                style: SpotifyFonts.bold( 
                                  color: Colors.white, fontSize: 24,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // + Avatar Name
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(Icons.add, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Container(
                                  width: 24, height: 24,
                                  decoration: const BoxDecoration(
                                    color: SpotifyColors.green, shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      (widget.playlist.owner.isEmpty ? 'Y' : widget.playlist.owner[0]).toUpperCase(),
                                      style: SpotifyFonts.regular( 
                                        color: Colors.black, fontSize: 13, fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.playlist.owner.isEmpty ? 'You' : widget.playlist.owner,
                                  style: SpotifyFonts.regular( 
                                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Lock + duration
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline, color: SpotifyColors.lightGrey, size: 15),
                                const SizedBox(width: 5),
                                Text('${songs.length} songs • ${_totalDuration(songs)}',
                                    style: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 13)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Action row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                // Small thumb
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: songs.isNotEmpty && songs.first.imageUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: songs.first.imageUrl,
                                          width: 36, height: 36, fit: BoxFit.cover,
                                          memCacheWidth: 100, memCacheHeight: 100,
                                          errorWidget: (_, __, ___) => _miniThumb())
                                      : _miniThumb(),

                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.arrow_circle_down_outlined, color: SpotifyColors.lightGrey, size: 26),
                                const SizedBox(width: 12),
                                const Icon(Icons.share_outlined, color: SpotifyColors.lightGrey, size: 22),
                                if (widget.playlist.id == 'all_songs' && widget.isFromLibrary) ...[
                                  const SizedBox(width: 12),
                                  TextButton.icon(
                                    onPressed: () => _checkDuplicates(context, songs),
                                    icon: const Icon(Icons.cleaning_services_rounded, color: SpotifyColors.green, size: 18),
                                    label: Text('Check Duplicates', 
                                      style: SpotifyFonts.bold(color: SpotifyColors.green, fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      backgroundColor: Colors.white10,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                Consumer<PlayerProvider>(
                                  builder: (_, p, __) => GestureDetector(
                                    onTap: () => p.toggleShuffle(),
                                    child: Icon(Icons.shuffle,
                                        color: p.isShuffled ? SpotifyColors.green : SpotifyColors.lightGrey, size: 28),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Consumer<PlayerProvider>(
                                  builder: (_, p, __) => GestureDetector(
                                    onTap: () {
                                      if (songs.isNotEmpty) {
                                        p.playSong(songs.first, playlist: songs, playlistName: widget.playlist.name);
                                        _openPlayer(context, songs.first);
                                      }
                                    },
                                    child: Container(
                                      width: 52, height: 52,
                                      decoration: const BoxDecoration(
                                        color: SpotifyColors.green, shape: BoxShape.circle),
                                      child: const Icon(Icons.play_arrow, color: Colors.black, size: 30),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          if (widget.playlist.id != 'all_songs') ...[
                            const SizedBox(height: 12),
                            // Pill buttons
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _pill(Icons.add, 'Add', onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AddSongsScreen(
                                            playlistId: widget.playlist.id,
                                            existingTrackIds: rawSongs.map((s) => s.id).toList(),
                                          ),
                                        ),
                                      );
                                    }),
                                    const SizedBox(width: 8),
                                    _pill(Icons.edit_outlined, 'Edit', onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EditPlaylistScreen(
                                            playlistId: widget.playlist.id,
                                            songs: rawSongs,
                                          ),
                                        ),
                                      );
                                    }),
                                    const SizedBox(width: 8),
                                    _pill(Icons.import_export, 'Sort', onTap: () {
                                      showSortSheet(context, _sortOrder, (order) {
                                        setState(() => _sortOrder = order);
                                      });
                                    }),
                                    const SizedBox(width: 8),
                                    _pill(Icons.info_outline, 'Name and details', onTap: () {
                                      showNameDetailsSheet(context, widget.playlist, rawSongs);
                                    }),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── Track list ──
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _TrackTile(
                        song: songs[i], playlistSongs: songs,
                        playlistId: widget.playlist.id,
                        playlistName: widget.playlist.name,
                        canDelete: widget.playlist.id == 'all_songs' && widget.isFromLibrary,
                        isSelectionMode: _isSelectionMode,
                        isSelected: _selectedSongIds.contains(songs[i].id),
                        onSelectedChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedSongIds.add(songs[i].id);
                            } else {
                              _selectedSongIds.remove(songs[i].id);
                            }
                          });
                        },
                        onLongPress: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() {
                            _isSelectionMode = true;
                            _selectedSongIds.add(songs[i].id);
                          });
                        },
                      ),
                      childCount: songs.length,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),

              // ── Floating app bar ──
              ValueListenableBuilder<double>(
                valueListenable: _scrollNotifier,
                builder: (context, offset, child) {
                  return Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _dominantColor.withValues(alpha: _getAppBarAlpha(offset)),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: 50,
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                                onPressed: () {
                                  if (_isSelectionMode) {
                                    setState(() {
                                      _isSelectionMode = false;
                                      _selectedSongIds.clear();
                                    });
                                  } else {
                                    Navigator.pop(context);
                                  }
                                },
                              ),
                              const Spacer(),
                              Opacity(
                                opacity: _getTitleAlpha(offset),
                                child: Text(widget.playlist.name,
                                    style: SpotifyFonts.regular( 
                                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                              ),
                              const Spacer(),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // ── Mini Player Overlay ──
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: SafeArea(
                  child: Consumer<PlayerProvider>(
                    builder: (context, player, _) {
                      if (!player.hasCurrentSong) return const SizedBox.shrink();
                      return MiniPlayer(player: player);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}




  Widget _miniThumb() => Container(width: 36, height: 36, color: SpotifyColors.surface,
      child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 16));

  Widget _pill(IconData icon, String label, {required VoidCallback onTap}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 15),
        const SizedBox(width: 6),
        Text(label, style: SpotifyFonts.regular( color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  void _openPlayer(BuildContext ctx, Song song) {
    openNowPlaying(ctx, song);
  }
}

// ─── Track Tile (matches Spotify exact spacing ~70px per row) ────────────────
class _TrackTile extends StatelessWidget {
  final Song song;
  final List<Song> playlistSongs;
  final String playlistId;
  final String playlistName;
  final bool canDelete;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectedChanged;
  final VoidCallback? onLongPress;

  const _TrackTile({
    required this.song,
    required this.playlistSongs,
    required this.playlistId,
    required this.playlistName,
    this.canDelete = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectedChanged,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final isCurrent = player.currentSong?.id == song.id;
        return InkWell(
          onTap: isSelectionMode
              ? () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  onSelectedChanged?.call(!isSelected);
                }
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  player.playSong(song, playlist: playlistSongs, playlistName: playlistName);
                  FirebaseService.addRecentlyPlayed(song.id);
                  openNowPlaying(context, song);
                },
          onLongPress: isSelectionMode ? null : onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (isSelectionMode) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: onSelectedChanged,
                    activeColor: SpotifyColors.green,
                    checkColor: Colors.black,
                  ),
                  const SizedBox(width: 8),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: song.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: song.imageUrl,
                          width: 50, height: 50, fit: BoxFit.cover,
                          memCacheWidth: 150, memCacheHeight: 150,
                          errorWidget: (_, __, ___) => _ph())
                      : _ph(),

                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(song.title,
                          style: SpotifyFonts.bold( 
                            color: isCurrent ? SpotifyColors.green : Colors.white,
                            fontSize: 15),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(children: [
                        if (song.isExplicit) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: SpotifyColors.lightGrey, borderRadius: BorderRadius.circular(2)),
                            child: Text('E',
                                style: SpotifyFonts.bold(color: Colors.black, fontSize: 9)),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(song.artist,
                              style: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ],
                  ),
                ),
                if (!isSelectionMode && (playlistId != 'all_songs' || canDelete))
                  GestureDetector(
                    onTap: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      _showTrackOptions(context);
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.more_vert, color: SpotifyColors.lightGrey, size: 20),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ph() => Container(width: 50, height: 50, color: SpotifyColors.surface,
      child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 20));

  void _showTrackOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(3),
                  child: song.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: song.imageUrl,
                          width: 50, height: 50, fit: BoxFit.cover,
                          memCacheWidth: 150, memCacheHeight: 150,
                          errorWidget: (_, __, ___) => Container(width: 50, height: 50, color: SpotifyColors.surface))
                      : Container(width: 50, height: 50, color: SpotifyColors.surface)),

              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(song.title, style: SpotifyFonts.bold(color: Colors.white, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(song.artist, style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
          ),
          const Divider(color: Color(0xFF3A3A3A), height: 1),
          if (playlistId == 'all_songs') ...[
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: Text('Delete song', style: SpotifyFonts.regular(color: Colors.redAccent, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx); // close bottom sheet
                _confirmAndDeleteSong(context);
              },
            ),
            const SizedBox(height: 8),
          ] else ...[
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  void _confirmAndDeleteSong(BuildContext context) {
    showDialog(
      context: context,
      builder: (confirmCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Delete Song?', style: SpotifyFonts.bold(color: Colors.white, fontSize: 18)),
          content: Text(
            'This will permanently delete "${song.title}" from the cloud database, all playlists, and Cloudinary storage. This cannot be undone.',
            style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(confirmCtx),
              child: Text('Cancel', style: SpotifyFonts.bold(color: Colors.white, fontSize: 14)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(confirmCtx);
                _executeSongDeletion(context);
              },
              child: Text('Delete', style: SpotifyFonts.bold(color: Colors.redAccent, fontSize: 14)),
            ),
          ],
        );
      },
    );
  }

  void _executeSongDeletion(BuildContext context) async {
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingCtx) {
        dialogContext = loadingCtx;
        return const Center(
          child: CircularProgressIndicator(color: SpotifyColors.green),
        );
      },
    );

    try {
      await FirebaseService.deleteTrack(song.id);
      
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
      
      if (context.mounted) {
        SpotifyToast.show(
          context,
          'Successfully deleted "${song.title}"',
          icon: Icons.delete_outline,
        );
      }
    } catch (e) {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.pop(dialogContext!);
      }
      if (context.mounted) {
        SpotifyToast.show(
          context,
          'Failed to delete song: $e',
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
        );
      }
    }
  }
}

class _DuplicateResolverSheet extends StatefulWidget {
  final ScrollController scrollController;
  const _DuplicateResolverSheet({required this.scrollController});

  @override
  State<_DuplicateResolverSheet> createState() => _DuplicateResolverSheetState();
}

class _DuplicateResolverSheetState extends State<_DuplicateResolverSheet> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Song>>(
      stream: FirebaseService.streamAllSongs(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: SpotifyColors.green));
        }

        final songs = snapshot.data!;
        
        // Group songs by title and artist
        final Map<String, List<Song>> groups = {};
        for (final song in songs) {
          final key = '${song.title.toLowerCase().trim()} - ${song.artist.toLowerCase().trim()}';
          groups.putIfAbsent(key, () => []).add(song);
        }

        // Filter to duplicates only
        final duplicates = groups.entries
            .where((e) => e.value.length > 1)
            .toList();

        if (duplicates.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, color: SpotifyColors.green, size: 64),
                const SizedBox(height: 16),
                Text(
                  'No Duplicates Found',
                  style: SpotifyFonts.bold(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your library database is completely clean!',
                  style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SpotifyColors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Awesome', style: SpotifyFonts.bold(color: Colors.black)),
                  ),
                ),
              ],
            ),
          );
        }

        // Calculate total extra duplicate files to be deleted
        final totalDuplicatesCount = duplicates.fold<int>(0, (sum, e) => sum + (e.value.length - 1));

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handlebar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Duplicates Checker',
                          style: SpotifyFonts.bold(color: Colors.white, fontSize: 20),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Found ${duplicates.length} duplicate songs ($totalDuplicatesCount extra entries)',
                          style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (!_isProcessing)
                    ElevatedButton(
                      onPressed: () => _autoResolveAll(context, duplicates),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SpotifyColors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: Text('Auto Clean', style: SpotifyFonts.bold(color: Colors.black, fontSize: 13)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white10),
              Expanded(
                child: _isProcessing
                    ? const Center(child: CircularProgressIndicator(color: SpotifyColors.green))
                    : ListView.builder(
                        controller: widget.scrollController,
                        physics: const BouncingScrollPhysics(),
                        itemCount: duplicates.length,
                        itemBuilder: (context, index) {
                          final entry = duplicates[index];
                          final songList = entry.value;
                          final firstSong = songList.first;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: firstSong.imageUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: firstSong.imageUrl,
                                              width: 40, height: 40, fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.grey),
                                            )
                                          : const Icon(Icons.music_note, color: Colors.grey),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            firstSong.title,
                                            style: SpotifyFonts.bold(color: Colors.white, fontSize: 15),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            firstSong.artist,
                                            style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Database entries:',
                                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                ...songList.asMap().entries.map((item) {
                                  final idx = item.key;
                                  final s = item.value;
                                  final isKeepCandidate = idx == 0; // Default candidate to keep

                                  return Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isKeepCandidate ? Colors.green.withValues(alpha: 0.1) : Colors.black12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Entry #${idx + 1}',
                                                    style: SpotifyFonts.bold(
                                                      color: isKeepCandidate ? SpotifyColors.green : Colors.white70,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  if (isKeepCandidate) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: SpotifyColors.green,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Text(
                                                        'KEEP',
                                                        style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'ID: ${s.id}',
                                                style: const TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'monospace'),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!isKeepCandidate)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                            onPressed: () => _deleteSingleTrack(context, s),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteSingleTrack(BuildContext context, Song song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: Text('Delete duplicate track?', style: SpotifyFonts.title(color: Colors.white, fontSize: 18)),
        content: Text(
          'This will permanently delete this duplicate copy of "${song.title}" from the database. This action cannot be undone.',
          style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: SpotifyFonts.bold(color: SpotifyColors.lightGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Delete', style: SpotifyFonts.bold(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await FirebaseService.deleteTrack(song.id);
      if (mounted) {
        SpotifyToast.show(context, 'Deleted "${song.title}" entry successfully', icon: Icons.delete_outline);
      }
    } catch (e) {
      if (mounted) {
        SpotifyToast.show(context, 'Error deleting track: $e', icon: Icons.error_outline, iconColor: Colors.redAccent);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _autoResolveAll(BuildContext context, List<MapEntry<String, List<Song>>> duplicates) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: Text('Auto Clean Duplicates?', style: SpotifyFonts.title(color: Colors.white, fontSize: 18)),
        content: Text(
          'This will automatically keep the first entry of each duplicated song and permanently delete all other duplicates from the database.',
          style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: SpotifyFonts.bold(color: SpotifyColors.lightGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: SpotifyColors.green),
            child: Text('Clean All', style: SpotifyFonts.bold(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    int deletedCount = 0;
    try {
      for (final entry in duplicates) {
        final songList = entry.value;
        // Keep the first one (index 0), delete the rest
        for (int i = 1; i < songList.length; i++) {
          await FirebaseService.deleteTrack(songList[i].id);
          deletedCount++;
        }
      }
      if (mounted) {
        SpotifyToast.show(context, 'Successfully removed $deletedCount duplicate entries', icon: Icons.cleaning_services_rounded);
      }
    } catch (e) {
      if (mounted) {
        SpotifyToast.show(context, 'Error cleaning duplicates: $e', icon: Icons.error_outline, iconColor: Colors.redAccent);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
