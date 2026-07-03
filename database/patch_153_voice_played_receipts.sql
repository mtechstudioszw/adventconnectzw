-- patch_153: voice-note played receipts (WhatsApp parity).
-- Sender sees when the recipient has PLAYED their voice note (not just
-- read the chat): messages.voice_played_at, set once by the first
-- non-sender participant to play the clip.
--
-- Applied to production via the Supabase Management API on 2026-07-03.

alter table public.messages
  add column if not exists voice_played_at timestamptz;

-- SECURITY DEFINER so we don't have to loosen the messages UPDATE
-- policy: the function itself checks the caller is a participant of the
-- conversation and NOT the sender, and only ever sets the one column,
-- once (voice_played_at is null guard).
create or replace function public.mark_voice_played(p_message_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.messages m
     set voice_played_at = now()
   where m.id = p_message_id
     and m.voice_played_at is null
     and m.sender_id <> auth.uid()
     and (
       exists (
         select 1
           from public.conversations c
          where c.id = m.conversation_id
            and auth.uid() in (c.participant_one_id, c.participant_two_id)
       )
       or exists (
         select 1
           from public.conversation_members cm
          where cm.conversation_id = m.conversation_id
            and cm.user_id = auth.uid()
            and cm.left_at is null
       )
     );
end;
$$;

grant execute on function public.mark_voice_played(bigint) to authenticated;
