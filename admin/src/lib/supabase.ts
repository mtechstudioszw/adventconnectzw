"use client";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * The console's single Supabase client.
 *
 * It holds the **public anon key** and nothing else. There is deliberately no
 * service-role key anywhere in this app, and no server action that wraps one:
 *
 *  - Every `admin_*` RPC is SECURITY DEFINER and calls `assert_staff(...)` or
 *    `assert_super_admin()` server-side. The database is what decides who may
 *    ban a member or turn the app off — not this bundle.
 *  - A service-role key in a Vercel env var is a key that bypasses RLS
 *    entirely, sitting one misconfigured route away from the internet. The
 *    old version of this console had one. It buys nothing here, because the
 *    RPCs already do the work, so it is gone.
 *
 * The practical consequence: a stolen copy of this bundle grants exactly what
 * an anonymous visitor already has. The signed-in staff member's JWT is the
 * only thing that unlocks anything.
 */
const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

let client: SupabaseClient | null = null;

export function supabase(): SupabaseClient {
  if (!client) {
    client = createClient(url, anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        // The console is a plain SPA — there is no OAuth callback route to
        // parse, and leaving this on makes Supabase try to read a hash
        // fragment on every load.
        detectSessionInUrl: false,
      },
    });
  }
  return client;
}

/** True when the deploy is missing its environment variables. */
export const configMissing = !url || !anonKey;
