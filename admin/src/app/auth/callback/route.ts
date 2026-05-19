import { NextRequest, NextResponse } from "next/server";
import { getServerSupabase } from "@/lib/supabase/server";
import { isAdminEmail } from "@/lib/admin";

/**
 * Magic-link landing. Supabase appends `?code=…` to the redirect URL;
 * we trade it for a session cookie, verify the user's email is on the
 * admin allowlist, and bounce them to the dashboard. Non-admins get
 * signed out immediately so a leaked link can't grant access.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  if (!code) {
    return NextResponse.redirect(`${origin}/login`);
  }

  const supabase = getServerSupabase();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return NextResponse.redirect(
      `${origin}/login?error=${encodeURIComponent(error.message)}`,
    );
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!isAdminEmail(user?.email)) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      `${origin}/login?error=${encodeURIComponent(
        "This email is not allowed in the admin panel.",
      )}`,
    );
  }

  return NextResponse.redirect(`${origin}/`);
}
