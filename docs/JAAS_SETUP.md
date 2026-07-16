# JaaS (8x8) video setup

Real calls route through JaaS so users join as **moderator** and skip the
meet.jit.si lobby. The app code + the `jitsi-token` Edge Function are already
done and deployed. You just provide JaaS credentials.

## 1. Create a JaaS account & API key

1. Go to **https://jaas.8x8.vc** and sign up (free — ~25,000 minutes/month).
2. In the console, copy your **AppID** (a.k.a. tenant), format:
   `vpaas-magic-cookie-xxxxxxxxxxxxxxxxxxxxxxxx`
3. Open **API Keys → Add API Key**. This generates an RSA keypair:
   - **Download the private key** (a `.pk` / `.pem` file) — keep it safe.
   - Copy the **Key ID** (the `kid`).

## 2. Store the secrets (Supabase Edge Function)

The private key must stay server-side. From the project root:

```bash
# AppID + Key ID (not sensitive)
supabase secrets set JAAS_APP_ID="vpaas-magic-cookie-xxxxxxxx" JAAS_KID="<your-key-id>"

# Private key — reads the downloaded file, never printed
supabase secrets set JAAS_PRIVATE_KEY="$(cat ~/Downloads/your-key.pk)"
```

(The function was already deployed with `supabase functions deploy jitsi-token`;
secrets take effect on the next call — no redeploy needed.)

## 3. Point the app at JaaS

The AppID is **not secret** (it appears in the room name), so bake it in — either
edit `defaultValue` for `jaasAppId` in `lib/config/app_config.dart`, or run:

```bash
flutter run --dart-define=JAAS_APP_ID=vpaas-magic-cookie-xxxxxxxx
```

When `jaasAppId` is set, `CallService` fetches a JWT from `jitsi-token` and joins
`https://8x8.vc/<AppID>/<room>` as moderator. Leave it empty to fall back to
`meet.jit.si` (which has the lobby problem — smoke test only).

## How it fits together

```
client taps Call
  → CallService asks Edge Function `jitsi-token` for a JWT (as the logged-in user)
  → function signs a JaaS JWT (moderator=true) with your private key
  → Jitsi joins 8x8.vc/<AppID>/<room> with that token → admitted instantly
```

Later, to enforce coins, gate the token: only mint it after `spend_coins`
succeeds, and set a short `exp` so sessions can't run indefinitely.
