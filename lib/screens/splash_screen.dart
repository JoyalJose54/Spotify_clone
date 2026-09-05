import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _isLottieLoaded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.black,
      body: Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!_isLottieLoaded)
                Image.asset(
                  'assets/images/logo.webp',
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                ),
              Lottie.asset(
                'assets/animations/splash.json',
                controller: _ctrl,
                width: 200,
                height: 200,
                onLoaded: (composition) {
                  _ctrl.duration = composition.duration; // original speed
                  _ctrl.forward().then((_) {
                    if (mounted) widget.onComplete();
                  });
                  if (mounted) {
                    setState(() {
                      _isLottieLoaded = true;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
