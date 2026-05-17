-- =====================================================================
--  PATCH 010 — Persist applicant name + WhatsApp on church_admins
--
--  WHY:  claim_church_screen.dart collects the applicant's name and
--        WhatsApp number so the reviewer can verify them out-of-band,
--        but applyForChurchAdmin() was only sending the role + letter
--        URL. The reviewer had no contact info to act on.
--
--  WHAT: Two nullable text columns on church_admins. NULL is fine for
--        existing rows (they predate the field); new applications fill
--        them in.
--
--  PREREQUISITES: schema.sql + patch_001..patch_009 already applied.
--  IDEMPOTENT:    yes — ADD COLUMN IF NOT EXISTS throughout.
-- =====================================================================


ALTER TABLE public.church_admins
  ADD COLUMN IF NOT EXISTS applicant_name  TEXT,
  ADD COLUMN IF NOT EXISTS applicant_phone TEXT;


-- =====================================================================
--  END OF PATCH 010
-- =====================================================================
