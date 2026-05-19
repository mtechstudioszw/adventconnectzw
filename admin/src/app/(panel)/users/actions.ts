"use server";

import { revalidatePath } from "next/cache";
import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";

/**
 * Flip a user's is_banned switch. Banned users still exist in the
 * auth.users table — they just can't perform any user_is_active()-
 * gated mutations (posting, commenting, applying, etc.).
 */
export async function setUserBannedAction(
  userId: string,
  banned: boolean,
) {
  await requireAdmin();
  const supabase = getServiceSupabase();
  const { error } = await supabase
    .from("profiles")
    .update({ is_banned: banned })
    .eq("id", userId);
  if (error) {
    throw new Error(`Could not update user: ${error.message}`);
  }
  revalidatePath("/users");
  revalidatePath("/");
}

/**
 * Strip the business privilege from a user (e.g. after they violate
 * the seller terms). Leaves their account_type unchanged.
 */
export async function revokeBusinessAction(userId: string) {
  await requireAdmin();
  const supabase = getServiceSupabase();
  const { error } = await supabase
    .from("profiles")
    .update({ is_business: false })
    .eq("id", userId);
  if (error) {
    throw new Error(`Could not update user: ${error.message}`);
  }
  revalidatePath("/users");
  revalidatePath("/");
}
