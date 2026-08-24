import 'package:flutter/material.dart';

// ────────────────────────────────────────────────────────────────────────────
//  Spotify Font System
//
//  Font file → family name → usage rule
//  ─────────────────────────────────────────────────────────────────────────
//  spotify_mix_ui_title_extrabold.otf  → 'SpotifyMixUITitleExtraBold'
//    USE FOR: Playlist Headers, Album Title Headers, Main Category banners,
//             Top Banner Text. Max sharpness, punchy weight.
//
//  spotify_mix_ui_title_bold.otf       → 'SpotifyMixUITitleBold'
//    USE FOR: Section headings, Screen titles, large UI anchors.
//
//  spotify_mix_ui_bold.otf             → 'SpotifyMixUIBold'
//    USE FOR: Song / Track Titles (player + lists), active nav tab labels,
//             highlighted interface options, buttons.
//
//  spotify_mix_ui_regular.otf          → 'SpotifyMixUI' (weight 400)
//    USE FOR: Artist Names, Album sub-labels, Body text, Descriptions,
//             Lyrics, Timestamps, Navigation menus.
//
//  spotify_mix_mono_regular.otf        → 'SpotifyMixMono'
//    USE FOR: Counters, timestamps with fixed-width alignment, debug screens,
//             telemetry meters, code references.
// ────────────────────────────────────────────────────────────────────────────

class SpotifyFonts {
  SpotifyFonts._();

  // ── Family name constants (match pubspec.yaml) ────────────────────────────
  static const String _regular  = 'SpotifyMixUI';           // regular.otf
  static const String _bold     = 'SpotifyMixUIBold';       // bold.otf
  static const String _title    = 'SpotifyMixUITitleBold';  // title_bold.otf
  static const String _display  = 'SpotifyMixUITitleExtraBold'; // title_extrabold.otf

  // ── 1. DISPLAY — Playlist Headers, Album Titles, Main Category Banners ────
  //    Font: spotify_mix_ui_title_extrabold.otf
  //    "Spotify intentionally uses maxed-out sharpness and punchy extra-bold
  //     weights on its largest text headers to anchor its primary sections."
  static TextStyle display({
    double fontSize = 32,
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.w800,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _display,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
      );

  // ── 2. TITLE — Section Headings, Screen Titles, Large UI Anchors ──────────
  //    Font: spotify_mix_ui_title_bold.otf
  static TextStyle title({
    double fontSize = 24,
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.w700,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _title,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
      );

  // ── 3. BOLD — Song/Track Titles, Active Nav Tabs, Highlighted Options ─────
  //    Font: spotify_mix_ui_bold.otf
  //    "This heavy profile instantly prioritizes the song title over the rest
  //     of the metadata."
  static TextStyle bold({
    double fontSize = 14,
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.w700,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _bold,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
      );

  // ── 4. REGULAR — Artist Names, Body Text, Descriptions, Lyrics ───────────
  //    Font: spotify_mix_ui_regular.otf
  //    "Balanced, clean design for high-density reading and compact scaling."
  static TextStyle regular({
    double fontSize = 14,
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      TextStyle(
        fontFamily: _regular,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );

  // ── 5. MONO — Counters, Timestamps, Debug Screens, Telemetry ─────────────
  //    Font: spotify_mix_mono_regular.otf
  //    Fixed-width for exact column alignment.
  static TextStyle mono({
    double fontSize = 13,
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: 'SpotifyMixMono',
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
      );
}

// ────────────────────────────────────────────────────────────────────────────
//  Spoticon — Spotify native icon glyph font
// ────────────────────────────────────────────────────────────────────────────
class SpoticonIcons {
  SpoticonIcons._();

  static const IconData play          = IconData(0xF1C8, fontFamily: 'Spoticon');
  static const IconData pause         = IconData(0xF1D3, fontFamily: 'Spoticon');
  static const IconData repeat        = IconData(0xF1D4, fontFamily: 'Spoticon');
  static const IconData repeatOnce    = IconData(0xF201, fontFamily: 'Spoticon');
  static const IconData shuffle       = IconData(0xF1D5, fontFamily: 'Spoticon');
  static const IconData skipBack      = IconData(0xF1D6, fontFamily: 'Spoticon');
  static const IconData skipForward   = IconData(0xF1D7, fontFamily: 'Spoticon');
  static const IconData volume        = IconData(0xF1DB, fontFamily: 'Spoticon');
  static const IconData volumeOff     = IconData(0xF3BB, fontFamily: 'Spoticon');
  static const IconData heart         = IconData(0xF3DB, fontFamily: 'Spoticon');
  static const IconData heartActive   = IconData(0xF3DC, fontFamily: 'Spoticon');
  static const IconData search        = IconData(0xF3A4, fontFamily: 'Spoticon');
  static const IconData searchActive  = IconData(0xF372, fontFamily: 'Spoticon');
  static const IconData home          = IconData(0xF3B5, fontFamily: 'Spoticon');
  static const IconData homeActive    = IconData(0xF36E, fontFamily: 'Spoticon');
  static const IconData library       = IconData(0xF3A2, fontFamily: 'Spoticon');
  static const IconData nowPlaying    = IconData(0xF346, fontFamily: 'Spoticon');
  static const IconData more          = IconData(0xF1CC, fontFamily: 'Spoticon');
  static const IconData moreAndroid   = IconData(0xF21A, fontFamily: 'Spoticon');
  static const IconData addToPlaylist = IconData(0xF3AC, fontFamily: 'Spoticon');
  static const IconData queue         = IconData(0xF346, fontFamily: 'Spoticon');
  static const IconData shuffleSmart  = IconData(0xF688, fontFamily: 'Spoticon');
  static const IconData airplay       = IconData(0xF5DE, fontFamily: 'Spoticon');
  static const IconData sleepTimer    = IconData(0xF5E8, fontFamily: 'Spoticon');
}
