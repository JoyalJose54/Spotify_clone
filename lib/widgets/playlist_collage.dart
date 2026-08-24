import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';


class PlaylistCollage extends StatelessWidget {
  final Playlist playlist;
  final List<Song> currentTracks;
  final double size;

  const PlaylistCollage({
    super.key,
    required this.playlist,
    required this.currentTracks,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Get all songs that actually have an image URL
    final songsWithImages = currentTracks
        .where((s) => s.imageUrl.isNotEmpty)
        .toList();

    List<String> selectedUrls = [];

    if (playlist.id == 'all_songs') {
      // Rule: Start from 4th image (index 3), take up to 4
      if (songsWithImages.length >= 4) {
        selectedUrls = songsWithImages
            .skip(3)
            .take(4)
            .map((t) => t.imageUrl)
            .toList();
      }
      
      // If we don't have enough images after skipping, just take whatever we have
      if (selectedUrls.length < 4 && songsWithImages.isNotEmpty) {
        selectedUrls = songsWithImages.take(4).map((t) => t.imageUrl).toList();
      }
    } else {
      // Standard: First 4 images
      selectedUrls = songsWithImages.take(4).map((t) => t.imageUrl).toList();
    }

    // 2. Ensure we have exactly 4 items for the grid by repeating if needed
    final List<String> finalGridUrls = [];
    if (selectedUrls.isNotEmpty) {
      for (int i = 0; i < 4; i++) {
        finalGridUrls.add(selectedUrls[i % selectedUrls.length]);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: size,
        height: size,
        color: SpotifyColors.surface,
        child: finalGridUrls.isEmpty 
          ? _buildPlaceholder() 
          : _buildStaticGrid(finalGridUrls),
      ),
    );
  }

  Widget _buildStaticGrid(List<String> urls) {
    // Explicitly define a 2x2 grid to avoid any dynamic spacing issues
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildImage(urls[0])),
              Expanded(child: _buildImage(urls[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildImage(urls[2])),
              Expanded(child: _buildImage(urls[3])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(Icons.queue_music, color: SpotifyColors.lightGrey, size: size * 0.4),
    );
  }

  Widget _buildImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorWidget: (_, __, ___) => Container(
        color: SpotifyColors.surface,
        child: const Icon(Icons.music_note, color: SpotifyColors.lightGrey),
      ),
    );
  }
}
