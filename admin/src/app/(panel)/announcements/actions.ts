"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";

export async function createAnnouncementAction(formData: FormData) {
  const admin = await requireAdmin();
  const title = (formData.get("title") as string)?.trim() ?? "";
  const body = (formData.get("body") as string)?.trim() ?? "";
  const audience = (formData.get("audience") as string) ?? "all";
  const severity = (formData.get("severity") as string) ?? "info";

  if (title.length < 2 || body.length < 2) {
    throw new Error("Title and body are required.");
  }

  const supabase = getServiceSupabase();
  const { error } = await supabase.from("admin_announcements").insert({
    title,
    body,
    audience: ["all", "business", "personal"].includes(audience)
      ? audience
      : "all",
    severity: ["info", "urgent"].includes(severity) ? severity : "info",
    created_by: admin.id,
  });
  if (error) {
    throw new Error(`Could not publish: ${error.message}`);
  }
  revalidatePath("/announcements");
  revalidatePath("/");
  redirect("/announcements");
}

export async function deleteAnnouncementAction(id: string) {
  await requireAdmin();
  const supabase = getServiceSupabase();
  const { error } = await supabase
    .from("admin_announcements")
    .delete()
    .eq("id", id);
  if (error) {
    throw new Error(`Could not delete: ${error.message}`);
  }
  revalidatePath("/announcements");
}
