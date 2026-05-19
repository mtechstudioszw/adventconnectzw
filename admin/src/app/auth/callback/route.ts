import { NextRequest, NextResponse } from "next/server";
import { EmailOtpType } from "@supabase/supabase-js";
import { getServerSupabase } from "@/lib/supabase/server";
import { isAdminEmail } from "@/lib/admin";

/**
 * Magic-link landing. Supabase can send links in two formats:
 *   1. PKCE flow:  ?code=...                              → exchangeCodeForSession
 *   2. OTP flow:   ?token_hash=...&type=magiclink         → verifyOtp
 *
 * Older Supabase projects default to (2); newer ones to (1). We
 * handle either so the email template doesn't matter. After auth we
 * re-check the email against the allowlist and bounce non-admins.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;

  const supabase = getServerSupabase();

  let authError: string | null = null;
  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    authError = error?.message ?? null;
  } else if (tokenHash && type) {
    const { error } = await supabase.auth.verifyOtp({
      type,
      token_hash: tokenHash,
    });
    authError = error?.message ?? null;
  } else {
    authError = "Missing authentication code in the link.";
  }

  if (authError) {
    return NextResponse.redirect(
      `${origin}/login?error=${encodeURIComponent(authError)}`,
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
