/// App configuration.
///
/// You can provide these two ways:
///  1. Quick start: paste your values into the defaultValue strings below.
///  2. Safer: pass them at run time and keep them out of git, e.g.
///       flutter run \
///         --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///         --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
///
/// Get these from Supabase: Project Settings -> API -> Project URL / anon public key.
class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://iiwpzxhpqfcoudlqnibp.supabase.co',
  );

  // anon public key — safe to ship in a client app; protected by RLS.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlpd3B6eGhwcWZjb3VkbHFuaWJwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwMjg1MjUsImV4cCI6MjA5OTYwNDUyNX0.fbrrfhBNAd4TlIkjZaCqSb4R7GfyTaglkhUBsnA_4cY',
  );

  /// Deep link Supabase redirects back to after an OAuth (Google/Apple/…) login.
  /// This exact value must be added to your Supabase dashboard:
  ///   Authentication → URL Configuration → Redirect URLs.
  /// The matching URL scheme is registered in AndroidManifest.xml and Info.plist.
  static const String oauthRedirectUrl = 'mentorspace://login-callback';

  /// Jitsi server used only when JaaS is NOT configured (see jaasAppId).
  /// meet.jit.si requires a moderator to log in, so anonymous 1:1 calls get
  /// stuck in a lobby — fine for a smoke test, not for real calls.
  static const String jitsiServerUrl = String.fromEnvironment(
    'JITSI_SERVER_URL',
    defaultValue: 'https://meet.jit.si',
  );

  /// JaaS (8x8) App ID / tenant, e.g. `vpaas-magic-cookie-xxxxxxxx`.
  /// This value is NOT secret (it appears in the JWT and room name). When set,
  /// the app routes calls through https://8x8.vc with a JWT minted by the
  /// `jitsi-token` Supabase Edge Function, which admits the user as moderator
  /// (no lobby). Leave empty to fall back to jitsiServerUrl above.
  static const String jaasAppId = String.fromEnvironment(
    'JAAS_APP_ID',
    defaultValue: 'vpaas-magic-cookie-dfd87abdc0234d4d8e5ef4b70fe57bad',
  );

  static bool get usesJaas => jaasAppId.isNotEmpty;

  static const String jaasServerUrl = 'https://8x8.vc';

  static bool get isConfigured =>
      supabaseUrl.startsWith('http') &&
      !supabaseAnonKey.startsWith('PASTE_');
}
