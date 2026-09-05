import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_list_tile.dart';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../player/now_playing_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {

  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _isSearching = false;
  String _query = '';
  List<Song> _results = [];
  bool _loading = false;
  Timer? _debounce;


  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        setState(() => _isSearching = true);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    // Show loading immediately for responsiveness
    if (mounted) setState(() { _loading = true; _query = q; });
    // Cancel any previous pending search
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      if (mounted) setState(() { _results = []; _loading = false; });
      return;
    }
    // Wait 350ms after the last keystroke before actually querying
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final res = await FirebaseService.searchTracks(q);
      if (mounted) setState(() { _results = res; _loading = false; });
    });
  }

  void _clearSearch() {
    _ctrl.clear();
    _focus.unfocus();
    setState(() { _query = ''; _results = []; _isSearching = false; });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: SpotifyColors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Fixed top bar: avatar + title + camera ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(
                children: [
                  Text(
                    'Search',
                    style: SpotifyFonts.bold( 
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: Colors.white, size: 28),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // ── Search bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        style: SpotifyFonts.bold( 
                          color: Colors.black,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'What do you want to listen to?',
                          hintStyle: SpotifyFonts.bold( 
                            color: const Color(0xFF4A4A4A),
                            fontSize: 15,
                          ),
                          prefixIcon: const Icon(CupertinoIcons.search,
                              color: Colors.black, size: 24),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onChanged: _search,
                      ),
                    ),
                  ),
                  if (_isSearching) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _clearSearch,
                      child: Text(
                        'Cancel',
                        style: SpotifyFonts.bold( 
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Body (results or recent searches) ──────────────────────────────
            Expanded(
              child: _query.isNotEmpty ? _buildResults() : _buildRecentSearches(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search results ─────────────────────────────────────────────────────────
  Widget _buildResults() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: SpotifyColors.green));
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.search_off, color: SpotifyColors.lightGrey, size: 64),
          const SizedBox(height: 16),
          Text('No results for "$_query"',
              style: SpotifyFonts.bold( 
                  color: SpotifyColors.white,
                  fontSize: 18),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Please try different keywords.',
              style: SpotifyFonts.regular( 
                  color: SpotifyColors.lightGrey, fontSize: 14),
              textAlign: TextAlign.center),
        ]),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (ctx, i) {
        final song = _results[i];
        return TrackListTile(
          song: song,
          allSongs: _results,
          canDelete: true, // Allow deletion from library via search results
          playlistName: 'Search: "$_query"',
          showOptions: false,
        );
      },
    );
  }

  // ── Recent Searches ────────────────────────────────────────────────────────
  Widget _buildRecentSearches() {
    return StreamBuilder<List<Song>>(
      stream: FirebaseService.streamRecentlyPlayed(),
      builder: (context, snapshot) {
        final recents = snapshot.data ?? [];
        if (recents.isEmpty) {
          return Center(
            child: Text(
              'No recent searches',
              style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 16),
            ),
          );
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Recents',
                  style: SpotifyFonts.bold(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = recents[index];
                  return _buildRecentSearchTile(song);
                },
                childCount: recents.length,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: OutlinedButton(
                    onPressed: () {
                      FirebaseService.clearRecentlyPlayed();
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: SpotifyColors.lightGrey, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: Text(
                      'Clear recent searches',
                      style: SpotifyFonts.bold(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentSearchTile(Song song) {
    return InkWell(
      onTap: () {
        // Just play it immediately or re-trigger a search, we'll just play it.
        context.read<PlayerProvider>().playSong(song, playlist: [song]);
        openNowPlaying(context, song);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: song.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: song.imageUrl,
                      width: 52, height: 52, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _imgPlaceholder())
                  : _imgPlaceholder(),

            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: SpotifyFonts.bold(
                        color: SpotifyColors.white,
                        fontSize: 16,
                      )),
                  const SizedBox(height: 2),
                  Text('Song • ${song.artist}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: SpotifyFonts.regular(
                          color: SpotifyColors.lightGrey, fontSize: 13)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                FirebaseService.removeRecentlyPlayed(song.id);
              },
              child: const Icon(Icons.close, color: SpotifyColors.lightGrey, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
    width: 52, height: 52,
    color: SpotifyColors.surface,
    child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 22),
  );

}
