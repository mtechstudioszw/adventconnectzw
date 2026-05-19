"use client";

import { createBrowserClient } from "@supabase/ssr";

// Browser-side client used only on the login page (to kick off the
// magic-link flow). Once the user has a session, all DB reads go
// through server components / actions so RLS + the allowlist gate
// stay enforced.
export function getBrowserSupabase() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
