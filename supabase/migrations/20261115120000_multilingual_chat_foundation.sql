-- NEXORA multilingual communications foundation.
-- Staged only: do not apply until migration history is reconciled and isolated rehearsal passes.

begin;

create table if not exists public.user_language_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  preferred_language text not null default 'en'
    check (preferred_language ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
  updated_at timestamptz not null default now()
);

alter table public.user_language_preferences enable row level security;
revoke all on public.user_language_preferences from public, anon;
grant select, insert, update on public.user_language_preferences to authenticated;

create policy language_preferences_read_own
on public.user_language_preferences for select to authenticated
using (user_id = (select auth.uid()));

create policy language_preferences_insert_own
on public.user_language_preferences for insert to authenticated
with check (user_id = (select auth.uid()));

create policy language_preferences_update_own
on public.user_language_preferences for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create table if not exists public.message_translations (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  target_language text not null check (target_language ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
  source_language text check (source_language is null or source_language ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
  translated_body text not null check (length(translated_body) <= 10000),
  translation_provider text not null,
  created_at timestamptz not null default now(),
  unique(message_id, target_language),
  constraint message_translation_message_conversation_fk
    foreign key (message_id, conversation_id)
    references public.messages(id, conversation_id) on delete cascade
);

-- The composite FK above is backed by an explicit unique key on messages.
create unique index if not exists messages_id_conversation_unique
  on public.messages(id, conversation_id);

create index if not exists message_translations_conversation_language_idx
  on public.message_translations(conversation_id, target_language, created_at desc);

alter table public.message_translations enable row level security;
revoke all on public.message_translations from public, anon, authenticated;
grant select on public.message_translations to authenticated;

create policy message_translations_participant_read
on public.message_translations for select to authenticated
using (
  exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = message_translations.conversation_id
      and cp.user_id = (select auth.uid())
      and cp.invitation_status = 'accepted'
  )
);

commit;
