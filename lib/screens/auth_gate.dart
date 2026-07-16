import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/providers.dart';
import 'home_screen.dart';
import 'role_onboarding_screen.dart';

/// Routes between login → onboarding → home based on auth + profile state.
/// The sign-in flow is identical for everyone; the role is chosen once in
/// onboarding, so clients and mentors share the same entry path.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider); // rebuild on login/logout
    final session = Supabase.instance.client.auth.currentSession;
    // Guests can browse mentors; login is only required to start a session.
    if (session == null) return const HomeScreen();

    final profile = ref.watch(myProfileProvider);
    return profile.when(
      loading: () => const _Splash(),
      error: (e, _) => _Splash(error: '$e', onRetry: () {
        ref.invalidate(myProfileProvider);
      }),
      data: (p) {
        // No role yet → onboarding (same for social and email sign-ins).
        if (p == null || !p.hasRole) return const RoleOnboardingScreen();
        return const HomeScreen();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  final String? error;
  final VoidCallback? onRetry;
  const _Splash({this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load your profile:\n$error',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  if (onRetry != null)
                    FilledButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
      ),
    );
  }
}
