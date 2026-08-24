import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/firebase_service.dart';

// ══════════════════════════════════════════════════════════
// AUTH FLOW WRAPPER – manages email → password → name → artists
// ══════════════════════════════════════════════════════════
class AuthFlowScreen extends StatefulWidget {
  final VoidCallback onAuthComplete;
  const AuthFlowScreen({super.key, required this.onAuthComplete});

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  String _email = '';
  String _password = '';
  final String _name = '';

  void _nextPage() {
    if (_currentPage < 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    }
  }

  Future<void> _onComplete() async {
    final auth = context.read<AuthProvider>();
    try {
      await FirebaseService.signUpWithEmail(
        email: _email, password: _password, name: _name,
      );
      // Removed saveFollowedArtists as choose artists page is gone
      await auth.login(_email, _name);
    } catch (_) {
      // For demo: just proceed with empty name so setup screen shows
      await auth.login(_email, "");
    }
    widget.onAuthComplete();
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage--);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            if (_currentPage > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _prevPage,
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: _currentPage / 2,
                        backgroundColor: SpotifyColors.surface,
                        valueColor: const AlwaysStoppedAnimation(SpotifyColors.green),
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _EmailPage(onNext: (email) { _email = email; _nextPage(); }),
                  _PasswordPage(onNext: (pw) { _password = pw; _onComplete(); }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Email Page ───────────────────────────────────────────
class _EmailPage extends StatefulWidget {
  final ValueChanged<String> onNext;
  const _EmailPage({required this.onNext});

  @override
  State<_EmailPage> createState() => _EmailPageState();
}

class _EmailPageState extends State<_EmailPage> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return _AuthPageScaffold(
      title: "What's your email?",
      subtitle: "You'll need to confirm this later.",
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _controller,
              style: SpotifyFonts.regular(color: SpotifyColors.white, fontSize: 16),
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'Email address'),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter your email';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  widget.onNext(_controller.text.trim());
                }
              },
              child: Text('Next', style: SpotifyFonts.bold(fontSize: 16)),
            ),

          ],
        ),
      ),
    );
  }
}

// ── Password Page ────────────────────────────────────────
class _PasswordPage extends StatefulWidget {
  final ValueChanged<String> onNext;
  const _PasswordPage({required this.onNext});

  @override
  State<_PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<_PasswordPage> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return _AuthPageScaffold(
      title: 'Create a password',
      subtitle: 'Use at least 8 characters.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _controller,
            obscureText: _obscure,
            style: SpotifyFonts.regular(color: SpotifyColors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: SpotifyColors.lightGrey),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_controller.text.length >= 8) {
                widget.onNext(_controller.text);
              } else {
                SpotifyToast.show(
                  context,
                  'Password must be at least 8 characters',
                  icon: Icons.lock_outline,
                  iconColor: Colors.amberAccent,
                );
              }
            },
            child: Text('Next', style: SpotifyFonts.bold(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

// ── Name Page ────────────────────────────────────────────
class _NamePage extends StatefulWidget {
  final ValueChanged<String> onNext;
  const _NamePage({required this.onNext});

  @override
  State<_NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<_NamePage> {
  final _controller = TextEditingController();
  bool _newsChecked = false;
  bool _dataChecked = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return _AuthPageScaffold(
      title: "What's your name?",
      subtitle: 'This appears on your Spotify profile.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _controller,
            style: SpotifyFonts.regular(color: SpotifyColors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Profile name',
              suffixIcon: _controller.text.isNotEmpty
                  ? const Icon(Icons.check, color: SpotifyColors.green)
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'This appears on your Spotify profile.',
            style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(
              value: _newsChecked, onChanged: (v) => setState(() => _newsChecked = v ?? false),
              activeColor: SpotifyColors.green,
              side: const BorderSide(color: SpotifyColors.lightGrey),
            ),
            Expanded(
              child: Text(
                'Please send me news and offers from Spotify.',
                style: SpotifyFonts.regular(color: SpotifyColors.white, fontSize: 13),
              ),
            ),
          ]),
          Row(children: [
            Checkbox(
              value: _dataChecked, onChanged: (v) => setState(() => _dataChecked = v ?? false),
              activeColor: SpotifyColors.green,
              side: const BorderSide(color: SpotifyColors.lightGrey),
            ),
            Expanded(
              child: Text(
                "Share my registration data with Spotify's content providers.",
                style: SpotifyFonts.regular(color: SpotifyColors.white, fontSize: 13),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const _LegalText(),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (_newsChecked && _dataChecked && _controller.text.trim().isNotEmpty)
                ? () {
                    widget.onNext(_controller.text.trim());
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: (_newsChecked && _dataChecked && _controller.text.trim().isNotEmpty)
                  ? SpotifyColors.green
                  : SpotifyColors.surface,
              foregroundColor: (_newsChecked && _dataChecked && _controller.text.trim().isNotEmpty)
                  ? SpotifyColors.black
                  : SpotifyColors.lightGrey,
            ),
            child: Text(
              'Create account',
              style: SpotifyFonts.bold(
                color: (_newsChecked && _dataChecked && _controller.text.trim().isNotEmpty)
                    ? SpotifyColors.black
                    : SpotifyColors.lightGrey,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Choose Artists Page ──────────────────────────────────
// ── Shared widgets ───────────────────────────────────────
class _AuthPageScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _AuthPageScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Create account',
              style: SpotifyFonts.regular(
                color: SpotifyColors.lightGrey,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: SpotifyFonts.title(color: SpotifyColors.white, fontSize: 26, fontWeight: FontWeight.w700),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideX(begin: 0.1, end: 0),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 14),
          )
              .animate()
              .fadeIn(delay: 100.ms, duration: 400.ms),
          const SizedBox(height: 20),
          child
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideY(begin: 0.1, end: 0),
        ],
      ),
    );
  }
}



class _LegalText extends StatelessWidget {
  const _LegalText();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: SpotifyFonts.regular(color: SpotifyColors.lightGrey, fontSize: 12, height: 1.5),
        children: [
          const TextSpan(text: 'By tapping "Create account", you agree to the Spotify '),
          TextSpan(
            text: 'Terms of Use',
            style: SpotifyFonts.regular(color: SpotifyColors.green, decoration: TextDecoration.underline),
          ),
          const TextSpan(text: '.\n\nTo learn more about how Spotify collects, uses, shares and protects your personal data, please see the Spotify '),
          TextSpan(
            text: 'Privacy Policy',
            style: SpotifyFonts.regular(color: SpotifyColors.green, decoration: TextDecoration.underline),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
