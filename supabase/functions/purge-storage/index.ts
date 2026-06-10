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

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
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
