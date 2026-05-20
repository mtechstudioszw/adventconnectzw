"use server";

import { revalidatePath } from "next/cache";
import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import { sendEmail } from "@/lib/notify/email";
import { sendWhatsapp } from "@/lib/notify/whatsapp";
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
 * Look up the applicant's email + WhatsApp so we can reach them
 * outside the app. Email comes from auth.users (one extra round-trip
 * because PostgREST can't join the auth schema); WhatsApp is on the
 * application row itself (patch_015).
 */
async function fetchApplicantContact(
  supabase: SupabaseClient,
  args: { userId: string; applicationId: string },
): Promise<{ email: string | null; whatsapp: string | null }> {
  let email: string | null = null;
  let whatsapp: string | null = null;
  try {
    const { data: user } = await supabase.auth.admin.getUserById(args.userId);
    email = user.user?.email ?? null;
  } catch (e) {
    console.warn("[notify] getUserById failed:", e);
  }
  try {
    const { data } = await supabase
      .from("business_applications")
      .select("applicant_whatsapp")
      .eq("id", args.applicationId)
      .single();
    whatsapp = (data?.applicant_whatsapp as string | null) ?? null;
  } catch (e) {
    console.warn("[notify] applicant_whatsapp lookup failed:", e);
  }
  return { email, whatsapp };
}

/**
 * Fire-and-forget email + WhatsApp to the applicant. Errors are
 * swallowed — these are best-effort comms and must never roll back
 * the approve / reject transaction.
 */
async function notifyApplicant(args: {
  supabase: SupabaseClient;
  userId: string;
  applicationId: string;
  subject: string;
  message: string;
}) {
  const { email, whatsapp } = await fetchApplicantContact(args.supabase, {
    userId: args.userId,
    applicationId: args.applicationId,
  });
  if (email) {
    await sendEmail({ to: email, subject: args.subject, text: args.message });
  }
  if (whatsapp) {
    await sendWhatsapp({ to: whatsapp, message: args.message });
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

  const approvedBody =
    `Your business account "${app.business_name}" is now active. ` +
    `You can list products in the marketplace and claim a church ` +
    `listing in the app. Open Advent Connect ZW to get started.`;

  await pushAppNotification(supabase, {
    userId: app.user_id,
    title: "Business account approved",
    body: approvedBody,
    type: "business_approved",
    referenceId: app.id,
  });
  await notifyApplicant({
    supabase,
    userId: app.user_id,
    applicationId: app.id,
    subject: `Approved — ${app.business_name}`,
    message: `Good news — your Advent Connect ZW business application was approved.\n\n${approvedBody}`,
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

  const rejectedBody =
    `Your business application for "${app.business_name}" was declined.\n\n` +
    `Reason: ${reviewerNote.trim()}\n\n` +
    `You can edit your details and re-apply from your profile.`;

  await pushAppNotification(supabase, {
    userId: app.user_id,
    title: "Business application declined",
    body: rejectedBody,
    type: "business_rejected",
    referenceId: app.id,
  });
  await notifyApplicant({
    supabase,
    userId: app.user_id,
    applicationId: app.id,
    subject: `Declined — ${app.business_name}`,
    message: rejectedBody,
  });

  revalidatePath("/applications");
  revalidatePath("/");
}
