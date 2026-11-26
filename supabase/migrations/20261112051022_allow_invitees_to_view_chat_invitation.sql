create or replace function private.is_conversation_invited(p_conversation_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.conversation_participants cp where cp.conversation_id=p_conversation_id and cp.user_id=(select auth.uid())); $$;
revoke all on function private.is_conversation_invited(uuid) from public,anon;
grant execute on function private.is_conversation_invited(uuid) to authenticated;
drop policy if exists conversations_participant_read on public.conversations;
create policy conversations_participant_read on public.conversations for select to authenticated
using (private.is_conversation_member(id) or private.is_conversation_creator(id) or private.is_conversation_invited(id));