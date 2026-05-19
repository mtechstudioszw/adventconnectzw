"use server";

import { revalidatePath } from "next/cache";
import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";

/**
 * Approve a business application. Atomic in two writes (no SQL
 * function yet): flip the application row to 'approved' AND set
 * profiles.is_business = TRUE for the applicant. If either write
 * fails we bail and let the caller retry — the partial state will
 * be visible in the next page load so the admin can finish the job.
 */
export async function approveApplicationAction(
  applicationId: string,
  reviewerNote: string | null,
) {
  const admin = await requireAdmin();
  const supabase = getServiceSupabase();

  // Look up the application's user so we know which profile to flip.
  const { data: app, error: lookupError } = await supabase
    .from("business_applications")
    .select("id, user_id, status")
    .eq("id", applicationId)
    .single();
  if (lookupError || !app) {
    throw new Error("Application not found.");
  }

  // Mark approved.
  const { error: updateError } = await supabase
    .from("business_applications")
    .update({
      status: "approved",
      reviewed_at: new Date().toISOString(),
      reviewer_note: reviewerNote?.trim() ? reviewerNote.trim() : null,
    })
    .eq("id", applicationId);
  if (updateError) {
    throw new Error(`Could not update application: ${updateError.message}`);
  }

  // Flip the user's is_business switch.
  const { error: profileError } = await supabase
    .from("profiles")
    .update({ is_business: true })
    .eq("id", app.user_id);
  if (profileError) {
    throw new Error(`Could not upgrade profile: ${profileError.message}`);
  }

  // For audit purposes we'd log `admin.id` somewhere; the table
  // doesn't have a reviewer_id column yet so we leave the trail to
  // logs only.
  void admin;

  revalidatePath("/applications");
  revalidatePath("/");
}

export async function rejectApplicationAction(
  applicationId: string,
  reviewerNote: string,
) {
  await requireAdmin();
  if (!reviewerNote.trim()) {
    throw new Error("Reviewer note is required when rejecting.");
  }
  const supabase = getServiceSupabase();
  const { error } = await supabase
    .from("business_applications")
    .update({
      status: "rejected",
      reviewed_at: new Date().toISOString(),
      reviewer_note: reviewerNote.trim(),
    })
    .eq("id", applicationId);
  if (error) {
    throw new Error(`Could not update application: ${error.message}`);
  }

  revalidatePath("/applications");
  revalidatePath("/");
}
