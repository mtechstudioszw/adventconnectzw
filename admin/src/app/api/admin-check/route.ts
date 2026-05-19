import { NextResponse } from "next/server";
import { getServerSupabase } from "@/lib/supabase/server";
import { isAdminEmail } from "@/lib/admin";

/**
 * Returns `{ allowed: boolean }` based on the signed-in user's email
 * vs the ADMIN_EMAILS env allowlist. The client callback page uses
 * this to decide whether to keep or drop the just-issued session.
 */
export async function POST() {
  const supabase = getServerSupabase();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return NextResponse.json({ allowed: isAdminEmail(user?.email) });
}
