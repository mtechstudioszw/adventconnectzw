"use server";

import { revalidatePath } from "next/cache";
import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import { sendEmail } from "@/lib/notify/email";
import { sendWhatsapp } from "@/lib/notify/whatsapp";
import type { SupabaseClient } from "@supabase/supabase-js";

type ClaimRow = {
  id: number;
  user_id: string;
  church_id: number;
  applicant_name: string | null;
  applicant_phone: string | null;
  applicant_email: string | null;
  status: string;
};

async function fetchClaim(
  supabase: SupabaseClient,
  id: number,
): Promise<ClaimRow & { church_name: string }> {
  const { data, error } = await supabase
    .from("church_admins")
    .select(
      "id, user_id, church_id, applicant_name, applicant_phone, applicant_email, status, churches!church_admins_church_id_fkey(name)",
    )
    .eq("id", id)
    .single();
  if (error || !data) {
    throw new Error("Claim not found.");
  }
  const church = data.churches as { name?: string } | null;
  return { ...(data as unknown as ClaimRow), church_name: church?.name ?? "your church" };
}

/**
 * Best-effort email + WhatsApp to the applicant. The in-app notification
 * is fired by the `notify_church_admin_status` DB trigger when the row's
 * status flips, so we do NOT insert one here. Errors are swallowed —
 * comms must never roll back the approve/reject write.
 */
async function notifyApplicant(claim: ClaimRow & { church_name: string }, message: string, subject: string) {
  if (claim.applicant_email) {
    await sendEmail({ to: claim.applicant_email, subject, text: message });
  }
  if (claim.applicant_phone) {
    await sendWhatsapp({ to: claim.applicant_phone, message });
  }
}

/**
 * Approve a church-admin claim. Flips status -> 'approved' (which the
 * is_approved_church_admin RLS helper + the church-admin dashboard key
 * off) and stamps approved_at. The status-change trigger notifies the
 * applicant in-app; we add email/WhatsApp on top.
 */
export async function approveChurchClaimAction(claimId: number) {
  await requireAdmin();
  const supabase = getServiceSupabase();
  const claim = await fetchClaim(supabase, claimId);

  const { error } = await supabase
    .from("church_admins")
    .update({
      status: "approved",
      approved_at: new Date().toISOString(),
      rejection_reason: null,
    })
    .eq("id", claimId);
  if (error) {
    throw new Error(`Could not approve claim: ${error.message}`);
  }

  await notifyApplicant(
    claim,
    `Good news — you're now verified to manage ${claim.church_name} on ` +
      `Advent Connect ZW. Open the app and tap "Manage this church" on your ` +
      `church page to post announcements and update your church profile.`,
    `Approved — ${claim.church_name}`,
  );

  revalidatePath("/church-claims");
  revalidatePath("/");
}

export async function rejectChurchClaimAction(claimId: number, reviewerNote: string) {
  await requireAdmin();
  if (!reviewerNote.trim()) {
    throw new Error("A note is required when declining.");
  }
  const supabase = getServiceSupabase();
  const claim = await fetchClaim(supabase, claimId);

  const { error } = await supabase
    .from("church_admins")
    .update({
      status: "rejected",
      rejection_reason: reviewerNote.trim(),
    })
    .eq("id", claimId);
  if (error) {
    throw new Error(`Could not decline claim: ${error.message}`);
  }

  await notifyApplicant(
    claim,
    `Your request to manage ${claim.church_name} on Advent Connect ZW ` +
      `wasn't approved.\n\nReason: ${reviewerNote.trim()}`,
    `Update — ${claim.church_name}`,
  );

  revalidatePath("/church-claims");
  revalidatePath("/");
}
