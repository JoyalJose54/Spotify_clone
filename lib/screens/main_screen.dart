import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'search/search_screen.dart';
import '../widgets/mini_player.dart';
import 'package:flutter/cupertino.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  int _searchKeyCounter = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        setState(() {
          // If we leave the search screen when resetting, increment search key
          if (_currentIndex == 1) {
            _searchKeyCounter++;
          }
          _currentIndex = 0;
        });
      },
      child: Scaffold(
        backgroundColor: SpotifyColors.black,
        body: IndexedStack(
          index: _currentIndex,
          children: List.generate(3, (i) {
            Widget child;
            if (i == 0) {
              child = const HomeScreen();
            } else if (i == 1) {
              child = SearchScreen(key: ValueKey(_searchKeyCounter));
            } else {
              child = const LibraryScreen();
            }
            // TickerMode pauses ALL AnimationControllers in the subtree of
            // inactive tabs — no changes needed in individual widgets.
            // When the tab becomes active again, tickers resume from where
            // they stopped, giving seamless animation continuity.
            return TickerMode(
              enabled: i == _currentIndex,
              child: child,
            );
          }),
        ),

        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<PlayerProvider>(
              builder: (context, player, _) {
                if (!player.hasCurrentSong) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: MiniPlayer(player: player),
                );
              },
            ),
            _BottomNav(
              currentIndex: _currentIndex,
              onTap: (i) {
                setState(() {
                  if (i == 1) {
                    // Reset if tapping Search while already on Search
                    if (_currentIndex == 1) {
                      _searchKeyCounter++;
                    }
                  } else if (_currentIndex == 1) {
                    // Reset when leaving Search tab to another tab
                    _searchKeyCounter++;
                  }
                  _currentIndex = i;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Premium Custom Bottom Navigation Bar matching spotify_navigation.dart
// ─────────────────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  static const _navItems = [
    _NavItem(
      label: 'Home',
      inactiveIcon: Icons.home_outlined,
      activeIcon: Icons.home,
    ),
    _NavItem(
      label: 'Search',
      inactiveIcon: CupertinoIcons.search,
      activeIcon: CupertinoIcons.search,
    ),
    _NavItem(
      label: 'Your Library',
      inactiveIcon: Icons.library_music_outlined,
      activeIcon: Icons.library_music,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black, // Pure #000000 background
      padding: EdgeInsets.only(
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_navItems.length, (i) {
          return _SpotifyNavItem(
            item: _navItems[i],
            isActive: i == currentIndex,
            onTap: () {
              onTap(i);
            },
          );
        }),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.inactiveIcon,
    required this.activeIcon,
  });
  final String label;
  final IconData inactiveIcon;
  final IconData activeIcon;
}

class _SpotifyNavItem extends StatelessWidget {
  const _SpotifyNavItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(
                isActive ? item.activeIcon : item.inactiveIcon,
                key: ValueKey(isActive),
                color: isActive
                    ? SpotifyColors.white
                    : SpotifyColors.lightGrey,
                size: isActive ? 26 : 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: isActive
                ? SpotifyFonts.bold(
                    color: SpotifyColors.white,
                    fontSize: 10,
                    letterSpacing: 0.2,
                  )
                : SpotifyFonts.regular(
                    color: SpotifyColors.lightGrey,
                    fontSize: 10,
                    letterSpacing: 0.2,
                  ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}



