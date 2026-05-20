"use server";

import { revalidatePath } from "next/cache";
import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";

/**
 * Reply to a feedback submission. Updates the feedback row's status +
 * resolution note, then drops a notification on the submitter so the
 * reply lands in their in-app inbox the next time they refresh.
 */
export async function replyToFeedbackAction(
  feedbackId: string,
  body: string,
  newStatus: "triaged" | "in_progress" | "resolved" | "wont_fix",
) {
  const admin = await requireAdmin();
  const trimmed = body.trim();
  if (trimmed.length < 2) {
    throw new Error("Reply cannot be empty.");
  }
  const supabase = getServiceSupabase();

  const { data: row, error: lookupError } = await supabase
    .from("feedback")
    .select("id, user_id, subject")
    .eq("id", Number(feedbackId))
    .single();
  if (lookupError || !row) {
    throw new Error("Feedback not found.");
  }

  const { error: updateError } = await supabase
    .from("feedback")
    .update({
      status: newStatus,
      triaged_by: admin.id,
      triaged_at: new Date().toISOString(),
      resolution_note: trimmed,
    })
    .eq("id", Number(feedbackId));
  if (updateError) {
    throw new Error(`Could not update feedback: ${updateError.message}`);
  }

  await supabase.from("notifications").insert({
    user_id: row.user_id,
    title: "Reply to your feedback",
    body: `Re: "${row.subject}" — ${trimmed}`,
    type: "feedback_reply",
    reference_id: row.id.toString(),
    reference_type: "feedback",
  });

  revalidatePath("/feedback");
  revalidatePath("/");
}
