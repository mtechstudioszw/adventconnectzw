"use server";

import { revalidatePath } from "next/cache";
import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";

export async function setReportStatusAction(
  reportId: string,
  status: "reviewing" | "actioned" | "dismissed",
  actionTaken: string | null,
) {
  const admin = await requireAdmin();
  const supabase = getServiceSupabase();
  const { error } = await supabase
    .from("reports")
    .update({
      status,
      reviewed_by: admin.id,
      reviewed_at: new Date().toISOString(),
      action_taken: actionTaken?.trim() ? actionTaken.trim() : null,
    })
    .eq("id", reportId);
  if (error) {
    throw new Error(`Could not update report: ${error.message}`);
  }
  revalidatePath("/reports");
  revalidatePath("/");
}
