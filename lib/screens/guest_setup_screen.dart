import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

class GuestSetupScreen extends StatefulWidget {
  final Function(String) onComplete;

  const GuestSetupScreen({super.key, required this.onComplete});

  @override
  State<GuestSetupScreen> createState() => _GuestSetupScreenState();
}

class _GuestSetupScreenState extends State<GuestSetupScreen> {
  final _nameController = TextEditingController();
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Text(
                  "What should we call you?",
                  style: SpotifyFonts.regular( 
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),
                const SizedBox(height: 12),
                Text(
                  "Enter the name you'd like to use in the app.",
                  style: SpotifyFonts.regular( 
                    color: SpotifyColors.lightGrey,
                    fontSize: 16,
                  ),
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  style: SpotifyFonts.regular(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    hintText: "Your Name",
                    hintStyle: SpotifyFonts.regular(color: SpotifyColors.surfaceLight),
                    filled: true,
                    fillColor: SpotifyColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(20),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please enter your name";
                    }
                    return null;
                  },
                ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1)),
                const SizedBox(height: 32),
                _buildCheckbox(
                  title: "I accept the Terms and Conditions",
                  value: _termsAccepted,
                  onChanged: (val) => setState(() => _termsAccepted = val!),
                ).animate().fadeIn(delay: 600.ms),
                _buildCheckbox(
                  title: "I agree to the Privacy Policy",
                  value: _privacyAccepted,
                  onChanged: (val) => setState(() => _privacyAccepted = val!),
                ).animate().fadeIn(delay: 700.ms),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (_termsAccepted && _privacyAccepted)
                        ? () {
                            if (_formKey.currentState!.validate()) {
                              widget.onComplete(_nameController.text.trim());
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SpotifyColors.green,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: SpotifyColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      "Create Account",
                      style: SpotifyFonts.regular( 
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.5, end: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckbox({
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Row(
      children: [
        Theme(
          data: ThemeData(unselectedWidgetColor: SpotifyColors.lightGrey),
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: SpotifyColors.green,
            checkColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        Expanded(
          child: Text(
            title,
            style: SpotifyFonts.regular(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
