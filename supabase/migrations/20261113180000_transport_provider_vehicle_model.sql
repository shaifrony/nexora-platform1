-- NEXORA transport provider + multiple vehicle model.
-- Staged only. Do not apply to hosted DB without explicit approval.
begin;

-- Preserve the existing public Porter role while adding transport-provider records.
-- Porter account activation remains governed by the separate Porter review workflow.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role = any (array['buyer'::text,'seller'::text,'porter'::text,'admin'::text]));
alter table public.role_requests drop constraint if exists role_requests_requested_role_check;
alter table public.role_requests add constraint role_requests_requested_role_check
  check (requested_role = any (array['seller'::text,'porter'::text]));

create table if not exists public.transport_providers (
 id uuid primary key default gen_random_uuid(),
 owner_user_id uuid not null references public.profiles(id) on delete restrict,
 provider_type text not null check(provider_type in ('individual','business')),
 display_name text not null check(length(btrim(display_name)) between 2 and 160),
 legal_name text,
 contact_phone text not null check(length(btrim(contact_phone)) between 5 and 40),
 country text not null check(length(btrim(country)) between 2 and 120),
 city text not null check(length(btrim(city)) between 2 and 120),
 operating_address text not null check(length(btrim(operating_address)) between 5 and 1000),
 business_registration_number text,
 document_paths text[] not null default '{}',
 application_status text not null default 'pending'
   check(application_status in ('pending','approved','rejected','suspended')),
 admin_note text, reviewed_by uuid references public.profiles(id) on delete set null,
 reviewed_at timestamptz, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists transport_providers_owner_status_idx
 on public.transport_providers(owner_user_id,application_status,created_at desc);
create index if not exists transport_providers_review_queue_idx
 on public.transport_providers(application_status,created_at) where application_status='pending';

create table if not exists public.transport_vehicles (
 id uuid primary key default gen_random_uuid(),
 provider_id uuid not null references public.transport_providers(id) on delete restrict,
 vehicle_type text not null check(length(btrim(vehicle_type)) between 2 and 80),
 make_model text,
 registration_number text not null check(length(btrim(registration_number)) between 2 and 40),
 registration_country text not null check(length(btrim(registration_country)) between 2 and 120),
 capacity_value numeric(12,2) not null check(capacity_value>0),
 capacity_unit text not null check(length(btrim(capacity_unit)) between 1 and 32),
 image_paths text[] not null default '{}', document_paths text[] not null default '{}',
 is_available boolean not null default true,
 approval_status text not null default 'pending'
   check(approval_status in ('pending','approved','rejected','suspended')),
 admin_note text, reviewed_by uuid references public.profiles(id) on delete set null,
 reviewed_at timestamptz, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists transport_vehicles_provider_status_idx
 on public.transport_vehicles(provider_id,approval_status,created_at desc);
create index if not exists transport_vehicles_dispatch_idx
 on public.transport_vehicles(approval_status,is_available,vehicle_type)
 where approval_status='approved' and is_available=true;

create or replace function private.guard_transport_provider_update()
returns trigger language plpgsql set search_path='' as $$
begin
 -- Privileged SECURITY DEFINER review RPCs execute under their function owner;
 -- ordinary authenticated table updates must remain owner-scoped and review-field protected.
 if current_user <> 'authenticated' then
   new.updated_at:=now(); return new;
 end if;
 if auth.uid() is null or auth.uid()<>old.owner_user_id then
   raise exception 'Not allowed to modify provider';
 end if;
 if new.id is distinct from old.id
 or new.created_at is distinct from old.created_at
 or new.owner_user_id is distinct from old.owner_user_id
 or new.application_status is distinct from old.application_status
 or new.admin_note is distinct from old.admin_note
 or new.reviewed_by is distinct from old.reviewed_by
 or new.reviewed_at is distinct from old.reviewed_at then
   raise exception 'Provider review fields are protected';
 end if;
 new.updated_at:=now(); return new;
end $$;
revoke all on function private.guard_transport_provider_update() from public,anon,authenticated;

create or replace function private.guard_transport_vehicle_update()
returns trigger language plpgsql set search_path='' as $$
declare v_owner uuid;
begin
 -- Privileged SECURITY DEFINER review RPCs execute under their function owner;
 -- ordinary authenticated table updates must remain owner-scoped and review-field protected.
 if current_user <> 'authenticated' then
   new.updated_at:=now(); return new;
 end if;
 select owner_user_id into v_owner from public.transport_providers where id=old.provider_id;
 if auth.uid() is null or auth.uid()<>v_owner then raise exception 'Not allowed to modify vehicle'; end if;
 if new.id is distinct from old.id
 or new.created_at is distinct from old.created_at
 or new.provider_id is distinct from old.provider_id
 or new.approval_status is distinct from old.approval_status
 or new.admin_note is distinct from old.admin_note
 or new.reviewed_by is distinct from old.reviewed_by
 or new.reviewed_at is distinct from old.reviewed_at then
   raise exception 'Vehicle review fields are protected';
 end if;
 new.updated_at:=now(); return new;
end $$;
revoke all on function private.guard_transport_vehicle_update() from public,anon,authenticated;

drop trigger if exists trg_guard_transport_provider_update on public.transport_providers;
create trigger trg_guard_transport_provider_update before update on public.transport_providers
for each row execute function private.guard_transport_provider_update();
drop trigger if exists trg_guard_transport_vehicle_update on public.transport_vehicles;
create trigger trg_guard_transport_vehicle_update before update on public.transport_vehicles
for each row execute function private.guard_transport_vehicle_update();

alter table public.transport_providers enable row level security;
alter table public.transport_vehicles enable row level security;

create policy transport_provider_owner_read on public.transport_providers for select to authenticated
using(owner_user_id=(select auth.uid()));
create policy transport_provider_admin_read on public.transport_providers for select to authenticated
using(private.has_nexora_permission('logistics.view'));
create policy transport_provider_owner_insert on public.transport_providers for insert to authenticated
with check(owner_user_id=(select auth.uid()) and application_status='pending'
 and admin_note is null and reviewed_by is null and reviewed_at is null
 and exists(select 1 from public.profiles p where p.id=(select auth.uid())
 and p.role in ('buyer','seller') and p.account_status='active'));
create policy transport_provider_owner_update on public.transport_providers for update to authenticated
using(owner_user_id=(select auth.uid())) with check(owner_user_id=(select auth.uid()));
-- Admin review changes use audited, AAL2-gated SECURITY DEFINER RPCs only.
-- Do not grant direct Admin UPDATE through RLS; that would bypass review audit checks.

create policy transport_vehicle_owner_read on public.transport_vehicles for select to authenticated
using(exists(select 1 from public.transport_providers p where p.id=provider_id and p.owner_user_id=(select auth.uid())));
create policy transport_vehicle_admin_read on public.transport_vehicles for select to authenticated
using(private.has_nexora_permission('logistics.view'));
create policy transport_vehicle_owner_insert on public.transport_vehicles for insert to authenticated
with check(approval_status='pending' and admin_note is null and reviewed_by is null and reviewed_at is null
 and exists(select 1 from public.transport_providers p where p.id=provider_id
 and p.owner_user_id=(select auth.uid()) and p.application_status in ('pending','approved')));
create policy transport_vehicle_owner_update on public.transport_vehicles for update to authenticated
using(exists(select 1 from public.transport_providers p where p.id=provider_id and p.owner_user_id=(select auth.uid())))
with check(exists(select 1 from public.transport_providers p where p.id=provider_id and p.owner_user_id=(select auth.uid())));

grant select,insert,update on public.transport_providers,public.transport_vehicles to authenticated;
revoke delete on public.transport_providers,public.transport_vehicles from anon,authenticated;
comment on table public.transport_providers is 'Porter transport service provider applications; not a user role.';
comment on table public.transport_vehicles is 'Vehicles registered under a transport provider, independently reviewed.';
commit;
