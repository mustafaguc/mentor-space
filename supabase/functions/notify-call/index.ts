// Rings a mentor's device(s) for an incoming call — even when their app is
// backgrounded or killed. Invoked by the caller right after creating a session
// (and again with action:"cancel" to dismiss a stale ring if they hang up).
//
// Two transports, chosen per stored device token:
//   - Android  -> FCM v1 high-priority DATA message (Dart shows CallKit)
//   - iOS      -> APNs VoIP push (native PushKit -> CallKit; the only push type
//                 Apple lets ring a *killed* app)
//
// The media is unchanged: on Accept the app joins the same Jitsi room. This
// function only delivers the "someone is calling" signal.
//
// Secrets (supabase secrets set ...):
//   FCM_SERVICE_ACCOUNT  full service-account JSON for the Firebase project
//   APNS_KEY             APNs auth key (.p8 PEM contents)   } iOS only —
//   APNS_KEY_ID          the .p8 Key ID                     } omit them and the
//   APNS_TEAM_ID         Apple Developer Team ID            } function simply
//   APNS_BUNDLE_ID       iOS bundle id (topic = <bundle>.voip)} skips iOS tokens
//   APNS_PRODUCTION      "true" for the production APNs host (default sandbox)
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are auto-injected.

import { create } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function pemToDer(pem: string): Uint8Array {
  const clean = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(clean), (c) => c.charCodeAt(0));
}

// ---- FCM (Android) ---------------------------------------------------------
let fcmCache: { token: string; exp: number } | null = null;

// deno-lint-ignore no-explicit-any
async function fcmAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (fcmCache && fcmCache.exp > now + 60) return fcmCache.token;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key).buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const assertion = await create({ alg: "RS256", typ: "JWT" }, {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }, key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const data = await res.json();
  if (!data.access_token) throw new Error("fcm oauth: " + JSON.stringify(data));
  fcmCache = { token: data.access_token, exp: now + (data.expires_in ?? 3600) };
  return fcmCache.token;
}

// deno-lint-ignore no-explicit-any
async function sendFcm(sa: any, token: string, data: Record<string, string>) {
  const at = await fcmAccessToken(sa);
  return await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${at}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: { token, data, android: { priority: "high" } },
      }),
    },
  );
}

// ---- APNs VoIP (iOS) -------------------------------------------------------
interface ApnsCfg {
  key: string;
  keyId: string;
  teamId: string;
  bundleId: string;
  production: boolean;
}

async function apnsJwt(cfg: ApnsCfg): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(cfg.key).buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  return await create({ alg: "ES256", kid: cfg.keyId, typ: "JWT" }, {
    iss: cfg.teamId,
    iat: Math.floor(Date.now() / 1000),
  }, key);
}

async function sendApnsVoip(
  cfg: ApnsCfg,
  token: string,
  payload: Record<string, unknown>,
) {
  const jwt = await apnsJwt(cfg);
  const host = cfg.production
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  return await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": `${cfg.bundleId}.voip`,
      "apns-push-type": "voip",
      "apns-priority": "10",
      "apns-expiration": "0",
    },
    body: JSON.stringify(payload),
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;

    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);

    const { sessionId, action = "ring" } = await req.json().catch(() => ({}));
    if (!sessionId) return json({ error: "sessionId required" }, 400);

    // RLS lets the caller read their own session; verify they ARE the caller.
    const { data: session } = await userClient
      .from("sessions")
      .select("id, room_id, client_id, mentor_id")
      .eq("id", sessionId)
      .maybeSingle();
    if (!session) return json({ error: "session not found" }, 404);
    if (session.client_id !== user.id) {
      return json({ error: "only the caller can ring" }, 403);
    }

    const { data: prof } = await userClient
      .from("profiles")
      .select("full_name")
      .eq("id", user.id)
      .maybeSingle();
    const callerName = (prof?.full_name ?? "").trim() || "Someone";

    // Service role reads the *recipient's* tokens (RLS would otherwise hide them).
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: tokens } = await admin
      .from("device_tokens")
      .select("token, platform")
      .eq("user_id", session.mentor_id);
    if (!tokens || tokens.length === 0) {
      return json({ sent: 0, reason: "no device tokens" });
    }

    const callData: Record<string, string> = {
      type: action === "cancel" ? "cancel_call" : "incoming_call",
      sessionId: session.id,
      roomId: session.room_id,
      callerId: session.client_id,
      callerName,
    };

    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    const sa = saRaw ? JSON.parse(saRaw) : null;
    const apns: ApnsCfg | null = Deno.env.get("APNS_KEY")
      ? {
        key: Deno.env.get("APNS_KEY")!,
        keyId: Deno.env.get("APNS_KEY_ID")!,
        teamId: Deno.env.get("APNS_TEAM_ID")!,
        bundleId: Deno.env.get("APNS_BUNDLE_ID")!,
        production: Deno.env.get("APNS_PRODUCTION") === "true",
      }
      : null;

    let sent = 0;
    const errors: string[] = [];

    for (const { token, platform } of tokens) {
      try {
        if (platform === "ios_voip") {
          // Every VoIP push MUST report a call to CallKit (iOS 13+), so we can't
          // deliver a silent "cancel" to a killed app. Skip cancels on iOS and
          // let the 45s ring timeout mark the call missed instead.
          if (callData.type === "cancel_call") continue;
          if (!apns) {
            errors.push("apns not configured");
            continue;
          }
          const r = await sendApnsVoip(apns, token, { aps: {}, ...callData });
          if (r.ok) {
            sent++;
          } else {
            const body = await r.text();
            errors.push(`apns ${r.status}: ${body}`);
            if (r.status === 410 || body.includes("BadDeviceToken")) {
              await admin.from("device_tokens").delete().eq("token", token);
            }
          }
        } else {
          if (!sa) {
            errors.push("fcm not configured");
            continue;
          }
          const r = await sendFcm(sa, token, callData);
          if (r.ok) {
            sent++;
          } else {
            const body = await r.text();
            errors.push(`fcm ${r.status}: ${body}`);
            if (body.includes("UNREGISTERED") || body.includes("NOT_FOUND")) {
              await admin.from("device_tokens").delete().eq("token", token);
            }
          }
        }
      } catch (e) {
        errors.push(String(e));
      }
    }

    return json({ sent, total: tokens.length, errors });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
