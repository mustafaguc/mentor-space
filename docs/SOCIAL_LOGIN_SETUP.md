# Social login setup (Google & Apple)

The app uses **Supabase's built-in OAuth** (`signInWithOAuth`). All the app-side
code, buttons, and the `mentorspace://login-callback` deep link are already
wired. What's left is provider config in dashboards — this needs *your*
developer accounts, so only you can do it.

Everywhere below, `PROJECT_REF` is your Supabase project ref (the `xxxx` in
`https://xxxx.supabase.co`).

## 0. Register the redirect URL (do this once, both providers need it)

Supabase dashboard → **Authentication → URL Configuration → Redirect URLs** →
add exactly:

```
mentorspace://login-callback
```

## 1. Google

1. **Google Cloud Console** → APIs & Services → **Credentials**.
2. Configure the OAuth consent screen (External). While it's in *Testing*, add
   your Google account under **Test users**, or Google will block sign-in.
3. **Create Credentials → OAuth client ID → Web application** — this is the
   correct (and only) client type for this flow. Set the **Authorized redirect
   URI** to your Supabase callback (must match exactly):
   ```
   https://iiwpzxhpqfcoudlqnibp.supabase.co/auth/v1/callback
   ```
   Copy the **Client ID** and **Client secret**.
4. Supabase dashboard → **Authentication → Providers → Google** → enable, then:
   - **Client IDs** field → paste the **Web** client ID. (This field is a
     comma-separated *superset* — Android / iOS / One-Tap client IDs only belong
     here if you also use native `signInWithIdToken`, which we don't. For the
     browser OAuth flow, the Web client ID alone is correct.)
   - **Client Secret (for OAuth)** field → paste the Web client's secret.
   - Save.

> Because we use the browser-based OAuth flow (not the native SDK), you do **not**
> need Android SHA-1 fingerprints, an iOS client ID, or One-Tap. A single **Web**
> client is the whole payoff of using Supabase's built-in feature.

## 2. Apple  (requires an Apple Developer account — $99/yr)

Apple **requires** "Sign in with Apple" to be offered if you offer any other
social login in an iOS App Store app, so this is needed for release on iOS.

1. **developer.apple.com** → Certificates, Identifiers & Profiles.
2. **Identifiers → App IDs**: on your app's App ID, enable *Sign in with Apple*.
3. **Identifiers → Services IDs**: create one (e.g. `space.mentor.web`), enable
   *Sign in with Apple*, and configure:
   - Domain: `PROJECT_REF.supabase.co`
   - Return URL: `https://PROJECT_REF.supabase.co/auth/v1/callback`
4. **Keys**: create a key with *Sign in with Apple* enabled; download the `.p8`.
5. Supabase dashboard → **Authentication → Providers → Apple** → enable and fill:
   - **Client ID** = the Services ID (`space.mentor.web`)
   - **Secret Key** = generated from your Team ID, Key ID, and the `.p8`
     (Supabase's Apple provider page explains the exact fields).

## 3. Test

Run on a device/simulator, tap **Continue with Google / Apple** → the browser
opens the provider login → on success it returns to the app via the deep link
and you land on the home screen. New users get a profile + wallet automatically
(via the DB trigger) and default to the **client** role.

## Adding more providers later

Facebook, GitHub, etc. are the same: enable in the Supabase dashboard, then call
`AuthService.signInWithProvider(OAuthProvider.facebook)`. No new native config
beyond the one redirect URL already registered.
