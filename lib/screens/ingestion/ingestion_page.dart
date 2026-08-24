import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart' as ap;

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

  Future<void> _showBackendSettingsDialog(BuildContext context) async {
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
                hintText: 'http://192.168.1.100:8080',
                hintStyle: SpotifyFonts.regular(color: Colors.grey, fontSize: 14),
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
                await IngestionService.updateBackendUrl(newUrl);
                if (context.mounted) {
                  SpotifyToast.show(context, 'Backend URL updated!', icon: Icons.save);
                }
                Navigator.pop(dCtx);
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Smart Ingestion',
          style: SpotifyFonts.regular( 
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: GestureDetector(
                onTap: () => _showBackendSettingsDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isBackendOnline == null
                        ? Colors.orange.withValues(alpha: 0.1)
                        : (_isBackendOnline!
                            ? SpotifyColors.green.withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isBackendOnline == null
                          ? Colors.orange.withValues(alpha: 0.3)
                          : (_isBackendOnline!
                              ? SpotifyColors.green.withValues(alpha: 0.3)
                              : Colors.red.withValues(alpha: 0.3)),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isBackendOnline == null
                              ? Colors.orange
                              : (_isBackendOnline! ? SpotifyColors.green : Colors.red),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isBackendOnline == null
                            ? 'Checking'
                            : (_isBackendOnline! ? 'Online' : 'Offline'),
                        style: SpotifyFonts.regular(
                          color: _isBackendOnline == null
                              ? Colors.orange
                              : (_isBackendOnline! ? SpotifyColors.green : Colors.red),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF262626)),
            ),
            child: TabBar(
              controller: _tab,
              indicator: BoxDecoration(
                color: SpotifyColors.green,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: SpotifyColors.green.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.white70,
              labelStyle: SpotifyFonts.regular( fontSize: 12, fontWeight: FontWeight.bold),
              unselectedLabelStyle: SpotifyFonts.regular( fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload_file, size: 16),
                      SizedBox(width: 8),
                      Text('CSV Upload'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 16),
                      SizedBox(width: 8),
                      Text('YouTube Search'),
                    ],
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
              Color(0xFF0F0F0F),
              Color(0xFF070707),
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
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))
          ]
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Playlist picker
          widget.loadingPlaylists
              ? const SizedBox(height: 48,
                  child: Center(child: CircularProgressIndicator(
                      color: SpotifyColors.green, strokeWidth: 2)))
              : _PlaylistDropdown(
                  playlists: provider.localPlaylists,
                  selected:  widget.selectedPlaylist,
                  onChanged: widget.onPlaylistChanged,
                ),
          const SizedBox(height: 14),
          // Row: Pick file + Start
          Row(children: [
            Expanded(
              child: _GreenOutlineButton(
                icon:  Icons.folder_open_outlined,
                label: 'Pick CSV',
                onTap: provider.csvProcessing ? null : _pickCsv,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GreenButton(
                icon:    Icons.rocket_launch_outlined,
                label:   'Ingest All',
                loading: provider.csvProcessing,
                onTap:   (!provider.csvProcessing && provider.csvEntries.isNotEmpty) ? _startProcessing : null,
              ),
            ),
          ]),
        ]),
      ),

      // ── Progress Dashboard ─────────────────────────────────────────────────
      // Plain Container intentionally — AnimatedContainer caused
      // !semantics.parentDataDirty assertions when scrolling during ingestion.
      if (total > 0) ...[
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF282828)),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bulk Ingestion Progress',
                    style: SpotifyFonts.regular( 
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: SpotifyFonts.regular( 
                      color: SpotifyColors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFF2A2A2A),
                  color: SpotifyColors.green,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              // Stats badges
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatBadge(
                    label: 'Success',
                    count: provider.csvSuccessCount,
                    color: SpotifyColors.green,
                    icon: Icons.check_circle_outline,
                  ),
                  _StatBadge(
                    label: 'Duplicate',
                    count: provider.csvDupCount,
                    color: const Color(0xFF1A78C2),
                    icon: Icons.copy_outlined,
                  ),
                  _StatBadge(
                    label: 'Failed',
                    count: provider.csvFailCount,
                    color: SpotifyColors.error,
                    icon: Icons.error_outline,
                  ),
                ],
              ),
              if (provider.csvProcessing && provider.csvActiveTrack.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFF2E2E2E), height: 16),
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
                        style: SpotifyFonts.regular( 
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
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
            ? const _EmptyHint(
                icon:  Icons.upload_file,
                title: 'Import CSV File',
                body:  'Upload a .csv file containing song metadata.\nExpected headers: "Title, Artist" (one song per row).',
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            '$label: $count',
            style: SpotifyFonts.regular( 
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
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
      EntryStatus.done      => (SpotifyColors.green,               Icons.check_circle_outline),
      EntryStatus.duplicate => (const Color(0xFF1A78C2),           Icons.copy_outlined),
      EntryStatus.failed    => (SpotifyColors.error,               Icons.error_outline),
      EntryStatus.processing => (Colors.amber,                     Icons.hourglass_top_rounded),
      EntryStatus.pending   => (SpotifyColors.lightGrey,           Icons.radio_button_unchecked),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: row.status == EntryStatus.processing
              ? Colors.amber.withValues(alpha: 0.3)
              : const Color(0xFF222222),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.08),
            shape:        BoxShape.circle,
            border:       Border.all(color: color.withValues(alpha: 0.2), width: 1.2),
          ),
          child: row.status == EntryStatus.processing
              ? const Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))
              : Icon(icon, color: color, size: 16),
        ),
        title: Text(row.entry.title,
            style: SpotifyFonts.regular( color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.bold),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(row.entry.artist,
            style: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 11),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: row.message.isNotEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  row.message,
                  style: SpotifyFonts.regular( color: color, fontSize: 10, fontWeight: FontWeight.bold),
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
    await _stopPreview();

    final provider = context.read<IngestionProvider>();
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

    if (_previewVideoId == r.videoId) {
      await _stopPreview();
    }

    final provider = context.read<IngestionProvider>();
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
      print('PREVIEW ERROR: $e');
      if (mounted) {
        setState(() {
          _previewVideoId = null;
          _previewLoading = false;
        });
        SpotifyToast.show(context, 'Preview unavailable', icon: Icons.error_outline, iconColor: Colors.redAccent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IngestionProvider>();
    final results = provider.searchResults;
    final searching = provider.isSearching;
    final error = provider.searchError;

    return Column(children: [
      // ── Controls ───────────────────────────────────────────────────────────
      Container(
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))
          ]
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(children: [
          // Playlist picker
          widget.loadingPlaylists
              ? const SizedBox(height: 48,
                  child: Center(child: CircularProgressIndicator(
                      color: SpotifyColors.green, strokeWidth: 2)))
              : _PlaylistDropdown(
                  playlists: provider.localPlaylists,
                  selected:  widget.selectedPlaylist,
                  onChanged: widget.onPlaylistChanged,
                ),
          const SizedBox(height: 14),
          // Search bar
          Row(children: [
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color:        const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: const Color(0xFF2E2E2E)),
                ),
                child: Row(children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.search, color: SpotifyColors.lightGrey, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style:       SpotifyFonts.regular( color: Colors.white, fontSize: 13),
                      textInputAction: TextInputAction.search,
                      onSubmitted:     (_) => _search(),
                      decoration: InputDecoration(
                        hintText:  'Search Artist or Song Title…',
                        hintStyle: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 13),
                        border:    InputBorder.none,
                        isDense:   true,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            _GreenButton(
              icon: Icons.search, label: 'Search',
              loading: searching, onTap: searching ? null : _search,
            ),
          ]),
        ]),
      ),

      // ── Results ────────────────────────────────────────────────────────────
      Expanded(
        child: error != null
            ? _EmptyHint(icon: Icons.search_off, title: 'No results',
                         body: error)
            : results.isEmpty && !searching
                ? const _EmptyHint(icon: Icons.youtube_searched_for,
                             title: 'Search YouTube',
                             body: 'Search the YouTube database directly to import new songs.\nThey will download, process, and automatically match metadata.')
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final r            = results[i];
                      final exactLocalMatch = widget.cachedTracks.any((s) => s.videoId.isNotEmpty && s.videoId == r.videoId);
                      final isIngesting  = provider.ingestingVideoIds.contains(r.videoId);
                      final progress     = provider.ingestionProgress[r.videoId] ?? 0.0;
                      final isDone       = provider.doneVideoIds.containsKey(r.videoId) || exactLocalMatch;
                      final isDup        = exactLocalMatch || (provider.doneVideoIds[r.videoId] == true);
                      final preChecked   = provider.libraryCheck.containsKey(r.videoId);
                      
                      final isPlayingPreview = _previewVideoId == r.videoId;

                      return _YoutubeResultTile(
                        result:           r,
                        isLoading:        isIngesting || (!exactLocalMatch && !preChecked && provider.checkingLibrary),
                        progress:         progress,
                        isDone:           isDone,
                        isDup:            isDup,
                        isPlayingPreview: isPlayingPreview,
                        isPreviewLoading: isPlayingPreview && _previewLoading,
                        onPlayPreview:    () => _togglePreview(r),
                        onAdd:            isDone || isIngesting
                                               ? null
                                               : () => _ingest(r),
                      );
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
class _YoutubeResultTile extends StatelessWidget {
  final YouTubeSearchResult result;
  final bool                isLoading;
  final double              progress;
  final bool                isDone;
  final bool                isDup;
  final bool                isPlayingPreview;
  final bool                isPreviewLoading;
  final VoidCallback        onPlayPreview;
  final VoidCallback?       onAdd;

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

  String _getProgressLabel(double p) {
    if (p < 0.3) return 'Fetching stream URL... ${(p * 100).toInt()}%';
    if (p < 0.65) return 'Converting to high-quality audio... ${(p * 100).toInt()}%';
    if (p < 0.9) return 'Uploading to Cloud storage... ${(p * 100).toInt()}%';
    return 'Finalizing metadata index... ${(p * 100).toInt()}%';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLoading
              ? Colors.amber.withValues(alpha: 0.3)
              : isPlayingPreview
                  ? SpotifyColors.green.withValues(alpha: 0.3)
                  : const Color(0xFF222222),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                // Thumbnail with custom Play/Pause overlay
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: result.thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl:   result.thumbnailUrl,
                              width: 52, height: 52, fit: BoxFit.cover,
                              placeholder: (_, __) => _thumb(),
                              errorWidget: (_, __, ___) => _thumb())
                          : _thumb(),
                    ),
                    // Darkening overlay
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    // Play icon overlay
                    GestureDetector(
                      onTap: onPlayPreview,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isPlayingPreview ? SpotifyColors.green : Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: isPreviewLoading
                            ? const Padding(
                                padding: EdgeInsets.all(7),
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2),
                              )
                            : Icon(
                                isPlayingPreview ? Icons.stop : Icons.play_arrow,
                                color: Colors.black,
                                size: 16,
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
                      Text(result.title,
                          style: SpotifyFonts.regular( color: Colors.white, fontSize: 13,
                              fontWeight: FontWeight.bold),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                          '${result.artist.isNotEmpty ? result.artist : "Unknown Artist"}'
                          '  ·  ${result.formattedDuration}',
                          style: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Add action button
                _TrailingButton(
                    isLoading: isLoading && progress == 0.0, isDone: isDone, isDup: isDup, onTap: onAdd),
              ],
            ),

            // Simulated Ingestion Progress Bar
            if (isLoading && progress > 0.0) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFF222222),
                      color: Colors.amber,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _getProgressLabel(progress),
                          style: SpotifyFonts.regular( 
                            color: Colors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: SpotifyFonts.regular( 
                          color: Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
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
        width: 52, height: 52, color: SpotifyColors.surface,
        child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey, size: 20));
}

// ─────────────────────────────────────────────────────────────────────────────
class _TrailingButton extends StatelessWidget {
  final bool isLoading, isDone, isDup;
  final VoidCallback? onTap;
  const _TrailingButton(
      {required this.isLoading, required this.isDone,
       required this.isDup,     required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(width: 28, height: 28,
          child: CircularProgressIndicator(color: SpotifyColors.green, strokeWidth: 2));
    }
    if (isDone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:        (isDup ? const Color(0xFF1A78C2) : SpotifyColors.green)
                            .withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(
              color: isDup ? const Color(0xFF1A78C2) : SpotifyColors.green,
              width: 1),
        ),
        child: Text(isDup ? 'In Library' : 'Added ✓',
            style: SpotifyFonts.regular( 
                color: isDup ? const Color(0xFF1A78C2) : SpotifyColors.green,
                fontSize: 10, fontWeight: FontWeight.bold)),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border:       Border.all(color: SpotifyColors.green, width: 1.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Add',
            style: SpotifyFonts.regular( 
                color: SpotifyColors.green, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _PlaylistDropdown extends StatelessWidget {
  final List<_Playlist> playlists;
  final String?             selected;
  final ValueChanged<String?> onChanged;

  const _PlaylistDropdown(
      {required this.playlists, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color:        const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value:         selected,
          isExpanded:    true,
          dropdownColor: const Color(0xFF161616),
          style:         SpotifyFonts.regular( color: Colors.white, fontSize: 13),
          hint: Text('Select Playlist Target (Optional)',
              style: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 13)),
          icon: const Icon(Icons.keyboard_arrow_down, color: SpotifyColors.lightGrey),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('Add to Library Only',
                  style: SpotifyFonts.regular( color: SpotifyColors.lightGrey, fontSize: 13))),
            DropdownMenuItem<String?>(
              value: '_create_new_',
              child: Row(
                children: [
                  const Icon(Icons.add, color: SpotifyColors.green, size: 18),
                  const SizedBox(width: 8),
                  Text('Create new playlist...',
                      style: SpotifyFonts.bold(color: SpotifyColors.green, fontSize: 13)),
                ],
              ),
            ),
            ...playlists.map((p) => DropdownMenuItem<String?>(
              value: p.id,
              child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _GreenButton extends StatelessWidget {
  final IconData  icon;
  final String    label;
  final bool      loading;
  final VoidCallback? onTap;

  const _GreenButton(
      {required this.icon, required this.label,
       this.loading = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color:        onTap != null
              ? SpotifyColors.green : SpotifyColors.green.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: SpotifyColors.green.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading)
            const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.2))
          else
            Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: SpotifyFonts.regular( 
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _GreenOutlineButton extends StatelessWidget {
  final IconData  icon;
  final String    label;
  final VoidCallback? onTap;

  const _GreenOutlineButton(
      {required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final color = active ? SpotifyColors.green : SpotifyColors.lightGrey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(
              color: active ? SpotifyColors.green : const Color(0xFF2E2E2E), width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: SpotifyFonts.regular( 
                  color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ]),
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
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: SpotifyColors.lightGrey.withValues(alpha: 0.2), size: 64),
          const SizedBox(height: 20),
          Text(title,
              style: SpotifyFonts.regular( color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(body,
              textAlign: TextAlign.center,
              style: SpotifyFonts.regular( 
                  color: SpotifyColors.lightGrey, fontSize: 12, height: 1.5)),
        ]),
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
