create or replace function private.touch_conversation_on_message()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 update public.conversations set updated_at=now() where id=new.conversation_id;
 return new;
end;
$$;
revoke all on function private.touch_conversation_on_message() from public,anon,authenticated;
drop trigger if exists messages_touch_conversation on public.messages;
create trigger messages_touch_conversation after insert on public.messages
for each row execute function private.touch_conversation_on_message();