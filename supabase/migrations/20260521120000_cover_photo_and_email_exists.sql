-- =============================================================================
-- 20260521120000_cover_photo_and_email_exists.sql
-- =============================================================================
-- Adds cover photo columns to profiles + sellers, and provisions the
-- email_exists() RPC used by the unified auth screen to decide
-- whether to show the login or signup form for a typed email.
--
-- Safe to run more than once: every statement is guarded with
-- IF NOT EXISTS / OR REPLACE.
-- =============================================================================

-- ----- Cover photo column on profiles ----------------------------------------
alter table public.profiles
  add column if not exists cover_photo_url text;

-- ----- Cover photo column on sellers -----------------------------------------
alter table public.sellers
  add column if not exists cover_photo_url text;

-- ----- email_exists(p_email) RPC ---------------------------------------------
-- Used by the unified login/signup screen. Returns true when an account
-- already exists for the given email, false otherwise. SECURITY DEFINER
-- so the anon role can call it without seeing the auth.users table
-- directly.
create or replace function public.email_exists(p_email text)
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select exists(
    select 1
    from auth.users
    where lower(email) = lower(p_email)
  );
$$;

-- Allow both signed-in and anonymous callers to ask the question.
grant execute on function public.email_exists(text) to anon, authenticated;

-- =============================================================================
-- Smoke tests (run manually in SQL editor after applying)
-- =============================================================================
-- select column_name
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name in ('profiles','sellers')
--     and column_name = 'cover_photo_url';
--
-- select public.email_exists('someone@example.com');
-- =============================================================================
