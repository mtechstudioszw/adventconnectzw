// =====================================================================
//  Edge Function: purge-storage
//
//  Trigger:  pg_cron daily (net.http_post) — see patch_074.
//  Purpose:  Free storage that SQL can't — deletes the actual S3 files
//            for expired story photos and orphaned chat media/voice
//            notes via the storage API (storage.remove also drops the
//            storage.objects row, unlike a raw SQL delete).
//
//  Asks purgeable_storage_names(bucket) (patch_073) for the orphaned
//  object paths per bucket, then removes them in batches.
//
//  Env: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (auto-injected).
//  verify_jwt = false (harmless cleanup; only removes >24-48h orphans).
// =====================================================================

// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BUCKETS = ["story_photos", "chat_media", "voice_notes"];

/// Constant-time compare, so the secret can't be walked out a byte at a
/// time by timing the response.
function cronSecretOk(supplied: string | null): boolean {
  const expected = Deno.env.get("CRON_SECRET") ?? "";
  if (expected.length === 0 || supplied === null) return false;
  const a = new TextEncoder().encode(supplied);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // This function had NO authentication at all while running with the
  // service-role key and calling storage.remove(). The old header comment
  // called it "harmless cleanup", and the blast radius genuinely is small —
  // purgeable_storage_names() only ever returns orphans older than 24-48h,
  // so a caller cannot choose what gets deleted. But "an unauthenticated
  // endpoint holding the service-role key" is not a sentence that should
  // appear anywhere, and it could be hit in a loop to burn invocations and
  // storage API quota.
  //
  // FAIL CLOSED, including when the env var is missing. The pg_cron job
  // sends this header (see patch notes); nothing else legitimately calls
  // this function.
  if (!cronSecretOk(req.headers.get("x-cron-secret"))) {
    return new Response("forbidden", { status: 403 });
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const result: Record<string, number> = {};
  for (const bucket of BUCKETS) {
    try {
      const { data, error } = await supabase.rpc("purgeable_storage_names", {
        p_bucket: bucket,
      });
      if (error) {
        result[bucket] = -1;
        continue;
      }
      const names = (data ?? [])
        .map((r: { name: string }) => r.name)
        .filter((n: string) => !!n);
      if (names.length === 0) {
        result[bucket] = 0;
        continue;
      }
      // Remove in chunks so one call doesn't get too large.
      let removed = 0;
      for (let i = 0; i < names.length; i += 100) {
        const chunk = names.slice(i, i + 100);
        const { error: rmErr } = await supabase.storage
          .from(bucket)
          .remove(chunk);
        if (!rmErr) removed += chunk.length;
      }
      result[bucket] = removed;
    } catch (_e) {
      result[bucket] = -1;
    }
  }
  return new Response(JSON.stringify({ ok: true, purged: result }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
