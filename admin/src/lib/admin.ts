import { redirect } from "next/navigation";
import { getServerSupabase } from "./supabase/server";

/**
 * The single source of truth for "is this person allowed in the
 * admin panel?". Anyone whose email isn't in this list is bounced to
 * /login even if they have a valid Supabase session.
 */
export function adminEmailAllowlist(): string[] {
  const raw = process.env.ADMIN_EMAILS ?? "";
  return raw
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter((email) => email.length > 0);
}

export function isAdminEmail(email: string | null | undefined): boolean {
  if (!email) return false;
  const allow = adminEmailAllowlist();
  return allow.includes(email.toLowerCase());
}

/**
 * Use at the top of every protected server component / action. Returns
 * the verified admin user object so the caller can record who did what.
 */
export async function requireAdmin() {
  const supabase = getServerSupabase();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user || !isAdminEmail(user.email)) {
    redirect("/login");
  }
  return user;
}
