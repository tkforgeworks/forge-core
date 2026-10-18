// forge_core: web deletion, step 2. The link in the confirmation email lands
// here with ?token=…; the database consumes the token and flags the
// account (the purge takes over), and the user is sent back to the
// website's page with ?status=done or ?status=invalid. Deployed with
// --no-verify-jwt: the visitor has no session.
//
// Secrets: FORGE_SITE_URL (the app's delete-account page).
import { createClient } from "jsr:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const siteUrl = (Deno.env.get("FORGE_SITE_URL") ?? "").replace(/\/+$/, "");
const secretKey = adminKey();

function adminKey(): string {
  const dict = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (dict) {
    try {
      const parsed = JSON.parse(dict) as Record<string, string> | string[];
      const values = Array.isArray(parsed) ? parsed : Object.values(parsed);
      const first = values.find((v) => typeof v === "string" && v.length > 0);
      if (first) return first;
    } catch (_) { /* fall through */ }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

function land(status: "done" | "invalid"): Response {
  if (siteUrl) {
    return new Response(null, {
      status: 303,
      headers: { location: `${siteUrl}/?status=${status}` },
    });
  }
  // No site configured: say it plainly.
  const text = status === "done"
    ? "Your account is being deleted. You can close this page."
    : "That link is invalid, expired or was already used.";
  return new Response(text, { status: status === "done" ? 200 : 400, headers: { "content-type": "text/plain" } });
}

Deno.serve(async (req) => {
  const token = new URL(req.url).searchParams.get("token") ?? "";
  if (!token) return land("invalid");
  const supabase = createClient(url, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase.rpc("forge_confirm_deletion", { raw_token: token });
  if (error) {
    console.error(`forge-delete-confirm: ${error.message}`);
    return land("invalid");
  }
  if (data === true) console.log("forge-delete-confirm: account flagged");
  return land(data === true ? "done" : "invalid");
});
