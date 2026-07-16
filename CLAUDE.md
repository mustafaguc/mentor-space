# CLAUDE.md

Guidance for working in this repository.

## Project

**MentorSpace** — a mobile mentoring / live-session marketplace. Clients browse
mentors (by sector), see who's **online now**, and start a **video/audio call**.
Mostly 1:1, but group sessions are supported (a teacher with many students share
one room). Sectors: education, health, law, tech, agriculture, services.

## Stack

| Concern | Choice |
|---|---|
| App | **Flutter** (Riverpod for state) |
| Video/Audio | **Jitsi Meet Flutter SDK** via **JaaS (8x8)** |
| Auth · DB · Presence · Functions | **Supabase** |

A "call" = client checks the mentor is online → creates a `sessions` row → both
join the **same Jitsi room** (`8x8.vc/<AppID>/<room>`). Same path for 1:1 and group.

## Common commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <deviceId>                       # dev on a device/simulator
flutter build apk --release --split-per-abi     # shareable APKs (arm64 is the one)

# Supabase (schema is migrations; secrets live in Supabase, not the repo)
supabase db push                                # apply supabase/migrations/*
supabase functions deploy jitsi-token           # deploy the JaaS token minter
```

## Layout

```
lib/
  config/app_config.dart     Supabase URL/anon key, JaaS App ID, OAuth redirect
  models/                    Profile, CoinTransaction
  providers/providers.dart   auth · presence · mentors · wallet · transactions (Riverpod)
  services/
    auth_service.dart        Supabase OAuth (Google/Apple)
    call_service.dart        Jitsi/JaaS join, auto-end when room empties
  ui/                        brand tokens + shared widgets
  screens/                   setup · login · signup · role onboarding · home · wallet
supabase/
  migrations/                tables, RLS, triggers, spend_coins/topup_coins RPCs
  functions/jitsi-token/     Edge Function: mints a JaaS JWT (moderator=true)
docs/                        SOCIAL_LOGIN_SETUP.md, JAAS_SETUP.md
```

## Backend notes

- **Auth is one flow for everyone**: social (or email) sign-in → one-time role
  onboarding (client/mentor) → home. `profiles.role` is NULL until chosen.
- **Presence**: a shared Supabase Realtime channel; the mentor list crosses the
  live online set for green dots.
- **Coins move only through SECURITY DEFINER RPCs** (`spend_coins`, `topup_coins`)
  so balances can't be tampered with client-side.
- **Guests can browse** mentors (RLS allows anon SELECT of `role='mentor'` rows);
  login is required only to start a call.
- **Secrets are NOT in the repo**. The JaaS private key lives in Supabase secrets
  (`supabase secrets set JAAS_APP_ID / JAAS_KID / JAAS_PRIVATE_KEY`). The Supabase
  anon key and JaaS App ID in `app_config.dart` are public/RLS-protected.

## Gotchas (learned the hard way)

- **Android release crash on the call screen.** R8 minification strips
  `org.webrtc.*` classes (only referenced via native JNI), causing a native abort
  (`Check failed: !clazz.is_null() org/webrtc/WebRtcClassLoader`). Fix is in
  `android/app/build.gradle.kts` (`isMinifyEnabled=false`, `useLegacyPackaging=true`)
  + `android/app/proguard-rules.pro` keep rules. Verify a build kept it:
  `unzip -p <apk> classes*.dex | grep -c WebRtcClassLoader` must be `> 0`.
- **Don't use `meet.jit.si`** for real calls: it forces a moderator/lobby and
  anonymous 1:1 calls deadlock. JaaS + our JWT (moderator=true) avoids it.
- **Jitsi is mobile-only** — no macOS/web; iOS needs a real device for camera.
- Release APKs are currently **debug-key-signed** (fine for sideload, not Play Store).

## Conventions

- Match surrounding style; keep comments at the density of nearby code.
- Do **not** add AI/co-author trailers to commit messages.
