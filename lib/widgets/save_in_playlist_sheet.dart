import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';


/// Shows the "Save In" bottom sheet that lists existing playlists and a
/// "New playlist" option. Designed to match the Spotify reference screenshot.
///
/// Usage:
///   showModalBottomSheet(
///     context: context,
///     isScrollControlled: true,
///     backgroundColor: Colors.transparent,
///     builder: (_) => SaveInPlaylistSheet(song: song),
///   );
class SaveInPlaylistSheet extends StatefulWidget {
  final Song song;
  const SaveInPlaylistSheet({super.key, required this.song});

  @override
  State<SaveInPlaylistSheet> createState() => _SaveInPlaylistSheetState();
}

class _SaveInPlaylistSheetState extends State<SaveInPlaylistSheet> {
  List<Playlist> _playlists = [];
  bool _loading = true;
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // Track which playlists already contain this song
  final Set<String> _containingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {

    // Listen once for playlists
    FirebaseService.streamPlaylists().first.then((playlists) {
      if (!mounted) return;
      // Resolve tracks to check containment
      final containing = <String>{};
      for (final pl in playlists) {
        if (pl.trackIds.contains(widget.song.id)) {
          containing.add(pl.id);
        }
      }
      setState(() {
        _playlists = playlists;
        _containingIds.addAll(containing);
        _loading = false;
      });
    });
  }

  Future<void> _togglePlaylist(Playlist pl) async {
    if (_containingIds.contains(pl.id)) {
      // Remove from playlist
      await FirebaseService.removeTrackFromPlaylist(pl.id, widget.song.id);
      setState(() => _containingIds.remove(pl.id));
    } else {
      // Add to playlist
      await FirebaseService.addTrackToPlaylist(pl.id, widget.song.id);
      setState(() => _containingIds.add(pl.id));
    }
  }

  Future<void> _createNewPlaylist() async {
    final ctrl = TextEditingController();
    String? chosenName;

    // Step 1 – collect the name synchronously inside the dialog,
    // then close immediately with no async work inside the dialog context.
    await showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF282828),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Text(
            'Give your playlist a name',
            style: SpotifyFonts.regular( 
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: SpotifyFonts.regular( color: Colors.white, fontSize: 16),
            cursorColor: SpotifyColors.green,
            textAlign: TextAlign.center,
            onChanged: (_) => setDialogState(() {}),
            decoration: InputDecoration(
              hintText: 'My Playlist #1',
              hintStyle: SpotifyFonts.regular( 
                  color: SpotifyColors.lightGrey, fontSize: 16),
              border: const UnderlineInputBorder(
                  borderSide: BorderSide(color: SpotifyColors.green)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: SpotifyColors.green, width: 2)),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: SpotifyColors.lightGrey)),
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text('Cancel',
                  style: SpotifyFonts.regular( 
                      color: SpotifyColors.lightGrey,
                      fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ctrl.text.trim().isEmpty
                    ? SpotifyColors.surface
                    : SpotifyColors.green,
                foregroundColor: Colors.black,
                shape: const StadiumBorder(),
              ),
              onPressed: ctrl.text.trim().isEmpty
                  ? null
                  : () {
                      // Collect name and close — no async here
                      chosenName = ctrl.text.trim();
                      Navigator.pop(dCtx);
                    },
              child: Text('Create',
                  style: SpotifyFonts.regular( fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    // Step 2 – dialog is now gone; safe to do async Firebase work
    if (chosenName == null || !mounted) return;

    setState(() => _loading = true);

    String? newId;
    String? errorMsg;
    try {
      newId = await FirebaseService.createPlaylist(
          name: chosenName!, trackIds: [widget.song.id]);
    } catch (e) {
      errorMsg = e.toString();
    }

    if (!mounted) return;

    if (newId != null) {
      _containingIds.add(newId);
      _load(); // refreshes the list (_loading → false inside _load)
      SpotifyToast.show(context, 'Added to "$chosenName"', icon: Icons.playlist_add_check);
    } else {
      setState(() => _loading = false);
      SpotifyToast.show(
        context,
        errorMsg ?? 'Permission denied',
        icon: Icons.error_outline,
        iconColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      );
    }
  }

  List<Playlist> get _filtered {
    if (_search.isEmpty) return _playlists;
    return _playlists
        .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      snap: true,
      snapSizes: const [0.75, 0.95],
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              // ── Drag handle ───────────────────────────────────────────────
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: SpotifyColors.lightGrey,
                    borderRadius: BorderRadius.circular(2)),
              ),

              // ── Title row: "Save In" + "Done" button ─────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Save In',
                      style: SpotifyFonts.regular( 
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: SpotifyColors.green,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        'Done',
                        style: SpotifyFonts.regular( 
                            color: SpotifyColors.green,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Search bar ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.search,
                        color: SpotifyColors.lightGrey, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: SpotifyFonts.regular( 
                            color: Colors.white, fontSize: 14),
                        cursorColor: SpotifyColors.green,
                        decoration: InputDecoration(
                          hintText: 'Find a playlist',
                          hintStyle: SpotifyFonts.regular( 
                              color: SpotifyColors.lightGrey, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    if (_search.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(Icons.close,
                              color: SpotifyColors.lightGrey, size: 18),
                        ),
                      ),
                  ]),
                ),
              ),

              const Divider(color: Color(0xFF2A2A2A), height: 1),

              // ── Content (loading / list) ──────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: SpotifyColors.green))
                    : ListView(
                        controller: scrollCtrl,
                        padding: EdgeInsets.zero,
                        children: [
                          // User playlists
                          ..._filtered.map((pl) => _PlaylistRow(
                                playlist: pl,
                                isAdded: _containingIds.contains(pl.id),
                                onTap: () => _togglePlaylist(pl),
                              )),

                          // New Playlist button
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.add,
                                  color: Colors.white, size: 28),
                            ),
                            title: Text(
                              'New playlist',
                              style: SpotifyFonts.regular( 
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15),
                            ),
                            onTap: _createNewPlaylist,
                          ),

                          const SizedBox(height: 40),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}


// ── Individual playlist row ───────────────────────────────────────────────────
class _PlaylistRow extends StatelessWidget {
  final Playlist playlist;
  final bool isAdded;
  final VoidCallback onTap;

  const _PlaylistRow({
    required this.playlist,
    required this.isAdded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Build the 2x2 collage cover or a single cover
    Widget cover;
    final covers = playlist.tracks.take(4).map((t) => t.imageUrl).toList();

    if (covers.length >= 4) {
      // 2x2 grid collage
      cover = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 56, height: 56,
          child: GridView.count(
            crossAxisCount: 2,
            physics: const NeverScrollableScrollPhysics(),
            children: covers.map((url) => url.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                      color: SpotifyColors.surface,
                      child: const Icon(Icons.music_note,
                          color: SpotifyColors.lightGrey, size: 14)))
              : Container(
                  color: SpotifyColors.surface,
                  child: const Icon(Icons.music_note,
                      color: SpotifyColors.lightGrey, size: 14)),
            ).toList(),
          ),
        ),
      );
    } else if (covers.isNotEmpty && covers.first.isNotEmpty) {
      cover = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: covers.first,
          width: 56, height: 56,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );

    } else {
      cover = _placeholder();
    }

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SizedBox(width: 56, height: 56, child: cover),
      title: Text(
        playlist.name,
        style: SpotifyFonts.regular( 
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.trackCount} songs',
        style: SpotifyFonts.regular( 
            color: SpotifyColors.lightGrey, fontSize: 13),
      ),
      trailing: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isAdded ? SpotifyColors.green : SpotifyColors.lightGrey,
              width: 1.5,
            ),
            color: isAdded ? SpotifyColors.green : Colors.transparent,
          ),
          child: Icon(
            isAdded ? Icons.check : Icons.add,
            color: isAdded ? Colors.black : SpotifyColors.lightGrey,
            size: 16,
          ),
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _placeholder() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 56, height: 56,
      color: SpotifyColors.surface,
      child: const Icon(Icons.queue_music,
          color: SpotifyColors.lightGrey, size: 28),
    ),
  );
}
