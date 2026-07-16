import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../ui/brand.dart';
import '../ui/widgets.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _auth = AuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _showEmail = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _social(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      // Returns via the OAuth deep link; AuthGate reacts on the new session.
    } catch (e) {
      _show('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _emailLogin() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (e) {
      _show(e.message);
    } catch (e) {
      _show('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // When a session appears (email or social login completes), close this
    // screen so the AuthGate underneath routes to onboarding/home.
    ref.listen(authStateProvider, (_, __) {
      if (Supabase.instance.client.auth.currentSession != null &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    return Scaffold(
      body: GradientBackground(
        child: Stack(
          children: [
            LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  _logo(),
                  const SizedBox(height: 22),
                  const Text(
                    'MentorSpace',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Talk to a mentor, live.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _card(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: const Icon(Icons.video_camera_front_rounded,
          size: 44, color: Colors.white),
    );
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          _SocialButton(
            label: 'Continue with Google',
            leading: const _GoogleGlyph(),
            onTap: _loading ? null : () => _social(_auth.signInWithGoogle),
          ),
          const SizedBox(height: 12),
          _SocialButton(
            label: 'Continue with Apple',
            leading: const Icon(Icons.apple, size: 24, color: Colors.black),
            onTap: _loading ? null : () => _social(_auth.signInWithApple),
          ),
          const SizedBox(height: 18),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (!_showEmail) ...[
            const _OrDivider(),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed:
                  _loading ? null : () => setState(() => _showEmail = true),
              icon: const Icon(Icons.mail_outline_rounded, size: 20),
              label: const Text('Continue with email'),
            ),
          ] else
            _emailForm(),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _loading
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SignupScreen())),
            child: const Text.rich(TextSpan(
              text: 'New here?  ',
              style: TextStyle(color: Color(0xFF6B7280)),
              children: [
                TextSpan(
                  text: 'Create an account',
                  style: TextStyle(
                      color: Brand.indigo, fontWeight: FontWeight.w700),
                ),
              ],
            )),
          ),
        ],
      ),
    );
  }

  Widget _emailForm() {
    return Column(
      children: [
        const _OrDivider(),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _loading ? null : _emailLogin,
          child: const Text('Log in'),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget leading;
  final VoidCallback? onTap;
  const _SocialButton(
      {required this.label, required this.leading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.ink,
          side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Lightweight stylized Google "G" so we don't need to bundle a logo asset.
/// Swap for the official multicolor mark before shipping.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Text('G',
          style: TextStyle(
              color: Color(0xFF4285F4),
              fontWeight: FontWeight.w800,
              fontSize: 16)),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ),
        const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
      ],
    );
  }
}
