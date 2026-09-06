import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';


// ════════════════════════════════════════════════════════════════════════════
//  ADD SONGS SCREEN
// ════════════════════════════════════════════════════════════════════════════
class AddSongsScreen extends StatefulWidget {
  final String playlistId;
  final List<String> existingTrackIds;

  const AddSongsScreen({
    super.key,
    required this.playlistId,
    required this.existingTrackIds,
  });

  @override
  State<AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends State<AddSongsScreen> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Song> _allSongs = [];
  List<Song> _filtered = [];
  final Set<String> _adding = {}; // tracks being added
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  Future<void> _load() async {
    final all = await FirebaseService.fetchAllTracks();
    if (!mounted) return;
    // Exclude songs already in the playlist
    final existing = Set<String>.from(widget.existingTrackIds);
    setState(() {
      _allSongs = all.where((s) => !existing.contains(s.id)).toList();
      _filtered = List.from(_allSongs);
      _loading = false;
    });
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = _allSongs
          .where((s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _add(Song song) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _adding.add(song.id));
    try {
      await FirebaseService.addTrackToPlaylist(widget.playlistId, song.id);
      if (!mounted) return;
      SpotifyToast.show(context, 'Added "${song.title}" to playlist', icon: Icons.playlist_add_check);
      // Remove from list after adding
      setState(() {
        _adding.remove(song.id);
        _allSongs.removeWhere((s) => s.id == song.id);
        _filtered.removeWhere((s) => s.id == song.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding.remove(song.id));
      SpotifyToast.show(context, 'Failed to add song: $e', icon: Icons.error_outline, iconColor: Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.black,
      appBar: AppBar(
        backgroundColor: SpotifyColors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add to this playlist',
          style: SpotifyFonts.regular( color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.search, color: SpotifyColors.lightGrey, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocusNode,
                      style: SpotifyFonts.regular( color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'What would you like to add?',
                        hintStyle: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        suffixIcon: _search.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _search.clear();
                                  _searchFocusNode.unfocus();
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(Icons.close, color: SpotifyColors.lightGrey, size: 20),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Song list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: SpotifyColors.green))
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _search.text.isEmpty ? 'All songs already added!' : 'No results found',
                          style: SpotifyFonts.regular( color: SpotifyColors.lightGrey),
                        ),
                      )
                    : ListView.builder(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final song = _filtered[i];
                          final isAdding = _adding.contains(song.id);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: song.imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: song.imageUrl,
                                      width: 50, height: 50, fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => _ph())
                                  : _ph(),

                            ),
                            title: Text(song.title,
                                style: SpotifyFonts.regular( 
                                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(song.artist,
                                style: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 12),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: isAdding
                                ? const SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(
                                        color: SpotifyColors.green, strokeWidth: 2))
                                : GestureDetector(
                                    onTap: () => _add(song),
                                    child: Container(
                                      width: 28, height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: SpotifyColors.lightGrey, width: 1.5),
                                      ),
                                      child: const Icon(Icons.add, color: Colors.white, size: 18),
                                    ),
                                  ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _ph() => Container(
    width: 50, height: 50,
    color: SpotifyColors.surface,
    child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 22),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  EDIT PLAYLIST SCREEN  (reorder + delete)
// ════════════════════════════════════════════════════════════════════════════
class EditPlaylistScreen extends StatefulWidget {
  final String playlistId;
  final List<Song> songs;

  const EditPlaylistScreen({
    super.key,
    required this.playlistId,
    required this.songs,
  });

  @override
  State<EditPlaylistScreen> createState() => _EditPlaylistScreenState();
}

class _EditPlaylistScreenState extends State<EditPlaylistScreen> {
  late List<Song> _songs;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _songs = List.from(widget.songs);
  }

  Future<void> _save() async {
    if (!_dirty) { Navigator.pop(context); return; }
    setState(() => _saving = true);
    await FirebaseService.reorderPlaylistTracks(
      widget.playlistId,
      _songs.map((s) => s.id).toList(),
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _remove(int index) {
    final song = _songs[index];
    setState(() { _songs.removeAt(index); _dirty = true; });
    // Actually remove from Firebase too
    FirebaseService.removeTrackFromPlaylist(widget.playlistId, song.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.black,
      appBar: AppBar(
        backgroundColor: SpotifyColors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Edit playlist',
            style: SpotifyFonts.regular( color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: SpotifyColors.green, strokeWidth: 2))))
              : TextButton(
                  onPressed: _save,
                  child: Text('Save',
                      style: SpotifyFonts.regular( 
                          color: SpotifyColors.green, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
        ],
        elevation: 0,
      ),
      body: ReorderableListView.builder(
        itemCount: _songs.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final item = _songs.removeAt(oldIndex);
            _songs.insert(newIndex, item);
            _dirty = true;
          });
        },
        proxyDecorator: (child, index, animation) => Material(
          color: const Color(0xFF383838),
          borderRadius: BorderRadius.circular(8),
          elevation: 8,
          child: child,
        ),
        itemBuilder: (context, i) {
          final song = _songs[i];
          return ListTile(
            key: ValueKey(song.id),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              // Red remove button (⊖)
              GestureDetector(
                onTap: () => _remove(i),
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent, width: 1.8),
                  ),
                  child: const Icon(Icons.remove, color: Colors.redAccent, size: 16),
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: song.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: song.imageUrl,
                        width: 48, height: 48, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _ph())
                    : _ph(),
              ),
            ]),
            title: Text(song.title,
                style: SpotifyFonts.regular( color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(song.artist,
                style: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.drag_handle, color: SpotifyColors.lightGrey, size: 22),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _ph() => Container(
    width: 48, height: 48,
    color: SpotifyColors.surface,
    child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 20),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  SORT BOTTOM SHEET
// ════════════════════════════════════════════════════════════════════════════
enum PlaylistSortOrder { custom, title, artist, album, recentlyAdded }

void showSortSheet(
  BuildContext context,
  PlaylistSortOrder current,
  ValueChanged<PlaylistSortOrder> onChanged,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF282828),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) {
      final options = [
        (PlaylistSortOrder.custom,        'Custom order'),
        (PlaylistSortOrder.title,         'Title'),
        (PlaylistSortOrder.artist,        'Artist'),
        (PlaylistSortOrder.album,         'Album'),
        (PlaylistSortOrder.recentlyAdded, 'Recently added'),
      ];
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('Sort by',
                  style: SpotifyFonts.regular( 
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ...options.map((opt) {
              final isActive = opt.$1 == current;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(opt.$2,
                    style: SpotifyFonts.regular( 
                      color: isActive ? SpotifyColors.green : Colors.white,
                      fontSize: 16,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    )),
                trailing: isActive
                    ? const Icon(Icons.check, color: SpotifyColors.green, size: 22)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onChanged(opt.$1);
                },
              );
            }),
          ],
        ),
      );
    },
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  NAME & DETAILS BOTTOM SHEET
// ════════════════════════════════════════════════════════════════════════════
void showNameDetailsSheet(
  BuildContext context,
  Playlist playlist,
  List<Song> songs,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NameDetailsSheet(playlist: playlist, songs: songs),
  );
}

class _NameDetailsSheet extends StatefulWidget {
  final Playlist playlist;
  final List<Song> songs;
  const _NameDetailsSheet({required this.playlist, required this.songs});

  @override
  State<_NameDetailsSheet> createState() => _NameDetailsSheetState();
}

class _NameDetailsSheetState extends State<_NameDetailsSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.playlist.name);
    _descCtrl = TextEditingController(text: widget.playlist.description);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseService.updatePlaylistDetails(
        widget.playlist.id,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      if (!mounted) return;
      SpotifyToast.show(context, 'Playlist details saved', icon: Icons.check);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SpotifyToast.show(context, 'Failed to update details: $e', icon: Icons.error_outline, iconColor: Colors.redAccent);
    }
  }

  Future<void> _deletePlaylist() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Delete playlist?',
            style: SpotifyFonts.regular( color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'This will delete "${widget.playlist.name}" and all of its songs will be removed.',
          style: SpotifyFonts.regular( color: SpotifyColors.lightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: SpotifyFonts.regular( color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: SpotifyFonts.regular( color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      try {
        await FirebaseService.deletePlaylist(widget.playlist.id);
        if (!mounted) return;
        SpotifyToast.show(context, 'Playlist "${widget.playlist.name}" deleted', icon: Icons.delete_outline);
        Navigator.pop(context); // close sheet
        Navigator.pop(context); // go back from playlist detail
      } catch (e) {
        if (!mounted) return;
        SpotifyToast.show(context, 'Failed to delete playlist: $e', icon: Icons.error_outline, iconColor: Colors.redAccent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SingleChildScrollView(
          controller: scrollCtrl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel',
                          style: SpotifyFonts.regular( color: Colors.white, fontSize: 14)),
                    ),
                    const Spacer(),
                    Text('Name & details',
                        style: SpotifyFonts.regular( 
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: SpotifyColors.green, strokeWidth: 2))
                        : TextButton(
                            onPressed: _save,
                            child: Text('Save',
                                style: SpotifyFonts.regular( 
                                    color: SpotifyColors.green,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ),
                  ],
                ),
              ),

              // Cover + fields
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 4-grid cover thumbnail
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 120, height: 120,
                            child: _buildMiniCollage(widget.songs),
                          ),
                        ),
                        Positioned(
                          bottom: 4, right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, color: Colors.white, size: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),

                    // Name + description fields
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _nameCtrl,
                            style: SpotifyFonts.regular( color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: widget.playlist.name,
                              hintStyle: SpotifyFonts.regular( color: SpotifyColors.lightGrey),
                              filled: true,
                              fillColor: const Color(0xFF2A2A2A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descCtrl,
                            maxLines: 3,
                            style: SpotifyFonts.regular( color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Add description',
                              hintStyle: SpotifyFonts.regular( color: SpotifyColors.lightGrey),
                              filled: true,
                              fillColor: const Color(0xFF2A2A2A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: Color(0xFF2A2A2A), height: 1),

              // Make public
              ListTile(
                leading: const Icon(Icons.public_outlined, color: Colors.white, size: 24),
                title: Text('Make public',
                    style: SpotifyFonts.regular( color: Colors.white, fontSize: 16)),
                onTap: () {},
              ),
              const Divider(color: Color(0xFF2A2A2A), height: 1),

              // Delete
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
                title: Text('Delete playlist',
                    style: SpotifyFonts.regular( color: Colors.white, fontSize: 16)),
                onTap: _deletePlaylist,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniCollage(List<Song> songs) {
    final covers = songs.take(4).map((s) => s.imageUrl).toList();
    if (covers.length >= 4) {
      return GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: covers.map((u) => _coverImg(u)).toList(),
      );
    }
    return covers.isNotEmpty && covers.first.isNotEmpty
        ? _coverImg(covers.first)
        : Container(color: SpotifyColors.surface,
            child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 32));
  }

  Widget _coverImg(String url) {
    if (url.isEmpty) return Container(color: SpotifyColors.surface);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => Container(color: SpotifyColors.surface),
    );
  }
}
