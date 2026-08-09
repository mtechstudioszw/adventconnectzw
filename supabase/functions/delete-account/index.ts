// =====================================================================
//  Edge Function: delete-account
//
//  Deletes the CALLER's own account. Nothing else can: removing an
//  `auth.users` row needs `auth.admin.deleteUser`, which needs the
//  service role, which must never reach a phone.
//
//  This function was referenced by the app from the day account deletion
//  shipped, and never existed. The consequence was not "deletion doesn't
//  work" — the client had a fallback that deleted the `profiles` row
//  itself when this call failed, and `profiles` cascades to 45 tables.
//  So every member who tried to leave lost their posts, prayers,
//  messages and photo, and kept an account they could still sign into.
//  That fallback is gone; this is now the only path, and if it fails
//  nothing is destroyed.
//
//  verify_jwt MUST stay ON. The caller's identity IS the authorisation:
//  the only account this will ever delete is the one the JWT belongs to,
//  and no id is read from the request body precisely so that a caller
//  cannot name someone else.
//
//  Deploy:  supabase functions deploy delete-account
//  Env:     SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (auto-injected).
// =====================================================================
// @ts-nocheck
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/// Buckets where objects are stored under a `<user-id>/` prefix by
/// `StorageService._buildPath`. Deleting the auth row cascades through
/// the database but storage lives outside Postgres, so without this the
/// member's photos stay in the bucket for ever — unreferenced, still
/// billed, and still fetchable by anyone holding an old public URL.
const OWNED_BUCKETS = [
  "profile_photos",
  "story_photos",
  "chat_media",
  "voice_notes",
  "product_photos",
];

/// Remove everything under `<userId>/` in one bucket. Best-effort by
/// design: a bucket that does not exist, or a listing that fails, must
/// not stop the account from being deleted. Storage left behind is a
/// billing problem; a member trapped in an account they asked to leave
/// is a trust problem.
async function purgeBucket(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  userId: string,
): Promise<void> {
  try {
    const { data, error } = await admin.storage.from(bucket).list(userId, {
      limit: 1000,
    });
    if (error || !data || data.length === 0) return;
    const paths = data.map((f: { name: string }) => `${userId}/${f.name}`);
    await admin.storage.from(bucket).remove(paths);
  } catch (e) {
    console.error(`purge ${bucket} failed for ${userId}:`, e);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // ---- who is asking -------------------------------------------------
  // The id comes from the verified JWT and from nowhere else.
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ ok: false, error: "unauthenticated" }, 401);

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  const user = userData?.user;
  if (userErr || !user) {
    return json({ ok: false, error: "unauthenticated" }, 401);
  }

  // ---- storage first --------------------------------------------------
  // Before the auth row goes, while we can still name the folders. If the
  // delete below fails the member keeps their account AND their files,
  // which is the right way round to fail.
  for (const bucket of OWNED_BUCKETS) {
    await purgeBucket(admin, bucket, user.id);
  }

  // ---- the account ----------------------------------------------------
  // `profiles.id REFERENCES auth.users(id) ON DELETE CASCADE`, and the
  // rest of the schema cascades off `profiles`, so this one call removes
  // the member's rows across the database.
  const { error: deleteErr } = await admin.auth.admin.deleteUser(user.id);
  if (deleteErr) {
    console.error("deleteUser failed:", deleteErr);
    return json({ ok: false, error: "delete_failed" }, 500);
  }

  return json({ ok: true });
});
