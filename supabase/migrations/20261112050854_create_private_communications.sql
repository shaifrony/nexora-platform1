-- NEXORA private communications: conversations, messages, files and call signaling.
-- Admin deliberately receives no policy on private communication tables.
create table public.conversations (
 id uuid primary key default gen_random_uuid(),
 conversation_type text not null default 'direct' check (conversation_type in ('direct','group','support')),
 title text, created_by uuid not null references public.profiles(id) on delete cascade,
 status text not null default 'active' check (status in ('active','closed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.conversation_participants (
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 invited_by uuid not null references public.profiles(id),
 invitation_status text not null default 'pending' check (invitation_status in ('pending','accepted','declined','left')),
 joined_at timestamptz, created_at timestamptz not null default now(),
 primary key (conversation_id,user_id)
);
create table public.messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null default '',
 message_type text not null default 'text' check (message_type in ('text','image','file','system')),
 reply_to_id uuid references public.messages(id) on delete set null,
 edited_at timestamptz, deleted_at timestamptz, created_at timestamptz not null default now(),
 constraint messages_body_or_attachment check (length(body) <= 10000)
);
create table public.message_attachments (
 id uuid primary key default gen_random_uuid(),
 message_id uuid not null references public.messages(id) on delete cascade,
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 uploaded_by uuid not null references public.profiles(id) on delete cascade,
 storage_path text not null unique, file_name text not null, mime_type text not null,
 size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 20971520),
 created_at timestamptz not null default now()
);
create table public.call_sessions (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 initiated_by uuid not null references public.profiles(id) on delete cascade,
 call_type text not null check (call_type in ('audio','video')),
 call_status text not null default 'ringing' check (call_status in ('ringing','accepted','declined','ended','missed','cancelled')),
 started_at timestamptz, ended_at timestamptz, created_at timestamptz not null default now()
);
create table public.call_signals (
 id uuid primary key default gen_random_uuid(),
 call_id uuid not null references public.call_sessions(id) on delete cascade,
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 signal_type text not null check (signal_type in ('offer','answer','ice-candidate','hangup','busy')),
 payload jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create index conversation_participants_user_status_idx on public.conversation_participants(user_id,invitation_status,created_at desc);
create index messages_conversation_created_idx on public.messages(conversation_id,created_at desc);
create index messages_sender_created_idx on public.messages(sender_id,created_at desc);
create index attachments_conversation_created_idx on public.message_attachments(conversation_id,created_at);
create index calls_conversation_created_idx on public.call_sessions(conversation_id,created_at desc);
create index call_signals_recipient_created_idx on public.call_signals(recipient_id,created_at);
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;
alter table public.call_sessions enable row level security;
alter table public.call_signals enable row level security;
revoke all on public.conversations,public.conversation_participants,public.messages,public.message_attachments,public.call_sessions,public.call_signals from public,anon;
grant select,insert,update on public.conversations to authenticated;
grant select,insert,update on public.conversation_participants to authenticated;
grant select,insert,update,delete on public.messages to authenticated;
grant select,insert on public.message_attachments to authenticated;
grant select,insert,update on public.call_sessions to authenticated;
grant select,insert on public.call_signals to authenticated;
create policy conversations_participant_read on public.conversations for select to authenticated
using (exists(select 1 from public.conversation_participants cp where cp.conversation_id=id and cp.user_id=(select auth.uid())));
create policy conversations_creator_insert on public.conversations for insert to authenticated
with check (created_by=(select auth.uid()));
create policy conversations_creator_or_member_update on public.conversations for update to authenticated
using (created_by=(select auth.uid()) or exists(select 1 from public.conversation_participants cp where cp.conversation_id=id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'))
with check (created_by=(select auth.uid()) or exists(select 1 from public.conversation_participants cp where cp.conversation_id=id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy participants_read_self_or_members on public.conversation_participants for select to authenticated
using (user_id=(select auth.uid()) or exists(select 1 from public.conversation_participants cp where cp.conversation_id=conversation_participants.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy participants_invite_by_member on public.conversation_participants for insert to authenticated
with check (invited_by=(select auth.uid()) and ((user_id=(select auth.uid()) and invitation_status='accepted') or (user_id<>(select auth.uid()) and invitation_status='pending')) and exists(select 1 from public.conversations c where c.id=conversation_id and c.created_by=(select auth.uid())));
create policy participants_accept_own_invite on public.conversation_participants for update to authenticated
using (user_id=(select auth.uid()) and invitation_status='pending')
with check (user_id=(select auth.uid()) and invitation_status in ('accepted','declined') and invited_by<>user_id);
create policy participants_leave_self on public.conversation_participants for update to authenticated
using (user_id=(select auth.uid()) and invitation_status='accepted')
with check (user_id=(select auth.uid()) and invitation_status='left');
create policy messages_participant_read on public.messages for select to authenticated
using (exists(select 1 from public.conversation_participants cp where cp.conversation_id=messages.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy messages_participant_send on public.messages for insert to authenticated
with check (sender_id=(select auth.uid()) and exists(select 1 from public.conversations c join public.conversation_participants cp on cp.conversation_id=c.id where c.id=conversation_id and c.status='active' and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy messages_owner_edit on public.messages for update to authenticated
using (sender_id=(select auth.uid()) and deleted_at is null) with check (sender_id=(select auth.uid()) and deleted_at is null);
create policy messages_owner_delete on public.messages for delete to authenticated using (sender_id=(select auth.uid()));
create policy attachments_participant_read on public.message_attachments for select to authenticated
using (exists(select 1 from public.conversation_participants cp where cp.conversation_id=message_attachments.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy attachments_sender_insert on public.message_attachments for insert to authenticated
with check (uploaded_by=(select auth.uid()) and exists(select 1 from public.messages m join public.conversation_participants cp on cp.conversation_id=m.conversation_id where m.id=message_id and m.sender_id=(select auth.uid()) and m.conversation_id=message_attachments.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy calls_participant_read on public.call_sessions for select to authenticated
using (exists(select 1 from public.conversation_participants cp where cp.conversation_id=call_sessions.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy calls_participant_start on public.call_sessions for insert to authenticated
with check (initiated_by=(select auth.uid()) and call_status='ringing' and exists(select 1 from public.conversation_participants cp where cp.conversation_id=call_sessions.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy calls_participant_update on public.call_sessions for update to authenticated
using (exists(select 1 from public.conversation_participants cp where cp.conversation_id=call_sessions.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'))
with check (exists(select 1 from public.conversation_participants cp where cp.conversation_id=call_sessions.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy call_signals_sender_recipient_read on public.call_signals for select to authenticated
using ((sender_id=(select auth.uid()) or recipient_id=(select auth.uid())) and exists(select 1 from public.conversation_participants cp where cp.conversation_id=call_signals.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy call_signals_sender_insert on public.call_signals for insert to authenticated
with check (sender_id=(select auth.uid()) and recipient_id<>(select auth.uid()) and exists(select 1 from public.call_sessions cs join public.conversation_participants cp on cp.conversation_id=cs.conversation_id where cs.id=call_id and cs.conversation_id=call_signals.conversation_id and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted') and exists(select 1 from public.conversation_participants target where target.conversation_id=call_signals.conversation_id and target.user_id=recipient_id and target.invitation_status='accepted'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('nexora-chat-files','nexora-chat-files',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy nexora_chat_files_read on storage.objects for select to authenticated using (bucket_id='nexora-chat-files' and exists(select 1 from public.conversation_participants cp where cp.conversation_id=((storage.foldername(name))[1])::uuid and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy nexora_chat_files_insert on storage.objects for insert to authenticated with check (bucket_id='nexora-chat-files' and exists(select 1 from public.conversation_participants cp where cp.conversation_id=((storage.foldername(name))[1])::uuid and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
create policy nexora_chat_files_delete on storage.objects for delete to authenticated using (bucket_id='nexora-chat-files' and owner_id=(select auth.uid())::text and exists(select 1 from public.conversation_participants cp where cp.conversation_id=((storage.foldername(name))[1])::uuid and cp.user_id=(select auth.uid()) and cp.invitation_status='accepted'));
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then alter publication supabase_realtime add table public.messages; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='call_signals') then alter publication supabase_realtime add table public.call_signals; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='call_sessions') then alter publication supabase_realtime add table public.call_sessions; end if;
end $$;