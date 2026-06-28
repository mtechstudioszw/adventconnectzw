-- patch_138: fix "Delete account doesn't actually delete" (you can sign in
-- again afterwards).
--
-- The delete-account Edge Function deletes the user's content then calls
-- auth.admin.deleteUser(), which cascade-deletes the profiles row. But two
-- foreign keys to profiles were ON DELETE NO ACTION, so they blocked the
-- cascade — auth.admin.deleteUser() failed with an FK violation (500), the
-- auth.users row survived, and the account "came back" on next sign-in.
--
-- Every other FK to profiles/auth.users is already CASCADE or SET NULL. Fixing
-- these two lets the deletion complete.

-- Nullable → null it out (keep the conversation row).
ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_created_by_fkey;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- NOT NULL → cascade (remove the invite when its creator is deleted).
ALTER TABLE public.group_invites
  DROP CONSTRAINT IF EXISTS group_invites_created_by_fkey;
ALTER TABLE public.group_invites
  ADD CONSTRAINT group_invites_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE CASCADE;
