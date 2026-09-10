import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/app_provider.dart';
import 'providers/ingestion_provider.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/login_screen.dart';
import 'screens/guest_setup_screen.dart';
import 'screens/main_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    // Establish the system audio notification bridge (Android & iOS only)
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.yourdomain.spotify_clone.channel.audio',
      androidNotificationChannelName: 'Spotify Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'drawable/ic_notification',
    );
  }

  // 1. Firebase first — other plugins may depend on it
  const desktopFirebaseOptions = FirebaseOptions(
    apiKey: "AIzaSyDmLc3mtdMRKpb5V6KvBMLqE2yGZEyHPm4",
    appId: "1:159958033090:web:spotify-clone-desktop",
    messagingSenderId: "159958033090",
    projectId: "myspotifyclone-5000e",
    storageBucket: "myspotifyclone-5000e.firebasestorage.app",
  );

  if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await Firebase.initializeApp(options: desktopFirebaseOptions);
  } else {
    await Firebase.initializeApp();
  }



  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => IngestionProvider()),
      ],
      child: const SpotifyCloneApp(),
    ),
  );
}

class SpotifyCloneApp extends StatelessWidget {
  const SpotifyCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppNavigator(),
    );
  }
}

enum _AppState { splash, login, auth, guestSetup, main }

class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});
  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  _AppState _state = _AppState.splash;
  bool _isRegistered = false;

  @override
  void initState() {
    super.initState();
    _preFetchPrefs();
  }

  Future<void> _preFetchPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isRegistered = prefs.getBool('is_registered') ?? false;
      });
    }
  }

  Future<void> _go(_AppState next) async {
    if (mounted) setState(() => _state = next);
  }

  void _showKickSnackbar(String msg) {
    if (msg.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE22134),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    if (_state == _AppState.guestSetup) {
      if (auth.userName.isNotEmpty && auth.isLoggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _go(_AppState.main);
        });
      }
    } else if (_state == _AppState.main && !auth.isLoggedIn) {
      // User was kicked or logged out — return immediately to Login
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            context.read<PlayerProvider>().audioPlayer?.pause();
          } catch (_) {}
          _go(_AppState.login);
          _showKickSnackbar(auth.kickMessage);
          auth.clearKickMessage();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _buildScreen(),
    );
  }

  Widget _buildScreen() {
    final auth = context.watch<AuthProvider>();

    // 1. Splash Screen
    if (_state == _AppState.splash) {
      return SplashScreen(
        key: const ValueKey('splash'),
        onComplete: () {
          if (auth.isLoggedIn) {
            _go(_AppState.main);
          } else {
            _go(_AppState.login);
            _showKickSnackbar(auth.kickMessage);
            auth.clearKickMessage();
          }
        },
      );
    }

    // 2. Strict Security Guard: If not logged in, NEVER render MainScreen
    if (!auth.isLoggedIn) {
      if (_state == _AppState.auth) {
        return AuthFlowScreen(
          onAuthComplete: () => _go(_AppState.guestSetup),
        );
      }
      return LoginScreen(
        key: const ValueKey('login'),
        onLoginComplete: () {
          context.read<AuthProvider>().loginAsGuest();
          _go(_AppState.guestSetup);
        },
        onSignUp: () => _go(_AppState.auth),
      );
    }

    // 3. User is authenticated
    switch (_state) {
      case _AppState.auth:
        return AuthFlowScreen(
          onAuthComplete: () => _go(_AppState.guestSetup),
        );
      case _AppState.login:
        return LoginScreen(
          key: const ValueKey('login'),
          onLoginComplete: () {
            context.read<AuthProvider>().loginAsGuest();
            _go(_AppState.guestSetup);
          },
          onSignUp: () => _go(_AppState.auth),
        );
      case _AppState.guestSetup:
        return GuestSetupScreen(
          onComplete: (name) {
            context.read<AuthProvider>().setUserName(name);
            _go(_AppState.main);
          },
        );
      case _AppState.main:
      default:
        return const MainScreen(key: ValueKey('main'));
    }
  }
}
