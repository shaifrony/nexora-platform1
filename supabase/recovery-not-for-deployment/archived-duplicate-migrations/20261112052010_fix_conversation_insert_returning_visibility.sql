drop policy if exists conversations_participant_read on public.conversations;
create policy conversations_participant_read on public.conversations for select to authenticated
using (created_by=(select auth.uid()) or private.is_conversation_member(id) or private.is_conversation_invited(id));