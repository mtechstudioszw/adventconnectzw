-- =====================================================================
--  PATCH 015 — Capture applicant WhatsApp on business applications
--
--  WHY:  The admin can email the applicant via auth.users.email, but
--        we also want to contact them on WhatsApp. The applicant now
--        provides a WhatsApp number on the form; the admin panel
--        renders it as a one-tap wa.me link so reviewer can ping
--        them in one click.
--
--  PREREQUISITES: schema.sql + patch_001..patch_014 already applied.
--  IDEMPOTENT:    yes.
-- =====================================================================

ALTER TABLE public.business_applications
  ADD COLUMN IF NOT EXISTS applicant_whatsapp TEXT;

-- =====================================================================
--  END OF PATCH 015
-- =====================================================================
