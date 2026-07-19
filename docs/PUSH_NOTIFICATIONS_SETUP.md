# Incoming-call push notifications (WhatsApp-style)

Makes a mentor's device **ring when the app is backgrounded or killed**, with a
native full-screen Accept/Decline UI over the lock screen. On Accept the app
joins the same **Jitsi** room as before — this system is only the "doorbell".

## How it works

```
Caller taps call
  → INSERT sessions row                      (unchanged)
  → invoke Edge Function `notify-call`
        → Android tokens: FCM v1 high-priority DATA push
        → iOS tokens:     APNs VoIP (PushKit) push
Mentor's device (any state)
  → Android: FCM background isolate → flutter_callkit_incoming shows the ring
  → iOS:     AppDelegate PushKit handler → CallKit shows the ring
        ├─ Decline → session = 'rejected'
        └─ Accept  → app opens → CallService.join(roomId) → Jitsi (audio/video)
```

- **Android** uses **FCM** (Firebase Cloud Messaging). Firebase is used *only*
  to deliver the wakeup ping — no Firebase Auth/DB. Supabase stays the backend.
- **iOS** uses **APNs VoIP** pushes, the only push type Apple lets ring a killed
  app. Firebase is **not** needed on iOS.
- A **Realtime `sessions`-INSERT listener** remains as a foreground-only
  fallback (deduped by session id), so the app rings in-foreground even before
  push is configured.

If neither transport is configured, the app still builds and runs — killed/
background ringing is simply disabled until you complete the steps below.

---

## 1. Database (required)

Apply the migration that adds the `device_tokens` table:

```bash
supabase db push        # applies supabase/migrations/20260719163000_device_tokens.sql
```

## 2. Deploy the Edge Function (required)

```bash
supabase functions deploy notify-call
```

## 3. Android — Firebase Cloud Messaging

1. **Create a Firebase project** at <https://console.firebase.google.com> (or
   reuse one). Firebase is free for FCM.
2. **Add an Android app** with package name **`app.mentora.mentora`**.
   (App nickname / SHA-1 are optional for FCM.)
3. **Download `google-services.json`** and drop it at:
   ```
   android/app/google-services.json
   ```
   The Gradle plugin auto-activates once this file exists (it's git-ignored by
   default — keep it out of the repo).
4. **Create a service account for FCM v1:**
   Firebase console → ⚙ Project settings → **Service accounts** →
   *Generate new private key* → downloads a JSON file.
5. **Store it as a Supabase secret** (single-line the JSON):
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat path/to/service-account.json)"
   ```

That's the whole Android setup. Rebuild the app:
`flutter build apk --release --split-per-abi` (remember: **JDK 17**).

## 4. iOS — APNs VoIP  *(build on a Mac / Xcode required)*

1. **Apple Developer** → Certificates, Identifiers & Profiles:
   - Ensure the App ID (bundle id, e.g. `app.mentora.mentora`) has the
     **Push Notifications** capability.
   - Create an **APNs Auth Key** (Keys → +, enable *Apple Push Notifications
     service*). Download the **`.p8`** once and note the **Key ID** and your
     **Team ID**.
2. **Supabase secrets:**
   ```bash
   supabase secrets set \
     APNS_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" \
     APNS_KEY_ID=XXXXXXXXXX \
     APNS_TEAM_ID=YYYYYYYYYY \
     APNS_BUNDLE_ID=app.mentora.mentora \
     APNS_PRODUCTION=false      # "true" for TestFlight/App Store builds
   ```
   `APNS_PRODUCTION=false` targets the **sandbox** APNs host (debug builds run
   from Xcode). Switch to `true` for TestFlight/Store builds.
3. **Xcode → Runner target → Signing & Capabilities**, add:
   - **Push Notifications**
   - **Background Modes** → check **Voice over IP**, **Audio, AirPlay…**,
     **Remote notifications** (already declared in `Info.plist`).
4. The native wiring is already in `ios/Runner/AppDelegate.swift` (PushKit →
   CallKit). No `GoogleService-Info.plist` is required (iOS doesn't use Firebase).

> **Note:** iOS cannot silently cancel a ring on a *killed* app (every VoIP push
> must report a call to CallKit). So a caller hang-up before answer is handled on
> iOS by the 45-second ring timeout marking the call `missed`, not by a cancel
> push. Android cancels immediately.

---

## Testing

1. Two accounts (one mentor, one client) on two devices (or device + emulator).
2. Sign in as the mentor; confirm a row appears in `device_tokens` for them.
3. Fully **swipe-kill** the mentor's app.
4. From the client, call the mentor → the mentor's device should ring with the
   native full-screen UI. Accept → both land in the Jitsi room.

Debugging: `notify-call` returns `{ sent, total, errors }`. If `sent: 0`, check
`errors` (missing secret, stale token, wrong APNs host via `APNS_PRODUCTION`).

## Secrets summary

| Secret | Platform | Where it comes from |
|---|---|---|
| `FCM_SERVICE_ACCOUNT` | Android | Firebase → Project settings → Service accounts |
| `APNS_KEY` | iOS | Apple Developer → Keys → APNs `.p8` |
| `APNS_KEY_ID` | iOS | the `.p8` Key ID |
| `APNS_TEAM_ID` | iOS | Apple Developer membership |
| `APNS_BUNDLE_ID` | iOS | iOS bundle id (topic becomes `<bundle>.voip`) |
| `APNS_PRODUCTION` | iOS | `false` (sandbox) / `true` (production) |

`android/app/google-services.json` is a file, not a secret — it lives in the app
bundle and is safe to ship (protected by FCM's server-side auth).
