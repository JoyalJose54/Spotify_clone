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

  if (!kIsWeb) {
    // Establish the system audio notification bridge
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.yourdomain.spotify_clone.channel.audio',
      androidNotificationChannelName: 'Spotify Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'drawable/ic_notification',
    );
  }

  // 1. Firebase first — other plugins may depend on it
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: "YOUR_FIREBASE_WEB_API_KEY"),
        appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: "YOUR_FIREBASE_WEB_APP_ID"),
        messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: "YOUR_MESSAGING_SENDER_ID"),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: "YOUR_FIREBASE_PROJECT_ID"),
        storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: "YOUR_STORAGE_BUCKET"),
      ),
    );
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If we're in the guestSetup state but auth is already complete
    // (e.g. the user was already registered), advance to main immediately.
    // Using didChangeDependencies is the correct hook for reacting to
    // Provider changes — never call setState or schedule navigation from build().
    if (_state == _AppState.guestSetup) {
      final auth = context.read<AuthProvider>();
      if (auth.userName.isNotEmpty && auth.isLoggedIn) {
        // Schedule after current frame to avoid setState-during-build assertions.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _go(_AppState.main);
        });
      }
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
        // Build stays pure — the auto-advance is handled in didChangeDependencies.
        return GuestSetupScreen(
          onComplete: (name) {
            context.read<AuthProvider>().setUserName(name);
            _go(_AppState.main);
          },
        );
      case _AppState.splash:
        return SplashScreen(
          key: const ValueKey('splash'),
          onComplete: () {
            _go(_isRegistered ? _AppState.main : _AppState.login);
          },
        );
      case _AppState.main:
        return const MainScreen(key: ValueKey('main'));
    }
  }
}
