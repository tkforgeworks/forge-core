// forge_core: purge every account flagged for deletion (spec: Account
// deletion). Called by the database (pg_net, on request and every 15
// minutes) with a shared token; deployed with --no-verify-jwt because the
// caller is not a user. For each flagged account: delete the user's Storage
// objects (every bucket, prefix <user_id>/), the user's Vault secrets if
// any, then the auth user, which cascades to accounts and the app's
// tables. Logs ids only, never data.
import { createClient } from "jsr:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const purgeToken = Deno.env.get("FORGE_PURGE_TOKEN") ?? "";
const secretKey = adminKey();

function adminKey(): string {
  // Supabase injects the new keys as JSON dictionaries; the legacy
  // service-role key is the fallback while it still exists.
  const dict = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (dict) {
    try {
      const parsed = JSON.parse(dict) as Record<string, string> | string[];
      const values = Array.isArray(parsed) ? parsed : Object.values(parsed);
      const first = values.find((v) => typeof v === "string" && v.length > 0);
      if (first) return first;
    } catch (_) {
      // fall through
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

function unauthorized(reason: string) {
  console.warn(`forge-purge: ${reason}`);
  return new Response(JSON.stringify({ error: "unauthorized" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (!purgeToken) return unauthorized("FORGE_PURGE_TOKEN is not set");
  const auth = req.headers.get("authorization") ?? "";
  if (auth !== `Bearer ${purgeToken}`) return unauthorized("bad token");
  if (!secretKey) {
    return new Response(JSON.stringify({ error: "no secret key" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(url, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: flagged, error } = await supabase
    .from("accounts")
    .select("id")
    .not("deletion_requested_at", "is", null)
    .limit(100);
  if (error) {
    console.error(`forge-purge: listing flagged accounts failed: ${error.message}`);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const purged: string[] = [];
  const failed: { id: string; step: string; message: string }[] = [];
  for (const row of flagged ?? []) {
    const id = row.id as string;
    try {
      await deleteStorage(supabase, id);
      await deleteVaultSecrets(supabase, id);
      const { error: delError } = await supabase.auth.admin.deleteUser(id);
      if (delError) throw Object.assign(new Error(delError.message), { step: "auth" });
      purged.push(id);
      console.log(`forge-purge: purged ${id}`);
    } catch (e) {
      const err = e as Error & { step?: string };
      failed.push({ id, step: err.step ?? "unknown", message: err.message });
      console.error(`forge-purge: ${id} failed at ${err.step ?? "unknown"}: ${err.message}`);
    }
  }

  return new Response(JSON.stringify({ purged: purged.length, failed }), {
    status: failed.length === 0 ? 200 : 207,
    headers: { "Content-Type": "application/json" },
  });
});

// Every object under <user_id>/ in every bucket, walking folders.
async function deleteStorage(
  supabase: ReturnType<typeof createClient>,
  userId: string,
) {
  const { data: buckets, error } = await supabase.storage.listBuckets();
  if (error) throw Object.assign(new Error(error.message), { step: "storage.listBuckets" });
  for (const bucket of buckets ?? []) {
    const paths = await listAll(supabase, bucket.name, userId);
    for (let i = 0; i < paths.length; i += 100) {
      const { error: rmError } = await supabase.storage
        .from(bucket.name)
        .remove(paths.slice(i, i + 100));
      if (rmError) throw Object.assign(new Error(rmError.message), { step: `storage.remove:${bucket.name}` });
    }
  }
}

async function listAll(
  supabase: ReturnType<typeof createClient>,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const out: string[] = [];
  let offset = 0;
  const limit = 1000;
  while (true) {
    const { data, error } = await supabase.storage
      .from(bucket)
      .list(prefix, { limit, offset });
    if (error) throw Object.assign(new Error(error.message), { step: `storage.list:${bucket}` });
    for (const item of data ?? []) {
      const path = `${prefix}/${item.name}`;
      // Folders come back without an id; recurse into them.
      if (item.id === null || item.id === undefined) {
        out.push(...(await listAll(supabase, bucket, path)));
      } else {
        out.push(path);
      }
    }
    if ((data?.length ?? 0) < limit) return out;
    offset += limit;
  }
}

// Secrets an app may have stored per user (none in v0.1; Apple tokens
// later). Named `forge_user_<id>_*` by convention.
async function deleteVaultSecrets(
  supabase: ReturnType<typeof createClient>,
  userId: string,
) {
  const { error } = await supabase.rpc("forge_delete_user_secrets", { target_user: userId });
  // The helper only exists once an app stores per-user secrets; a missing
  // function is not a failure.
  if (error && !/function .* does not exist/i.test(error.message) && error.code !== "PGRST202") {
    throw Object.assign(new Error(error.message), { step: "vault" });
  }
}
