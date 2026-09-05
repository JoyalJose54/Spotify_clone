import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/ingestion_service.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../providers/ingestion_provider.dart';
import '../../models/models.dart';

typedef _Playlist = ({String id, String name});

// ─────────────────────────────────────────────────────────────────────────────
//  IngestionPage  –  accessible via the "+" FAB near the Library screen.
// ─────────────────────────────────────────────────────────────────────────────
class IngestionPage extends StatefulWidget {
  const IngestionPage({super.key});

  @override
  State<IngestionPage> createState() => _IngestionPageState();
}

class _IngestionPageState extends State<IngestionPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Timer? _statusTimer;
  bool? _isBackendOnline;
  
  // Shared playlist + tracks state
  List<_Playlist> _playlists = [];
  List<Song>      _cachedTracks = [];
  String?         _selectedPlaylist;
  bool            _loadingPlaylists = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadPlaylistsAndTracks();
    _checkBackendStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkBackendStatus());
  }

  Future<void> _checkBackendStatus() async {
    final online = await IngestionService.isBackendOnline();
    if (!mounted) return;
    setState(() {
      _isBackendOnline = online;
    });
  }

  Future<void> _showBackendSettingsDialog() async {
    final currentUrl = await IngestionService.getActiveBackendUrl();
    final ctrl = TextEditingController(text: currentUrl);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.settings, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              'Backend Settings',
              style: SpotifyFonts.regular(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configure the URL for your Python ingestion backend (e.g. PC Local IP or cloud URL).',
              style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              style: SpotifyFonts.regular(color: Colors.white, fontSize: 14),
              cursorColor: SpotifyColors.green,
              decoration: InputDecoration(
                hintText: 'https://spotify-clone-uehl.onrender.com',
                hintStyle: SpotifyFonts.regular(color: Colors.grey, fontSize: 13),
                labelText: 'Backend Server URL',
                labelStyle: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 12),
                border: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3E3E3E)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: SpotifyColors.green, width: 1.5),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3E3E3E)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.text = 'https://spotify-ingestion-backend.onrender.com';
            },
            child: Text(
              'Use Cloud (Render)',
              style: SpotifyFonts.regular(color: SpotifyColors.green, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(
              'Cancel',
              style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SpotifyColors.green,
              foregroundColor: Colors.black,
              shape: const StadiumBorder(),
            ),
            onPressed: () async {
              final newUrl = ctrl.text.trim();
              if (newUrl.isNotEmpty) {
                final nav = Navigator.of(dCtx);
                await IngestionService.updateBackendUrl(newUrl);
                if (mounted) {
                  SpotifyToast.show(context, 'Backend URL updated!', icon: Icons.save);
                }
                nav.pop();
                _checkBackendStatus();
              }
            },
            child: Text(
              'Save',
              style: SpotifyFonts.regular(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPlaylistsAndTracks() async {
    try {
      final snap = await FirebaseService.fetchUserPlaylists();
      final tracks = await FirebaseService.fetchAllTracks();
      if (!mounted) return;

      final provider = context.read<IngestionProvider>();
      if (provider.localPlaylists.isEmpty || !provider.csvProcessing) {
        provider.localPlaylists = List.from(snap);
      }

      setState(() {
        _playlists        = snap;
        _cachedTracks     = tracks;
        _loadingPlaylists = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingPlaylists = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _handlePlaylistSelection(String? value) async {
    if (value == '_create_new_') {
      final newPlaylistId = await _showCreatePlaylistDialog(context);
      if (newPlaylistId != null) {
        await _loadPlaylistsAndTracks();
        setState(() {
          _selectedPlaylist = newPlaylistId;
        });
      }
    } else {
      setState(() {
        _selectedPlaylist = value;
      });
    }
  }

  Future<String?> _showCreatePlaylistDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    String? chosenName;

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

    if (chosenName == null || !context.mounted) return null;

    try {
      final newId = await FirebaseService.createPlaylist(name: chosenName!);
      if (context.mounted) {
        SpotifyToast.show(context, 'Playlist "$chosenName" created!', icon: Icons.playlist_add_check);
      }
      return newId;
    } catch (e) {
      if (context.mounted) {
        SpotifyToast.show(
          context,
          'Failed to create playlist: $e',
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
        );
      }
      return null;
    }
  }


  @override
  Widget build(BuildContext context) {
    final isOnline = _isBackendOnline;
    final statusColor = isOnline == null
        ? Colors.orange
        : (isOnline ? SpotifyColors.green : const Color(0xFFFF4B4B));

    return Scaffold(
      backgroundColor: const Color(0xFF090A0E),
      appBar: AppBar(
        toolbarHeight: 76,
        backgroundColor: const Color(0xFF0E1015),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10.0, top: 6.0),
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Column(
            children: [
              Text(
                'Smart Ingestion',
                style: SpotifyFonts.bold(
                  color: Colors.white,
                  fontSize: 18.5,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      SpotifyColors.green.withValues(alpha: 0.2),
                      const Color(0xFF00E5FF).withValues(alpha: 0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: SpotifyColors.green.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  'STUDIO LOSSLESS ENGINE',
                  style: SpotifyFonts.bold(
                    color: SpotifyColors.green,
                    fontSize: 8.5,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14.0, top: 6.0),
            child: Center(
              child: GestureDetector(
                onTap: _showBackendSettingsDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.45),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.2),
                        blurRadius: 8,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.8),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      )
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.25, 1.25)),
                      const SizedBox(width: 7),
                      Text(
                        isOnline == null
                            ? 'Checking'
                            : (isOnline ? 'Online' : 'Offline'),
                        style: SpotifyFonts.bold(
                          color: statusColor,
                          fontSize: 11,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.tune_rounded, color: statusColor.withValues(alpha: 0.7), size: 13),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(74),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            padding: const EdgeInsets.all(4.5),
            decoration: BoxDecoration(
              color: const Color(0xFF14171E),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFF282D3B)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TabBar(
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              controller: _tab,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF1DB954),
                    Color(0xFF1ED760),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: SpotifyColors.green.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.white70,
              labelStyle: SpotifyFonts.bold(fontSize: 12.5),
              unselectedLabelStyle: SpotifyFonts.bold(fontSize: 12.5),
              tabs: const [
                Tab(
                  height: 42,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload_file_rounded, size: 17),
                      SizedBox(width: 8),
                      Text('CSV Import'),
                    ],
                  ),
                ),
                Tab(
                  height: 42,
                  child: Center(
                    child: Text('Online Search'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0E1016),
              Color(0xFF08090C),
            ],
          ),
        ),
        child: TabBarView(
          controller: _tab,
          children: [
            _CsvTab(
              playlists: _playlists,
              cachedTracks: _cachedTracks,
              selectedPlaylist: _selectedPlaylist,
              loadingPlaylists: _loadingPlaylists,
              onPlaylistChanged: _handlePlaylistSelection,
            ),
            _SearchTab(
              playlists: _playlists,
              cachedTracks: _cachedTracks,
              selectedPlaylist: _selectedPlaylist,
              loadingPlaylists: _loadingPlaylists,
              onPlaylistChanged: _handlePlaylistSelection,
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  CSV TAB
// ═════════════════════════════════════════════════════════════════════════
class _CsvTab extends StatefulWidget {
  final List<_Playlist>     playlists;
  final List<Song>          cachedTracks;
  final String?             selectedPlaylist;
  final bool                loadingPlaylists;
  final ValueChanged<String?> onPlaylistChanged;

  const _CsvTab({
    required this.playlists,
    required this.cachedTracks,
    required this.selectedPlaylist,
    required this.loadingPlaylists,
    required this.onPlaylistChanged,
  });

  @override
  State<_CsvTab> createState() => _CsvTabState();
}

class _CsvTabState extends State<_CsvTab> {
  Future<void> _pickCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final path    = result.files.first.path!;
    final content = await File(path).readAsString();
    final entries = IngestionService.parseCsv(content);

    if (!mounted) return;
    if (entries.isEmpty) {
      _showSnack('No valid entries found in CSV.');
      return;
    }

    final provider = context.read<IngestionProvider>();
    provider.setCsvEntries(entries.map((e) => CsvEntryState(entry: e)).toList());
  }

  Future<void> _startProcessing() async {
    final provider = context.read<IngestionProvider>();
    if (provider.csvEntries.isEmpty || provider.csvProcessing) return;

    final hasCsvPlaylists = provider.csvEntries.any((e) => e.entry.playlistName.trim().isNotEmpty);
    if (widget.selectedPlaylist == null && !hasCsvPlaylists) {
      _showSnack('Please select a playlist first', isError: true, icon: Icons.playlist_add);
      return;
    }

    await provider.startCsvProcessing(
      selectedPlaylistId: widget.selectedPlaylist,
      cachedTracks: widget.cachedTracks,
      playlists: provider.localPlaylists,
      showSnack: (msg, {isError = false}) {
        if (mounted) {
          _showSnack(msg, isError: isError);
        }
      },
    );

    if (mounted && provider.csvDupCount == 0) {
      _showSummaryAndClear(provider);
    }
  }

  Future<void> _processForcedDownloads(List<CsvEntryState> selectedDups) async {
    final provider = context.read<IngestionProvider>();
    provider.startCsvForcedDownloads(
      selectedDups: selectedDups,
      selectedPlaylistId: widget.selectedPlaylist,
      showSnack: (msg, {isError = false}) {
        if (mounted) {
          _showSnack(msg, isError: isError);
        }
      },
    );
  }

  void _showSnack(String msg, {bool isError = false, IconData? icon}) {
    SpotifyToast.show(
      context,
      msg,
      icon: icon ?? (isError ? Icons.error_outline : Icons.check_circle_outline),
      iconColor: isError ? Colors.redAccent : SpotifyColors.green,
    );
  }

  // Guard flag: ensures only ONE addPostFrameCallback is ever pending.
  // Without this, every provider notification during ingestion stacks a new
  // callback inside build(), causing the semantics tree to corrupt and the
  // screen to go black.
  bool _showingDuplicateDialog = false;

  void _maybeShowDuplicateDialog(IngestionProvider provider) {
    if (_showingDuplicateDialog) return;
    if (provider.pendingDuplicates.isEmpty || provider.csvProcessing) return;

    _showingDuplicateDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) { _showingDuplicateDialog = false; return; }

      final duplicates = List<CsvEntryState>.from(provider.pendingDuplicates);
      provider.clearPendingDuplicates();

      final List<CsvEntryState>? selectedDups = await showDialog<List<CsvEntryState>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DuplicateSelectionDialog(
          duplicates: duplicates,
          successCount: provider.csvSuccessCount,
          failCount: provider.csvFailCount,
        ),
      );

      if (mounted) {
        if (selectedDups != null) {
          final unselectedDups = duplicates.where((d) => !selectedDups.contains(d)).toList();
          if (unselectedDups.isNotEmpty) {
            await provider.linkDuplicateReferences(
              duplicates: unselectedDups,
              selectedPlaylistId: widget.selectedPlaylist,
            );
          }
          if (selectedDups.isNotEmpty) {
            await _processForcedDownloads(selectedDups);
          }
        }
        
        if (mounted) {
          _showSummaryAndClear(provider);
        }
      }
      _showingDuplicateDialog = false;
    });
  }

  void _showSummaryAndClear(IngestionProvider provider) {
    final success = provider.csvSuccessCount;
    final dup = provider.csvDupCount;
    final fail = provider.csvFailCount;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: SpotifyColors.green, size: 20),
            const SizedBox(width: 10),
            Text(
              'Ingestion Complete',
              style: SpotifyFonts.regular(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All songs in the CSV file have been processed:',
              style: SpotifyFonts.regular(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _SummaryRow(label: 'Successfully Added', count: success, color: SpotifyColors.green, icon: Icons.check_circle_outline),
            const SizedBox(height: 8),
            _SummaryRow(label: 'Duplicates Linked', count: dup, color: const Color(0xFF1A78C2), icon: Icons.copy_outlined),
            const SizedBox(height: 8),
            _SummaryRow(label: 'Failed to Ingest', count: fail, color: SpotifyColors.error, icon: Icons.error_outline),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: SpotifyColors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(dCtx);
              provider.clearCsvState();
            },
            child: Text(
              'OK',
              style: SpotifyFonts.regular(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IngestionProvider>();

    // Safely trigger duplicate dialog — guarded, never stacks callbacks.
    _maybeShowDuplicateDialog(provider);

    final total    = provider.csvEntries.length;
    final progress = total == 0 ? 0.0 : provider.csvDoneCount / total;

    return Column(children: [
      // ── Playlist picker + action buttons ──────────────────────────────────
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF11141C),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF1F2433)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Playlist picker
          widget.loadingPlaylists
              ? const SizedBox(
                  height: 54,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: SpotifyColors.green,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : _PlaylistDropdown(
                  playlists: provider.localPlaylists,
                  selected: widget.selectedPlaylist,
                  onChanged: widget.onPlaylistChanged,
                ),
          const SizedBox(height: 16),
          // Row: Pick file + Start
          Row(children: [
            Expanded(
              child: _GreenOutlineButton(
                icon: Icons.upload_file_rounded,
                label: 'Pick CSV',
                onTap: provider.csvProcessing ? null : _pickCsv,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GreenButton(
                icon: Icons.rocket_launch_rounded,
                label: 'Ingest All',
                loading: provider.csvProcessing,
                onTap: (!provider.csvProcessing && provider.csvEntries.isNotEmpty)
                    ? _startProcessing
                    : null,
              ),
            ),
          ]),
        ]),
      ),

      // ── Progress Dashboard ─────────────────────────────────────────────────
      if (total > 0) ...[
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF232B3E)),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: SpotifyColors.green.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.sync_rounded, color: SpotifyColors.green, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Batch Ingestion Progress',
                        style: SpotifyFonts.bold(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: SpotifyColors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SpotifyColors.green.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${(progress * 100).toInt()}%',
                      style: SpotifyFonts.bold(
                        color: SpotifyColors.green,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 7,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: const Color(0xFF1E2433),
                    valueColor: const AlwaysStoppedAnimation<Color>(SpotifyColors.green),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Stats badges
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatBadge(
                    label: 'Success',
                    count: provider.csvSuccessCount,
                    color: SpotifyColors.green,
                    icon: Icons.check_circle_rounded,
                  ),
                  _StatBadge(
                    label: 'Duplicate',
                    count: provider.csvDupCount,
                    color: const Color(0xFF00E5FF),
                    icon: Icons.copy_rounded,
                  ),
                  _StatBadge(
                    label: 'Failed',
                    count: provider.csvFailCount,
                    color: SpotifyColors.error,
                    icon: Icons.error_rounded,
                  ),
                ],
              ),
              if (provider.csvProcessing && provider.csvActiveTrack.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Color(0xFF232B3E), height: 1),
                ),
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: Colors.amber,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ingesting: ${provider.csvActiveTrack}',
                        style: SpotifyFonts.bold(
                          color: Colors.amber,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],

      // ── Entry list ─────────────────────────────────────────────────────────
      Expanded(
        child: provider.csvEntries.isEmpty
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11141C),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF1F2433)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                SpotifyColors.green.withValues(alpha: 0.25),
                                SpotifyColors.green.withValues(alpha: 0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: SpotifyColors.green.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.cloud_upload_rounded,
                            color: SpotifyColors.green,
                            size: 32,
                          ),
                        )
                            .animate(onPlay: (controller) => controller.repeat(reverse: true))
                            .moveY(begin: 0, end: -6, duration: 1800.ms, curve: Curves.easeInOut),
                        const SizedBox(height: 18),
                        Text(
                          'Batch Import Songs via CSV',
                          style: SpotifyFonts.bold(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Select a .csv file containing song metadata to automatically resolve high-bitrate audio, download album artwork, and sync tags directly to your local library.',
                          textAlign: TextAlign.center,
                          style: SpotifyFonts.regular(
                            color: SpotifyColors.lightGrey,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF181C26),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF262E40)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.table_chart_rounded, color: SpotifyColors.green, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Headers: "Title, Artist"',
                                style: SpotifyFonts.bold(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: _pickCsv,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1DB954), Color(0xFF15883E)],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: SpotifyColors.green.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.file_upload_rounded, color: Colors.black, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Choose CSV File',
                                  style: SpotifyFonts.bold(
                                    color: Colors.black,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: provider.csvEntries.length,
                itemBuilder: (_, i) => _CsvEntryTile(row: provider.csvEntries[i]),
              ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StatBadge({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: SpotifyFonts.regular(
              color: color.withValues(alpha: 0.9),
              fontSize: 11,
            ),
          ),
          Text(
            '$count',
            style: SpotifyFonts.bold(
              color: color,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _CsvEntryTile extends StatelessWidget {
  final CsvEntryState row;
  const _CsvEntryTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (row.status) {
      EntryStatus.done      => (SpotifyColors.green, Icons.check_circle_rounded),
      EntryStatus.duplicate => (const Color(0xFF00E5FF), Icons.copy_rounded),
      EntryStatus.failed    => (SpotifyColors.error, Icons.error_rounded),
      EntryStatus.processing => (Colors.amber, Icons.hourglass_top_rounded),
      EntryStatus.pending   => (SpotifyColors.lightGrey, Icons.radio_button_unchecked),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: row.status == EntryStatus.processing
              ? Colors.amber.withValues(alpha: 0.4)
              : row.status == EntryStatus.done
                  ? SpotifyColors.green.withValues(alpha: 0.25)
                  : const Color(0xFF1E2433),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
          ),
          child: row.status == EntryStatus.processing
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                )
              : Icon(icon, color: color, size: 18),
        ),
        title: Text(
          row.entry.title,
          style: SpotifyFonts.bold(
            color: Colors.white,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          row.entry.artist,
          style: SpotifyFonts.regular(
            color: SpotifyColors.lightGrey,
            fontSize: 11,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: row.message.isNotEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Text(
                  row.message,
                  style: SpotifyFonts.bold(
                    color: color,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.end,
                ),
              )
            : null,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SEARCH TAB
// ═════════════════════════════════════════════════════════════════════════════
class _SearchTab extends StatefulWidget {
  final List<_Playlist>       playlists;
  final List<Song>            cachedTracks;
  final String?               selectedPlaylist;
  final bool                  loadingPlaylists;
  final ValueChanged<String?> onPlaylistChanged;

  const _SearchTab({
    required this.playlists,
    required this.cachedTracks,
    required this.selectedPlaylist,
    required this.loadingPlaylists,
    required this.onPlaylistChanged,
  });

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _ctrl = TextEditingController();

  // 15-second Audio Preview state
  String?       _previewVideoId;
  bool          _previewLoading = false;
  ap.AudioPlayer?  _previewPlayer;

  @override
  void initState() {
    super.initState();
    final provider = context.read<IngestionProvider>();
    _ctrl.text = provider.searchQuery;
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    final provider = context.read<IngestionProvider>();
    await _stopPreview();
    if (!mounted) return;

    provider.setSearchSearching(true);

    final res = await IngestionService.searchYouTube(q);
    if (!mounted) return;

    String? errorMsg;
    if (res.isEmpty) errorMsg = 'No results found for "$q"';
    provider.setSearchResults(q, res, errorMsg);

    // Pre-check all results against library and Firestore in the background
    if (res.isNotEmpty) {
      provider.preCheckSearchResults(res, widget.cachedTracks);
    }
  }

  Future<void> _stopPreview() async {
    if (_previewPlayer != null) {
      await _previewPlayer!.stop();
      await _previewPlayer!.dispose();
      _previewPlayer = null;
    }
    if (mounted) {
      setState(() {
        _previewVideoId = null;
        _previewLoading = false;
      });
    }
  }

  Future<void> _ingest(YouTubeSearchResult r) async {
    if (widget.selectedPlaylist == null) {
      _showSnack('Please select a playlist first', isError: true, icon: Icons.playlist_add);
      return;
    }

    final provider = context.read<IngestionProvider>();
    if (_previewVideoId == r.videoId) {
      await _stopPreview();
      if (!mounted) return;
    }

    final potentialDup = provider.checkPotentialDuplicatePublic(r, widget.cachedTracks);
    final hasCloudDup = provider.libraryCheck[r.videoId] != null;

    if (potentialDup != null || hasCloudDup) {
      final dupTitle = potentialDup?.title ?? r.title;
      final dupArtist = potentialDup?.artist ?? r.artist;
      SpotifyDialog.show(
        context: context,
        title: 'Already in Library',
        message: '"$dupTitle" by $dupArtist is already in your library.\n\nDo you still want to import this song?',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.amber,
        confirmLabel: 'ADD ANYWAY',
        cancelLabel: 'CANCEL',
        onConfirm: () {
          _runIngestPipeline(r, bypassDedup: true);
        },
      );
    } else {
      _runIngestPipeline(r);
    }
  }

  Future<void> _runIngestPipeline(YouTubeSearchResult r, {bool bypassDedup = false}) async {
    final provider = context.read<IngestionProvider>();
    provider.runSearchIngest(
      r: r,
      selectedPlaylistId: widget.selectedPlaylist,
      cachedTracks: widget.cachedTracks,
      bypassDedup: bypassDedup,
      showSnack: (msg, {isError = false, IconData? icon}) {
        if (mounted) {
          _showSnack(msg, isError: isError, icon: icon);
        }
      },
    );
  }

  void _showSnack(String msg, {bool isError = false, IconData? icon}) {
    SpotifyToast.show(
      context,
      msg,
      icon: icon ?? (isError ? Icons.error_outline : Icons.check_circle_outline),
      iconColor: isError ? Colors.redAccent : SpotifyColors.green,
    );
  }

  Future<void> _togglePreview(YouTubeSearchResult r) async {
    if (_previewVideoId == r.videoId) {
      await _stopPreview();
      return;
    }

    await _stopPreview();
    setState(() {
      _previewVideoId = r.videoId;
      _previewLoading = true;
    });

    try {
      if (!mounted) return;
      try {
        final pProvider = context.read<PlayerProvider>();
        if (pProvider.isPlaying) {
          pProvider.togglePlayPause();
        }
      } catch (_) {}

      final source = await IngestionService.getPreviewSource(
        r.videoId,
        title: r.title,
        artist: r.artist,
      );
      if (source == null) throw 'Preview source empty';

      if (!mounted || _previewVideoId != r.videoId) return;

      _previewPlayer = ap.AudioPlayer();
      await _previewPlayer!.setSource(source);
      
      if (!mounted || _previewVideoId != r.videoId) {
        await _previewPlayer?.dispose();
        return;
      }

      setState(() {
        _previewLoading = false;
      });

      await _previewPlayer!.resume();

      _previewPlayer!.onPositionChanged.listen((pos) {
        if (pos.inSeconds >= 15) {
          _stopPreview();
        }
      });

      _previewPlayer!.onPlayerComplete.listen((_) {
        _stopPreview();
      });

    } catch (e) {
      debugPrint('PREVIEW ERROR: $e');
      if (mounted) {
        setState(() {
          _previewVideoId = null;
          _previewLoading = false;
        });
        SpotifyToast.show(context, 'Preview unavailable', icon: Icons.error_outline, iconColor: Colors.redAccent);
      }
    }
  }

  static const _trendingChips = [
    '🔥 Trending',
    'Believer',
    'Starboy',
    'Coldplay',
    'Arijit Singh',
    'Die With A Smile',
    'Shape of You',
    'Tamil Hits',
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IngestionProvider>();
    final results = provider.searchResults;
    final searching = provider.isSearching;
    final error = provider.searchError;

    return Column(children: [
      // ── Controls Container with Glassmorphism ─────────────────────────────
      Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF11141C),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF1F2433)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Column(
          children: [
            // Target Playlist Selector
            widget.loadingPlaylists
                ? const SizedBox(
                    height: 48,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: SpotifyColors.green,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : _PlaylistDropdown(
                    playlists: provider.localPlaylists,
                    selected: widget.selectedPlaylist,
                    onChanged: widget.onPlaylistChanged,
                  ),
            const SizedBox(height: 12),
            // Search bar row
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF181C26),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2B3346)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            style: SpotifyFonts.regular(
                              color: Colors.white,
                              fontSize: 13.5,
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _search(),
                            decoration: InputDecoration(
                              hintText: 'Search songs, artists, or paste URL...',
                              hintStyle: SpotifyFonts.regular(
                                color: SpotifyColors.lightGrey,
                                fontSize: 13,
                              ),
                              filled: false,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_ctrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _ctrl.clear();
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Icon(
                                Icons.close_rounded,
                                color: SpotifyColors.lightGrey.withValues(alpha: 0.8),
                                size: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _GreenButton(
                  label: 'Search',
                  loading: searching,
                  onTap: searching ? null : _search,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Quick Trending Discovery Chips
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _trendingChips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final chip = _trendingChips[i];
                  final cleanQuery = chip.replaceFirst('🔥 ', '');
                  return GestureDetector(
                    onTap: () {
                      _ctrl.text = cleanQuery;
                      _search();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181C26),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: SpotifyColors.green.withValues(alpha: 0.35),
                          width: 0.9,
                        ),
                      ),
                      child: Text(
                        chip,
                        style: SpotifyFonts.bold(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: SpotifyColors.green, size: 13),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'SpotiFLAC Studio Lossless active • Auto YouTube fallback for regional & Malayalam tracks',
                      style: SpotifyFonts.regular(
                        color: SpotifyColors.lightGrey,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ── Results List ───────────────────────────────────────────────────────
      Expanded(
        child: searching
            ? Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: SpotifyColors.green,
                          strokeWidth: 2.8,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Searching Spotify & YouTube catalog...',
                        style: SpotifyFonts.bold(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : error != null
                ? _EmptyHint(
                    icon: Icons.music_off_rounded,
                    title: 'No results found',
                    body: error,
                  )
                : results.isEmpty
                    ? const _EmptyHint(
                        icon: Icons.queue_music_rounded,
                        title: 'Search Any Song',
                        body:
                            'Type an artist, song title, or keyword above.\nSongs will be transcoded to studio audio and added to your library.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        physics: const BouncingScrollPhysics(),
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final r = results[i];
                          final exactLocalMatch = widget.cachedTracks.any(
                              (s) => s.videoId.isNotEmpty && s.videoId == r.videoId);
                          final isIngesting =
                              provider.ingestingVideoIds.contains(r.videoId);
                          final progress =
                              provider.ingestionProgress[r.videoId] ?? 0.0;
                          final isDone =
                              provider.doneVideoIds.containsKey(r.videoId) ||
                                  exactLocalMatch;
                          final isDup = exactLocalMatch ||
                              (provider.doneVideoIds[r.videoId] == true);
                          final preChecked =
                              provider.libraryCheck.containsKey(r.videoId);

                          final isPlayingPreview = _previewVideoId == r.videoId;

                          return _YoutubeResultTile(
                            result: r,
                            isLoading: isIngesting ||
                                (!exactLocalMatch &&
                                    !preChecked &&
                                    provider.checkingLibrary),
                            progress: progress,
                            isDone: isDone,
                            isDup: isDup,
                            isPlayingPreview: isPlayingPreview,
                            isPreviewLoading: isPlayingPreview && _previewLoading,
                            onPlayPreview: () => _togglePreview(r),
                            onAdd: isDone || isIngesting ? null : () => _ingest(r),
                          )
                              .animate()
                              .fadeIn(duration: (200 + (i * 35).clamp(0, 300)).ms)
                              .slideY(begin: 0.08, end: 0);
                        },
                      ),
      ),
    ]);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _stopPreview();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dancing Equalizer Visualizer Bars for Previews
// ─────────────────────────────────────────────────────────────────────────────
class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars();

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(8 + 14 * (t * 0.95).abs()),
            const SizedBox(width: 2.5),
            _bar(18 - 12 * ((1 - t) * 0.85).abs()),
            const SizedBox(width: 2.5),
            _bar(6 + 16 * ((t * 1.3).clamp(0.0, 1.0))),
            const SizedBox(width: 2.5),
            _bar(17 - 10 * (t * 0.75).abs()),
          ],
        );
      },
    );
  }

  Widget _bar(double h) {
    return Container(
      width: 3.2,
      height: h.clamp(4.0, 22.0),
      decoration: BoxDecoration(
        color: SpotifyColors.green,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: SpotifyColors.green.withValues(alpha: 0.8),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _YoutubeResultTile with Multi-Stage Ingestion Pipeline Animation
// ─────────────────────────────────────────────────────────────────────────────
class _YoutubeResultTile extends StatelessWidget {
  final YouTubeSearchResult result;
  final bool isLoading;
  final double progress;
  final bool isDone;
  final bool isDup;
  final bool isPlayingPreview;
  final bool isPreviewLoading;
  final VoidCallback onPlayPreview;
  final VoidCallback? onAdd;

  const _YoutubeResultTile({
    required this.result,
    required this.isLoading,
    required this.progress,
    required this.isDone,
    required this.isDup,
    required this.isPlayingPreview,
    required this.isPreviewLoading,
    required this.onPlayPreview,
    required this.onAdd,
  });

  String _getStageTitle(double p) {
    if (p < 0.25) return 'Checking SpotiFLAC Catalog…';
    if (p < 0.55) return 'Lossless not found — Falling back to YouTube…';
    if (p < 0.85) return 'Downloading Audio & Transcoding (256k AAC)…';
    return 'Uploading Artwork & Cloud CDN…';
  }

  IconData _getStageIcon(double p) {
    if (p < 0.25) return Icons.search_rounded;
    if (p < 0.55) return Icons.swap_horiz_rounded;
    if (p < 0.85) return Icons.album_rounded;
    return Icons.cloud_upload_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final activeIngest = isLoading && progress > 0.0;
    final provider = context.watch<IngestionProvider>();
    final isFallback = provider.fallbackVideoIds.contains(result.videoId);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: activeIngest
            ? const Color(0xFF121915)
            : isPlayingPreview
                ? const Color(0xFF121B16)
                : const Color(0xFF13161F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activeIngest
              ? const Color(0xFF1DB954).withValues(alpha: 0.7)
              : isPlayingPreview
                  ? SpotifyColors.green.withValues(alpha: 0.6)
                  : const Color(0xFF222838),
          width: activeIngest || isPlayingPreview ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (activeIngest)
            BoxShadow(
              color: const Color(0xFF1DB954).withValues(alpha: 0.2),
              blurRadius: 16,
              spreadRadius: 1,
            )
          else if (isPlayingPreview)
            BoxShadow(
              color: SpotifyColors.green.withValues(alpha: 0.15),
              blurRadius: 12,
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                // Thumbnail with custom Play/Pause / Equalizer overlay
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: result.thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: result.thumbnailUrl,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _thumb(),
                              errorWidget: (_, __, ___) => _thumb(),
                            )
                          : _thumb(),
                    ),
                    // Darkening overlay
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: isPlayingPreview
                            ? Colors.black.withValues(alpha: 0.6)
                            : Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    // If preview is playing, show live dancing equalizer!
                    if (isPlayingPreview && !isPreviewLoading)
                      const _EqualizerBars()
                    else
                      // Play / Loading button overlay
                      GestureDetector(
                        onTap: onPlayPreview,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: isPlayingPreview
                                ? SpotifyColors.green
                                : Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: isPreviewLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : Icon(
                                  isPlayingPreview
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 18,
                                ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                // Song Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: SpotifyFonts.bold(
                          color: Colors.white,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isFallback
                                  ? Colors.amber.withValues(alpha: 0.15)
                                  : const Color(0xFF1E2433),
                              borderRadius: BorderRadius.circular(4),
                              border: isFallback
                                  ? Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.8)
                                  : null,
                            ),
                            child: Text(
                              isFallback ? 'YT FALLBACK' : 'LOSSLESS',
                              style: SpotifyFonts.bold(
                                color: isFallback ? Colors.amber : SpotifyColors.green,
                                fontSize: 8.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${result.artist.isNotEmpty ? result.artist : "Unknown Artist"} • ${result.formattedDuration}',
                              style: SpotifyFonts.regular(
                                color: SpotifyColors.lightGrey,
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Add action button
                _TrailingButton(
                  isLoading: isLoading && progress == 0.0,
                  isDone: isDone,
                  isDup: isDup,
                  onTap: onAdd,
                ),
              ],
            ),

            // ── Live Multi-Stage Animated Ingestion Progress ──────────────────
            if (activeIngest) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A212E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        return Stack(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: (constraints.maxWidth * progress.clamp(0.03, 1.0)),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF1DB954),
                                    Color(0xFF1ED760),
                                    Color(0xFF00E5FF),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1DB954).withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getStageIcon(progress),
                            size: 13,
                            color: const Color(0xFF00E5FF),
                          )
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.2, 1.2)),
                          const SizedBox(width: 6),
                          Text(
                            _getStageTitle(progress),
                            style: SpotifyFonts.bold(
                              color: const Color(0xFF00E5FF),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: SpotifyFonts.bold(
                          color: SpotifyColors.green,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumb() => Container(
        width: 56,
        height: 56,
        color: SpotifyColors.surface,
        child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 22),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  _TrailingButton with Scale Bounce Animation on Completion
// ─────────────────────────────────────────────────────────────────────────────
class _TrailingButton extends StatelessWidget {
  final bool isLoading, isDone, isDup;
  final VoidCallback? onTap;

  const _TrailingButton({
    required this.isLoading,
    required this.isDone,
    required this.isDup,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        width: 32,
        height: 32,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: SpotifyColors.green.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const CircularProgressIndicator(
          color: SpotifyColors.green,
          strokeWidth: 2.2,
        ),
      );
    }
    if (isDone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: (isDup ? const Color(0xFF1A78C2) : SpotifyColors.green)
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDup ? const Color(0xFF1A78C2) : SpotifyColors.green,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDup ? const Color(0xFF1A78C2) : SpotifyColors.green)
                  .withValues(alpha: 0.25),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_rounded,
              color: isDup ? const Color(0xFF1A78C2) : SpotifyColors.green,
              size: 13,
            ),
            const SizedBox(width: 4),
            Text(
              isDup ? 'In Library' : 'Added ✓',
              style: SpotifyFonts.bold(
                color: isDup ? const Color(0xFF1A78C2) : SpotifyColors.green,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      )
          .animate()
          .scale(
            begin: const Offset(0.7, 0.7),
            end: const Offset(1.0, 1.0),
            curve: Curves.elasticOut,
            duration: 450.ms,
          );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              SpotifyColors.green.withValues(alpha: 0.2),
              SpotifyColors.green.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: SpotifyColors.green, width: 1.3),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: SpotifyColors.green.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, color: SpotifyColors.green, size: 14),
            const SizedBox(width: 3),
            Text(
              'Add',
              style: SpotifyFonts.bold(
                color: SpotifyColors.green,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _PlaylistDropdown extends StatelessWidget {
  final List<_Playlist> playlists;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _PlaylistDropdown({
    required this.playlists,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveValue = (selected == null ||
            selected == '_create_new_' ||
            playlists.any((p) => p.id == selected))
        ? selected
        : null;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161A24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF262E40)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: effectiveValue,
          isExpanded: true,
          dropdownColor: const Color(0xFF131720),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: SpotifyColors.green,
            size: 22,
          ),
          selectedItemBuilder: (context) {
            return [
              _buildSelectedRow('Add to Library Only', Icons.library_music_rounded, isDefault: true),
              _buildSelectedRow('Create new playlist...', Icons.add_circle_outline_rounded, isCreate: true),
              ...playlists.map((p) => _buildSelectedRow(p.name, Icons.playlist_play_rounded)),
            ];
          },
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.library_music_rounded, color: Colors.white70, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Add to Library Only',
                    style: SpotifyFonts.regular(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            DropdownMenuItem<String?>(
              value: '_create_new_',
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: SpotifyColors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_rounded, color: SpotifyColors.green, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Create new playlist...',
                    style: SpotifyFonts.bold(color: SpotifyColors.green, fontSize: 13),
                  ),
                ],
              ),
            ),
            ...playlists.map(
              (p) => DropdownMenuItem<String?>(
                value: p.id,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2433),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.playlist_play_rounded, color: SpotifyColors.green, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.name,
                        style: SpotifyFonts.regular(color: Colors.white, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSelectedRow(String title, IconData icon, {bool isDefault = false, bool isCreate = false}) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isCreate
                  ? [const Color(0xFF1DB954), const Color(0xFF15883E)]
                  : isDefault
                      ? [const Color(0xFF2B3346), const Color(0xFF1F2433)]
                      : [const Color(0xFF1DB954), const Color(0xFF0F5A28)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DESTINATION PLAYLIST',
                style: SpotifyFonts.bold(
                  color: SpotifyColors.lightGrey,
                  fontSize: 9,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                title,
                style: SpotifyFonts.bold(
                  color: isCreate ? SpotifyColors.green : Colors.white,
                  fontSize: 13,
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
}

class _GreenButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const _GreenButton({
    this.icon,
    required this.label,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF1DB954), Color(0xFF15883E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: active ? null : const Color(0xFF1E2433),
          borderRadius: BorderRadius.circular(14),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: SpotifyColors.green.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2.2,
                ),
              )
            else if (icon != null) ...[
              Icon(icon, color: active ? Colors.black : Colors.white38, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: SpotifyFonts.bold(
                color: active ? Colors.black : Colors.white38,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreenOutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _GreenOutlineButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final color = active ? SpotifyColors.green : SpotifyColors.lightGrey.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF161A24) : const Color(0xFF10121A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? SpotifyColors.green.withValues(alpha: 0.6) : const Color(0xFF232B3E),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: SpotifyFonts.bold(
                color: color,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   body;
  const _EmptyHint({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SpotifyColors.lightGrey.withValues(alpha: 0.2), size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              style: SpotifyFonts.bold(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: SpotifyFonts.regular(
                color: SpotifyColors.lightGrey,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateSelectionDialog extends StatefulWidget {
  final List<CsvEntryState> duplicates;
  final int successCount;
  final int failCount;

  const _DuplicateSelectionDialog({
    required this.duplicates,
    required this.successCount,
    required this.failCount,
  });

  @override
  State<_DuplicateSelectionDialog> createState() => _DuplicateSelectionDialogState();
}

class _DuplicateSelectionDialogState extends State<_DuplicateSelectionDialog> {
  late final Set<CsvEntryState> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161616),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 22),
          const SizedBox(width: 10),
          Text(
            'Ingestion Complete',
            style: SpotifyFonts.regular(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Processed all tracks. The following duplicate songs were linked without downloading them again.',
              style: SpotifyFonts.regular(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 250),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF282828)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.duplicates.length,
                  separatorBuilder: (_, __) => const Divider(color: Color(0xFF282828), height: 1),
                  itemBuilder: (context, index) {
                    final item = widget.duplicates[index];
                    final isChecked = _selected.contains(item);
                    return CheckboxListTile(
                      value: isChecked,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selected.add(item);
                          } else {
                            _selected.remove(item);
                          }
                        });
                      },
                      title: Text(
                        item.entry.title,
                        style: SpotifyFonts.regular(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.entry.artist,
                        style: SpotifyFonts.regular(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      activeColor: SpotifyColors.green,
                      checkColor: Colors.black,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSummaryRow('New Songs Downloaded:', '${widget.successCount}', SpotifyColors.green),
            const SizedBox(height: 6),
            _buildSummaryRow('Duplicates Linked:', '${widget.duplicates.length}', Colors.amber),
            const SizedBox(height: 6),
            _buildSummaryRow('Failed Tracks:', '${widget.failCount}', SpotifyColors.error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF3E3E3E)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: Text(
            'Cancel',
            style: SpotifyFonts.regular(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          style: TextButton.styleFrom(
            backgroundColor: _selected.isEmpty ? const Color(0xFF282828) : SpotifyColors.green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(
            _selected.isEmpty ? 'Continue' : 'Download Selected',
            style: SpotifyFonts.regular(
              fontWeight: FontWeight.bold,
              color: _selected.isEmpty ? Colors.white38 : Colors.black,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String count, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: SpotifyFonts.regular(color: Colors.white70, fontSize: 12)),
        Text(count, style: SpotifyFonts.regular(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SummaryRow({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: SpotifyFonts.regular(color: Colors.white70, fontSize: 13),
        ),
        Text(
          '$count',
          style: SpotifyFonts.regular(color: color, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
