"use server";

import { revalidatePath } from "next/cache";
import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import type { SupabaseClient } from "@supabase/supabase-js";

async function pushAppNotification(
  supabase: SupabaseClient,
  args: { userId: string; title: string; body: string; type: string; referenceId: string },
) {
  // Best-effort — failures should not block the approval workflow.
  const { error } = await supabase.from("notifications").insert({
    user_id: args.userId,
    title: args.title,
    body: args.body,
    type: args.type,
    reference_id: args.referenceId,
    reference_type: "business_application",
  });
  if (error) {
    console.warn("notification insert failed", error.message);
  }
}

/**
 * Approve a business application. Atomic in two writes (no SQL
 * function yet): flip the application row to 'approved' AND set
 * profiles.is_business = TRUE for the applicant. Also drops an
 * in-app notification so the user knows the moment they refresh.
 */
export async function approveApplicationAction(
  applicationId: string,
  reviewerNote: string | null,
) {
  const admin = await requireAdmin();
  const supabase = getServiceSupabase();

  const { data: app, error: lookupError } = await supabase
    .from("business_applications")
    .select("id, user_id, business_name, status")
    .eq("id", applicationId)
    .single();
  if (lookupError || !app) {
    throw new Error("Application not found.");
  }

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

  const { error: profileError } = await supabase
    .from("profiles")
    .update({ is_business: true })
    .eq("id", app.user_id);
  if (profileError) {
    throw new Error(`Could not upgrade profile: ${profileError.message}`);
  }

  await pushAppNotification(supabase, {
    userId: app.user_id,
    title: "Business account approved",
    body: `Your business account "${app.business_name}" is now active. You can now list products in the marketplace and claim a church listing.`,
    type: "business_approved",
    referenceId: app.id,
  });

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

  const { data: app, error: lookupError } = await supabase
    .from("business_applications")
    .select("id, user_id, business_name")
    .eq("id", applicationId)
    .single();
  if (lookupError || !app) {
    throw new Error("Application not found.");
  }

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

  await pushAppNotification(supabase, {
    userId: app.user_id,
    title: "Business application declined",
    body: `Your business application for "${app.business_name}" was declined. Reason: ${reviewerNote.trim()} You can edit and re-apply from your profile.`,
    type: "business_rejected",
    referenceId: app.id,
  });

  revalidatePath("/applications");
  revalidatePath("/");
}
