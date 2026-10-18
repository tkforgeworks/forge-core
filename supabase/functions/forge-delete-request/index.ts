// forge_core: web deletion, step 1 (spec: Account deletion, "Web deletion
// requests"). The website's Pages Function posts {email} here with a
// shared header secret. If the address has an account, a single-use
// confirmation link goes out through Resend; the response is identical
// either way, so the form cannot be used to discover accounts. Deployed
// with --no-verify-jwt: the caller is the website, not a user.
//
// Secrets: FORGE_WEB_DELETE_SECRET (shared with the website), RESEND_API_KEY,
// FORGE_MAIL_FROM ("App <accounts@example.com>"), FORGE_APP_NAME,
// FORGE_SITE_URL (where the confirm step lands, e.g.
// https://example.com/privacy/app/delete-account/).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { json, sendMail } from "../_shared/mail.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const sharedSecret = Deno.env.get("FORGE_WEB_DELETE_SECRET") ?? "";
const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
const mailFrom = Deno.env.get("FORGE_MAIL_FROM") ?? "";
const appName = Deno.env.get("FORGE_APP_NAME") ?? "this app";
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

const ok = () => json(200, { ok: true });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method" });
  if (!sharedSecret) {
    console.error("forge-delete-request: FORGE_WEB_DELETE_SECRET is not set");
    return json(401, { error: "unauthorized" });
  }
  if ((req.headers.get("authorization") ?? "") !== `Bearer ${sharedSecret}`) {
    return json(401, { error: "unauthorized" });
  }
  let email = "";
  try {
    const body = await req.json();
    email = typeof body?.email === "string" ? body.email.trim() : "";
  } catch (_) {
    return json(400, { error: "bad_json" });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(400, { error: "bad_email" });

  const supabase = createClient(url, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: token, error } = await supabase.rpc("forge_create_deletion_token", {
    target_email: email,
  });
  if (error) {
    // Logged, not revealed.
    console.error(`forge-delete-request: token issue failed: ${error.message}`);
    return ok();
  }
  if (!token) return ok(); // no such account

  const confirmUrl = `${url}/functions/v1/forge-delete-confirm?token=${encodeURIComponent(token as string)}`;
  try {
    if (!resendKey || !mailFrom) throw new Error("RESEND_API_KEY / FORGE_MAIL_FROM not set");
    await sendMail(resendKey, mailFrom, {
      to: email,
      subject: `Confirm deleting your ${appName} account`,
      heading: "Delete your account?",
      body:
        `Someone asked to delete the ${appName} account for this address. ` +
        `If that was you, confirm below. The link works once and expires in 24 hours. ` +
        `Everything in the account is removed; nothing is kept.`,
      buttonLabel: "Yes, delete my account",
      buttonUrl: confirmUrl,
      footnote: "If you did not ask for this, ignore this email and nothing happens.",
      siteLabel: siteUrl.replace(/^https?:\/\//, "") || appName,
    });
    console.log("forge-delete-request: confirmation sent");
  } catch (e) {
    console.error(`forge-delete-request: mail failed: ${(e as Error).message}`);
  }
  return ok();
});
