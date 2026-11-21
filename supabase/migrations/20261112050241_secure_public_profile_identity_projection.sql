-- Keep public identity data separate from private profile rows.
-- This lets authenticated users see only approved public identity fields while
-- the underlying profiles table remains protected by its owner/admin RLS policies.

create table if not exists public.public_identities (
  id uuid primary key references public.profiles(id) on delete cascade,
  full_name text,
  updated_at timestamptz not null default now()
);

alter table public.public_identities enable row level security;
revoke all on table public.public_identities from public, anon, authenticated;
grant select on table public.public_identities to authenticated;

drop policy if exists "Authenticated users can view public identities" on public.public_identities;
create policy "Authenticated users can view public identities"
  on public.public_identities
  for select
  to authenticated
  using (true);

create or replace function public.sync_public_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    delete from public.public_identities where id = old.id;
    return old;
  end if;

  insert into public.public_identities (id, full_name, updated_at)
  values (new.id, new.full_name, now())
  on conflict (id) do update
    set full_name = excluded.full_name,
        updated_at = excluded.updated_at;

  return new;
end;
$function$;

revoke all on function public.sync_public_identity() from public, anon, authenticated;

drop trigger if exists profiles_sync_public_identity on public.profiles;
create trigger profiles_sync_public_identity
  after insert or update of full_name or delete on public.profiles
  for each row execute function public.sync_public_identity();

insert into public.public_identities (id, full_name, updated_at)
select id, full_name, now()
from public.profiles
on conflict (id) do update
  set full_name = excluded.full_name,
      updated_at = excluded.updated_at;

create or replace view public.public_profiles
with (security_invoker = true, security_barrier = true)
as
select id, full_name
from public.public_identities;

grant select on public.public_profiles to authenticated;
revoke all on public.public_profiles from public, anon;