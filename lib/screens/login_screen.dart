import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/spotify_fonts.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginComplete;
  final VoidCallback onSignUp;
  const LoginScreen({
    super.key,
    required this.onLoginComplete,
    required this.onSignUp,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

const _kGreen = Color(0xFF1DB954);
const _kBg = Color(0xFF121212);

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  late final AnimationController _logoCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _breathCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 3000),
  )..repeat(reverse: true);
  late final AnimationController _rippleCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 2600),
  )..repeat();
  late final AnimationController _arcCtrl = AnimationController(
    vsync: this, duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _logoCtrl.forward();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _breathCtrl.dispose();
    _rippleCtrl.dispose();
    _arcCtrl.dispose();
    super.dispose();
  }

  Animation<double> _stag(double start, double end) => 
    CurvedAnimation(parent: _logoCtrl, curve: Interval(start, end, curve: Curves.easeOut));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Stack(
            children: [
              Align(
                alignment: const Alignment(0, -0.2), // Centers the text block perfectly
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        _RippleRing(controller: _rippleCtrl, delay: 0.0),
                        _RippleRing(controller: _rippleCtrl, delay: 0.33),
                        _RippleRing(controller: _rippleCtrl, delay: 0.66),
                        RotationTransition(
                          turns: _arcCtrl,
                          child: CustomPaint(size: const Size(110, 110), painter: _DashedArcPainter()),
                        ),
                        ScaleTransition(
                          scale: _stag(0.0, 0.6),
                          child: FadeTransition(
                            opacity: _stag(0.0, 0.5),
                            child: ScaleTransition(
                              scale: Tween(begin: 1.0, end: 1.05).animate(_breathCtrl),
                              child: const _SpotifyIconPainterWidget(color: _kGreen, size: 84),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    _FadeSlide(
                      animation: _stag(0.2, 0.55),
                      child: Column(
                        children: [
                          Text('Millions of songs.', style: SpotifyFonts.display(color: Colors.white, fontSize: 30, height: 1.15)),
                          Text('Free on Spotify.', style: SpotifyFonts.display(color: _kGreen, fontSize: 30, height: 1.15)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FadeSlide(
                      animation: _stag(0.3, 0.6),
                      child: Text('Music streaming, redefined.', style: SpotifyFonts.regular(color: Colors.white.withValues(alpha: 0.42), fontSize: 14)),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 36),
                  child: _FadeSlide(
                    animation: _stag(0.55, 0.8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LoginButton(label: 'Sign up free', filled: true, onTap: widget.onSignUp),
                        const SizedBox(height: 12),
                        _LoginButton(label: 'Continue with Google', filled: false, onTap: widget.onLoginComplete, icon: Icons.g_mobiledata),
                        const SizedBox(height: 12),
                        _LoginButton(label: 'Guest login', filled: false, onTap: widget.onLoginComplete),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatefulWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  final IconData? icon;
  const _LoginButton({required this.label, required this.filled, required this.onTap, this.icon});
  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: widget.filled ? ( _pressed ? const Color(0xFF1ed760) : _kGreen) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: widget.filled ? null : Border.all(color: Colors.white.withValues(alpha: _pressed ? 0.5 : 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, color: Colors.white, size: 22), const SizedBox(width: 8)],
              Text(widget.label, style: SpotifyFonts.bold(color: widget.filled ? Colors.black : Colors.white, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RippleRing extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  const _RippleRing({required this.controller, required this.delay});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = ((controller.value + delay) % 1.0);
        return Transform.scale(
          scale: 1.0 + t * 2.2,
          child: Container(
            width: 76, height: 76,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _kGreen.withValues(alpha: (1.0 - t).clamp(0.0, 0.7)), width: 1.5)),
          ),
        );
      },
    );
  }
}

class _DashedArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _kGreen.withValues(alpha: 0.22)..style = PaintingStyle.stroke..strokeWidth = 1.2;
    final radius = size.width / 2;
    const dashLen = 8.0; const gapLen = 6.0;
    final count = (2 * math.pi * radius / (dashLen + gapLen)).floor();
    for (int i = 0; i < count; i++) {
      final startAngle = (i * (dashLen + gapLen) / (2 * math.pi * radius)) * 2 * math.pi;
      canvas.drawArc(Rect.fromCircle(center: Offset(size.width/2, size.height/2), radius: radius), startAngle, dashLen / radius, false, paint);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _FadeSlide extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _FadeSlide({required this.animation, required this.child});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: animation, builder: (_, __) => Opacity(opacity: animation.value, child: Transform.translate(offset: Offset(0, 28 * (1 - animation.value)), child: child)));
  }
}

class _SpotifyIconPainterWidget extends StatelessWidget {
  final Color color;
  final double size;
  const _SpotifyIconPainterWidget({required this.color, this.size = 44});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/logo.webp',
    width: size,
    height: size,
  );
}
