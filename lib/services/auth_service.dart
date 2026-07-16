import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Wraps Supabase auth. Social sign-in uses Supabase's built-in OAuth:
/// the provider's login opens in an external browser and returns to the app
/// via the [AppConfig.oauthRedirectUrl] deep link. supabase_flutter picks up
/// the returning session automatically and fires onAuthStateChange — no manual
/// link handling needed. Adding more providers later (Facebook, GitHub, …) is
/// just another OAuthProvider value; no new code.
class AuthService {
  final GoTrueClient _auth = Supabase.instance.client.auth;

  Future<void> signInWithProvider(OAuthProvider provider) {
    return _auth.signInWithOAuth(
      provider,
      redirectTo: AppConfig.oauthRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signInWithGoogle() => signInWithProvider(OAuthProvider.google);
  Future<void> signInWithApple() => signInWithProvider(OAuthProvider.apple);
}
