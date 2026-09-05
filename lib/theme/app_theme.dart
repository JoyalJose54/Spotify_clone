import 'package:flutter/material.dart';
import 'spotify_fonts.dart';

export 'spotify_fonts.dart';

class SpotifyColors {
  static const Color green = Color(0xFF1DB954);
  static const Color greenLight = Color(0xFF1ED760);
  static const Color black = Color(0xFF121212);
  static const Color darkBg = Color(0xFF191414);
  static const Color surface = Color(0xFF282828);
  static const Color surfaceLight = Color(0xFF3E3E3E);
  static const Color cardBg = Color(0xFF1E1E1E);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGrey = Color(0xFFB3B3B3);
  static const Color medGrey = Color(0xFF535353);
  static const Color darkGrey = Color(0xFF282828);
  static const Color error = Color(0xFFE91429);
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      // ── Global default font — every bare TextStyle inherits this ─────────
      // Individual overrides via SpotifyFonts.bold/title/display/mono() still
      // take priority; this is the fallback for raw TextStyle() calls.
      scaffoldBackgroundColor: SpotifyColors.black,

      colorScheme: const ColorScheme.dark(
        primary: SpotifyColors.green,
        secondary: SpotifyColors.green,
        surface: SpotifyColors.surface,
        error: SpotifyColors.error,
        onPrimary: SpotifyColors.black,
        onSecondary: SpotifyColors.black,
        onSurface: SpotifyColors.white,
        onError: SpotifyColors.white,
      ),
      textTheme: _buildTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: SpotifyFonts.title(
          color: SpotifyColors.white,
          fontSize: 24,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: SpotifyColors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SpotifyColors.green,
          foregroundColor: SpotifyColors.black,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: SpotifyFonts.bold(
            fontSize: 16,
            letterSpacing: 1.0,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SpotifyColors.white,
          side: const BorderSide(color: SpotifyColors.lightGrey, width: 1),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: SpotifyFonts.bold(
            fontSize: 16,
            letterSpacing: 1.0,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SpotifyColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: SpotifyColors.white, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: SpotifyColors.error),
        ),
        hintStyle: SpotifyFonts.regular(color: SpotifyColors.lightGrey),
        labelStyle: SpotifyFonts.regular(color: SpotifyColors.lightGrey),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF0A0A0A),
        selectedItemColor: SpotifyColors.white,
        unselectedItemColor: SpotifyColors.lightGrey,
        selectedLabelStyle: SpotifyFonts.bold(fontSize: 11),
        unselectedLabelStyle: SpotifyFonts.regular(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: SpotifyColors.white,
        inactiveTrackColor: SpotifyColors.medGrey,
        thumbColor: SpotifyColors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        overlayColor: Colors.white.withValues(alpha: 0.2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: SpotifyColors.surface,
        selectedColor: SpotifyColors.white,
        labelStyle: SpotifyFonts.regular(color: SpotifyColors.white, fontSize: 13),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    return TextTheme(
      // ── Display — Playlist Headers, Album Titles, Top Banners ─────────────
      //    Font: spotify_mix_ui_title_extrabold.otf  (punchy, maxed sharpness)
      displayLarge: SpotifyFonts.display(fontSize: 57, letterSpacing: -1),
      displayMedium: SpotifyFonts.display(fontSize: 45, letterSpacing: -0.5),
      displaySmall: SpotifyFonts.display(fontSize: 36),

      // ── Headlines — Screen / Section Titles ────────────────────────────────
      //    Font: spotify_mix_ui_title_bold.otf
      headlineLarge: SpotifyFonts.title(fontSize: 32),
      headlineMedium: SpotifyFonts.title(fontSize: 28),
      headlineSmall: SpotifyFonts.title(fontSize: 24),

      // ── Title slots — Song/Track Titles, Active Tabs, Highlighted Options ──
      //    Font: spotify_mix_ui_bold.otf
      //    "Heavy profile instantly prioritizes song title over metadata."
      titleLarge: SpotifyFonts.bold(fontSize: 22),
      titleMedium: SpotifyFonts.bold(fontSize: 16, letterSpacing: 0.1),
      titleSmall: SpotifyFonts.bold(fontSize: 14, letterSpacing: 0.1),

      // ── Body — Artist Names, Descriptions, Settings, Lyrics, Menus ─────────
      //    Font: spotify_mix_ui_regular.otf
      //    "Balanced, clean, for high-density reading."
      bodyLarge: SpotifyFonts.regular(fontSize: 16),
      bodyMedium: SpotifyFonts.regular(fontSize: 14, color: SpotifyColors.lightGrey),
      bodySmall: SpotifyFonts.regular(fontSize: 12, color: SpotifyColors.lightGrey),

      // ── Labels — Navigation menus, button text ─────────────────────────────
      //    Font: spotify_mix_ui_bold.otf (bold for active state prominence)
      labelLarge: SpotifyFonts.bold(fontSize: 14, letterSpacing: 1.2),
      labelMedium: SpotifyFonts.regular(fontSize: 12),
      labelSmall: SpotifyFonts.regular(fontSize: 11),
    );
  }
}

class SpotifyToast {
  static void show(
    BuildContext context,
    String message, {
    IconData icon = Icons.info_outline,
    Color iconColor = SpotifyColors.green,
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: SpotifyFonts.bold(
                  color: SpotifyColors.white,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2E2E2E),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF3E3E3E), width: 1),
        ),
        duration: duration,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      ),
    );
  }
}

class SpotifyDialog {
  static void show({
    required BuildContext context,
    required String title,
    required String message,
    IconData? icon,
    Color iconColor = SpotifyColors.green,
    String confirmLabel = 'OK',
    String? cancelLabel,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Center(
        child: Container(
          width: MediaQuery.of(ctx).size.width * 0.85,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF2E2E2E), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: SpotifyFonts.title(
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: SpotifyFonts.regular(
                    color: SpotifyColors.lightGrey,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (cancelLabel != null) ...[
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: Text(
                          cancelLabel,
                          style: SpotifyFonts.bold(
                            color: SpotifyColors.lightGrey,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onConfirm();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: iconColor == SpotifyColors.green ? SpotifyColors.green : iconColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      child: Text(
                        confirmLabel,
                        style: SpotifyFonts.title(
                          fontSize: 14,
                          color: Colors.black,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PaletteCache and PaletteColors for Performance Optimization
// ─────────────────────────────────────────────────────────────────────────────

class PaletteColors {
  final Color dominant;
  final Color vibrant;
  final Color muted;
  final Color bgColor;
  final Color bgColorDark;
  final Color bgColorBottom;

  const PaletteColors({
    required this.dominant,
    required this.vibrant,
    required this.muted,
    required this.bgColor,
    required this.bgColorDark,
    required this.bgColorBottom,
  });
}

class PaletteCache {
  static final Map<String, PaletteColors> _cache = {};

  static PaletteColors? get(String url) => _cache[url];

  static void set(String url, PaletteColors colors) {
    _cache[url] = colors;
  }

  static bool contains(String url) => _cache.containsKey(url);
}
