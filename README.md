# MentorSpace

A mobile mentoring / live-session marketplace. Clients browse mentors, see who's
**online right now**, and start a **video/audio call** — 1:1 today, group-ready
for the future. Built to grow across sectors: education, health, law, tech,
agriculture, services.

## Stack (and why)

| Concern | Choice | Reason |
|---|---|---|
| App | **Flutter** | One codebase, best-in-class WebRTC tooling |
| Video/Audio | **Jitsi Meet SDK** | Handles the whole call lifecycle (join/mute/end/reconnect) **and** group rooms for free. No hand-written WebRTC signaling. |
| Auth · DB · Presence | **Supabase** | Postgres for a relational marketplace, Realtime **Presence** for online status, no server to run |
| Coins | Postgres + `spend_coins` RPC | Balances change only through a `SECURITY DEFINER` function, so they can't be tampered with |

A "call" = the client checks the mentor is online → creates a `sessions` row →
both join the **same Jitsi room**. The exact same path serves a teacher with
many students (group education) — just more people in one room.

## Setup (Supabase CLI)

The database is defined as a migration under `supabase/migrations/` and applied
with the CLI — no manual SQL pasting.

1. **Create a project** at [supabase.com](https://supabase.com) (dashboard).
2. **Link & push the schema:**
   ```bash
   supabase login                                   # once, browser auth
   supabase link --project-ref <your-project-ref>
   supabase db push                                 # applies migrations/*.sql
   ```
3. **Keys:** pull them with `supabase projects api-keys --project-ref <ref>` and
   put the Project URL + **anon public** key into `lib/config/app_config.dart`
   (or pass via `--dart-define`). Until set, the app boots to a setup screen.
4. **One dashboard toggle** for frictionless testing: Authentication → Sign In /
   Providers → Email → turn **off "Confirm email"** so email signups log in
   instantly. (Social logins never need this.)

## Run it

Jitsi is **mobile-only** — use an iOS simulator or Android emulator (not macOS/web):

```bash
flutter emulators --launch <id>   # or open an iOS Simulator
flutter run
```

To test a real call, sign up **two accounts** (one as *Mentor*, one as *Client*)
on two devices/simulators. The client taps the online mentor; the mentor gets an
incoming-call dialog.

> Dev builds use the public `meet.jit.si` server (zero setup). For production,
> switch `JITSI_SERVER_URL` to JaaS (8x8) or a self-hosted domain, and add a
> TURN server so calls connect reliably behind strict mobile NATs.

## Status

- [x] Auth — **one-tap Google & Apple** (Supabase OAuth) + email fallback, client/mentor roles. Provider setup: [`docs/SOCIAL_LOGIN_SETUP.md`](docs/SOCIAL_LOGIN_SETUP.md)
- [x] **Presence** — live online/offline via Supabase Realtime
- [x] Mentor list with live green dots
- [x] Calling + Jitsi (1:1, incoming-call flow, group-ready)
- [x] **Ratings** — clients rate mentors after a session; average shown on cards
- [x] **Coins** — wallet screen, demo top-up, per-minute charge on call end (capped at balance), transaction ledger
- [ ] Later: real payments (Stripe/IAP), search by sector, scheduled sessions, TURN for production

## Project layout

```
lib/
  config/app_config.dart     Supabase URL/key + Jitsi server
  models/profile.dart
  providers/providers.dart   auth · presence · mentors · wallet (Riverpod)
  services/call_service.dart Jitsi wrapper
  ui/                        brand tokens + shared widgets
  screens/                   setup · login · signup · home
supabase/
  config.toml                CLI + local-stack config
  migrations/                versioned schema: tables, RLS, triggers, coin RPCs
```
