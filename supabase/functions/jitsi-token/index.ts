// Mints a JaaS (8x8) JWT so an authenticated MentorSpace user can join a call
// as MODERATOR — which skips the meet.jit.si-style lobby entirely.
//
// Secrets required (set with `supabase secrets set ...`):
//   JAAS_APP_ID       vpaas-magic-cookie-xxxxxxxxxxxxxxxx   (tenant / AppID)
//   JAAS_KID          the API key's Key ID from the JaaS console
//   JAAS_PRIVATE_KEY  the PKCS#8 PEM private key for that API key
//
// SUPABASE_URL / SUPABASE_ANON_KEY are injected automatically by the platform.

import { create } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APP_ID = Deno.env.get("JAAS_APP_ID")!;
const KID = Deno.env.get("JAAS_KID")!;
const PRIVATE_KEY_PEM = Deno.env.get("JAAS_PRIVATE_KEY")!;

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

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const clean = pem
    .replace(/\\n/g, "\n") // in case the secret was stored with literal \n
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(clean), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    // Identify the caller from their Supabase auth token.
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);

    const profile = await supabase
      .from("profiles")
      .select("full_name, avatar_url")
      .eq("id", user.id)
      .maybeSingle();
    const name = profile.data?.full_name || user.email || "User";

    const key = await importPrivateKey(PRIVATE_KEY_PEM);
    const now = Math.floor(Date.now() / 1000);

    const payload = {
      aud: "jitsi",
      iss: "chat",
      sub: APP_ID,
      room: "*", // token valid for any room in this tenant
      exp: now + 60 * 60 * 2, // 2 hours
      nbf: now - 10,
      context: {
        user: {
          id: user.id,
          name,
          email: user.email ?? "",
          avatar: profile.data?.avatar_url ?? "",
          moderator: "true", // <- admits instantly, no lobby
        },
        features: {
          livestreaming: "false",
          recording: "false",
          transcription: "false",
          "outbound-call": "false",
        },
      },
    };

    // JaaS consoles show the kid either as the bare key id or already prefixed
    // with the AppID ("<AppID>/<keyid>"). Accept both.
    const kid = KID.includes("/") ? KID : `${APP_ID}/${KID}`;
    const token = await create(
      { alg: "RS256", kid, typ: "JWT" },
      payload,
      key,
    );

    return json({ token, appId: APP_ID });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
