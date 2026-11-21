-- NEXORA Delivery Network foundation: managed teams and courier partners.
-- Development branch staging only. Never apply to hosted DB without explicit approval.
begin;

create table if not exists public.delivery_network_partners (
  id uuid primary key default gen_random_uuid(),
  partner_code text not null unique default ('NXDP-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  partner_kind text not null check (partner_kind in ('nexora_team','courier_company')),
  display_name text not null check (length(btrim(display_name)) between 2 and 160),
  legal_name text,
  contact_name text,
  contact_phone text not null check (length(btrim(contact_phone)) between 5 and 40),
  contact_email text,
  service_modes text[] not null default array['retail']::text[],
  service_countries text[] not null default array['Bangladesh']::text[],
  service_cities text[] not null default '{}',
  tracking_mode text not null default 'manual' check (tracking_mode in ('manual','api')),
  external_tracking_url text,
  partner_status text not null default 'pending' check (partner_status in ('pending','approved','suspended','inactive')),
  admin_notes text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(service_modes)>0),
  check (service_modes <@ array['retail','wholesale']::text[]),
  check (length(coalesce(admin_notes,''))<=1500),
  check (external_tracking_url is null or external_tracking_url ~ '^https://')
);
create index if not exists delivery_network_partners_status_idx
  on public.delivery_network_partners(partner_status,partner_kind,created_at desc);

create table if not exists public.delivery_network_staff (
  id uuid primary key default gen_random_uuid(),
  staff_code text not null unique default ('NXDS-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  partner_id uuid not null references public.delivery_network_partners(id) on delete restrict,
  full_name text not null check (length(btrim(full_name)) between 2 and 160),
  contact_phone text not null check (length(btrim(contact_phone)) between 5 and 40),
  contact_email text,
  employment_type text not null check (employment_type in ('employee','contract')),
  service_cities text[] not null default '{}',
  vehicle_type text,
  staff_status text not null default 'active' check (staff_status in ('active','inactive','suspended')),
  admin_notes text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(coalesce(admin_notes,''))<=1500)
);
create index if not exists delivery_network_staff_partner_status_idx
  on public.delivery_network_staff(partner_id,staff_status,created_at desc);

alter table public.delivery_network_partners enable row level security;
alter table public.delivery_network_staff enable row level security;
revoke all on public.delivery_network_partners,public.delivery_network_staff from public,anon,authenticated;
grant select on public.delivery_network_partners,public.delivery_network_staff to authenticated;

drop policy if exists delivery_network_partners_admin_read on public.delivery_network_partners;
create policy delivery_network_partners_admin_read on public.delivery_network_partners
 for select to authenticated using (private.has_nexora_permission('logistics.view'));
drop policy if exists delivery_network_staff_admin_read on public.delivery_network_staff;
create policy delivery_network_staff_admin_read on public.delivery_network_staff
 for select to authenticated using (private.has_nexora_permission('logistics.view'));

create or replace function private.upsert_delivery_network_partner(
  p_partner_id uuid,
  p_partner_kind text,
  p_display_name text,
  p_legal_name text,
  p_contact_name text,
  p_contact_phone text,
  p_contact_email text,
  p_service_modes text[],
  p_service_countries text[],
  p_service_cities text[],
  p_tracking_mode text,
  p_external_tracking_url text,
  p_admin_notes text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_admin_code text;
  v_id uuid;
begin
  if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  select s.admin_code into v_admin_code from public.admin_staff s
    join public.profiles p on p.id=s.user_id
   where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
  if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
  if p_partner_kind not in ('nexora_team','courier_company')
     or length(btrim(coalesce(p_display_name,''))) not between 2 and 160
     or length(btrim(coalesce(p_contact_phone,''))) not between 5 and 40
     or p_tracking_mode not in ('manual','api')
     or coalesce(cardinality(p_service_modes),0)=0
     or not (p_service_modes <@ array['retail','wholesale']::text[])
     or coalesce(cardinality(p_service_countries),0)=0
     or length(coalesce(p_admin_notes,''))>1500
     or (p_external_tracking_url is not null and p_external_tracking_url !~ '^https://') then
    raise exception 'Invalid delivery partner details' using errcode='22023';
  end if;
  if p_partner_id is null then
    insert into public.delivery_network_partners(
      partner_kind,display_name,legal_name,contact_name,contact_phone,contact_email,
      service_modes,service_countries,service_cities,tracking_mode,external_tracking_url,
      admin_notes,created_by,reviewed_by,reviewed_at,partner_status
    ) values (
      p_partner_kind,btrim(p_display_name),nullif(btrim(coalesce(p_legal_name,'')),''),
      nullif(btrim(coalesce(p_contact_name,'')),''),
      btrim(p_contact_phone),nullif(btrim(coalesce(p_contact_email,'')),''),
      p_service_modes,p_service_countries,coalesce(p_service_cities,'{}'),
      p_tracking_mode,nullif(btrim(coalesce(p_external_tracking_url,'')),''),
      nullif(btrim(coalesce(p_admin_notes,'')),''),
      v_actor,v_actor,now(),case when p_partner_kind='nexora_team' then 'approved' else 'pending' end
    ) returning id into v_id;
  else
    update public.delivery_network_partners set
      partner_kind=p_partner_kind,display_name=btrim(p_display_name),
      legal_name=nullif(btrim(coalesce(p_legal_name,'')),''),
      contact_name=nullif(btrim(coalesce(p_contact_name,'')),''),
      contact_phone=btrim(p_contact_phone),
      contact_email=nullif(btrim(coalesce(p_contact_email,'')),''),
      service_modes=p_service_modes,service_countries=p_service_countries,
      service_cities=coalesce(p_service_cities,'{}'),tracking_mode=p_tracking_mode,
      external_tracking_url=nullif(btrim(coalesce(p_external_tracking_url,'')),''),
      admin_notes=nullif(btrim(coalesce(p_admin_notes,'')),''),
      updated_at=now()
    where id=p_partner_id returning id into v_id;
    if v_id is null then raise exception 'Delivery partner not found' using errcode='P0002'; end if;
  end if;
  insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
  values(v_actor,v_admin_code,case when p_partner_id is null then 'delivery_network.partner_created' else 'delivery_network.partner_updated' end,
    'delivery_network_partner',v_id::text,jsonb_build_object('partner_kind',p_partner_kind,'tracking_mode',p_tracking_mode));
  return v_id;
end;
$$;

create or replace function private.set_delivery_network_partner_status(
  p_partner_id uuid,p_status text,p_reason text default null
) returns void
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid(); v_admin_code text; v_old text;
begin
  if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  select s.admin_code into v_admin_code from public.admin_staff s
    join public.profiles p on p.id=s.user_id
   where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
  if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
  if p_status not in ('approved','suspended','inactive','pending')
     or length(coalesce(p_reason,''))>1000
     or (p_status in ('suspended','inactive') and length(btrim(coalesce(p_reason,'')))<5) then
    raise exception 'Invalid partner status or reason' using errcode='22023';
  end if;
  select partner_status into v_old from public.delivery_network_partners where id=p_partner_id for update;
  if not found then raise exception 'Delivery partner not found' using errcode='P0002'; end if;
  update public.delivery_network_partners set partner_status=p_status,admin_notes=coalesce(nullif(btrim(coalesce(p_reason,'')),''),admin_notes),
    reviewed_by=v_actor,reviewed_at=now(),updated_at=now() where id=p_partner_id;
  insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details)
  values(v_actor,v_admin_code,'delivery_network.partner_status_changed','delivery_network_partner',p_partner_id::text,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object('previous_status',v_old,'new_status',p_status));
end;
$$;

create or replace function private.upsert_delivery_network_staff(
  p_staff_id uuid,p_partner_id uuid,p_full_name text,p_contact_phone text,p_contact_email text,
  p_employment_type text,p_service_cities text[],p_vehicle_type text,p_staff_status text,p_admin_notes text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid(); v_admin_code text; v_partner_kind text; v_id uuid;
begin
  if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  select s.admin_code into v_admin_code from public.admin_staff s
    join public.profiles p on p.id=s.user_id
   where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
  if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
  select partner_kind into v_partner_kind from public.delivery_network_partners
   where id=p_partner_id and partner_status='approved' for update;
  if v_partner_kind is distinct from 'nexora_team' then
    raise exception 'Staff records can only be attached to an approved NEXORA team' using errcode='23514';
  end if;
  if length(btrim(coalesce(p_full_name,''))) not between 2 and 160
     or length(btrim(coalesce(p_contact_phone,''))) not between 5 and 40
     or p_employment_type not in ('employee','contract')
     or p_staff_status not in ('active','inactive','suspended')
     or length(coalesce(p_admin_notes,''))>1500 then
    raise exception 'Invalid delivery staff details' using errcode='22023';
  end if;
  if p_staff_id is null then
    insert into public.delivery_network_staff(partner_id,full_name,contact_phone,contact_email,employment_type,
      service_cities,vehicle_type,staff_status,admin_notes,created_by,updated_by)
    values(p_partner_id,btrim(p_full_name),btrim(p_contact_phone),nullif(btrim(coalesce(p_contact_email,'')),''),
      p_employment_type,coalesce(p_service_cities,'{}'),nullif(btrim(coalesce(p_vehicle_type,'')),''),
      p_staff_status,nullif(btrim(coalesce(p_admin_notes,'')),''),v_actor,v_actor)
    returning id into v_id;
  else
    update public.delivery_network_staff set partner_id=p_partner_id,full_name=btrim(p_full_name),
      contact_phone=btrim(p_contact_phone),contact_email=nullif(btrim(coalesce(p_contact_email,'')),''),
      employment_type=p_employment_type,service_cities=coalesce(p_service_cities,'{}'),
      vehicle_type=nullif(btrim(coalesce(p_vehicle_type,'')),''),
      staff_status=p_staff_status,admin_notes=nullif(btrim(coalesce(p_admin_notes,'')),''),
      updated_by=v_actor,updated_at=now()
    where id=p_staff_id returning id into v_id;
    if v_id is null then raise exception 'Delivery staff record not found' using errcode='P0002'; end if;
  end if;
  insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
  values(v_actor,v_admin_code,case when p_staff_id is null then 'delivery_network.staff_created' else 'delivery_network.staff_updated' end,
    'delivery_network_staff',v_id::text,jsonb_build_object('partner_id',p_partner_id,'employment_type',p_employment_type));
  return v_id;
end;
$$;

revoke all on function private.upsert_delivery_network_partner(uuid,text,text,text,text,text,text,text[],text[],text[],text,text,text) from public,anon;
revoke all on function private.set_delivery_network_partner_status(uuid,text,text) from public,anon;
revoke all on function private.upsert_delivery_network_staff(uuid,uuid,text,text,text,text,text[],text,text,text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.upsert_delivery_network_partner(uuid,text,text,text,text,text,text,text[],text[],text[],text,text,text) to authenticated;
grant execute on function private.set_delivery_network_partner_status(uuid,text,text) to authenticated;
grant execute on function private.upsert_delivery_network_staff(uuid,uuid,text,text,text,text,text[],text,text,text) to authenticated;

create or replace function public.upsert_delivery_network_partner(
  p_partner_id uuid,p_partner_kind text,p_display_name text,p_legal_name text,p_contact_name text,
  p_contact_phone text,p_contact_email text,p_service_modes text[],p_service_countries text[],
  p_service_cities text[],p_tracking_mode text,p_external_tracking_url text,p_admin_notes text
) returns uuid language sql security invoker set search_path=''
as $$ select private.upsert_delivery_network_partner($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13); $$;

create or replace function public.set_delivery_network_partner_status(p_partner_id uuid,p_status text,p_reason text default null)
returns void language sql security invoker set search_path=''
as $$ select private.set_delivery_network_partner_status($1,$2,$3); $$;

create or replace function public.upsert_delivery_network_staff(
  p_staff_id uuid,p_partner_id uuid,p_full_name text,p_contact_phone text,p_contact_email text,
  p_employment_type text,p_service_cities text[],p_vehicle_type text,p_staff_status text,p_admin_notes text
) returns uuid language sql security invoker set search_path=''
as $$ select private.upsert_delivery_network_staff($1,$2,$3,$4,$5,$6,$7,$8,$9,$10); $$;

revoke all on function public.upsert_delivery_network_partner(uuid,text,text,text,text,text,text,text[],text[],text[],text,text,text) from public,anon;
revoke all on function public.set_delivery_network_partner_status(uuid,text,text) from public,anon;
revoke all on function public.upsert_delivery_network_staff(uuid,uuid,text,text,text,text,text[],text,text,text) from public,anon;
grant execute on function public.upsert_delivery_network_partner(uuid,text,text,text,text,text,text,text[],text[],text[],text,text,text) to authenticated;
grant execute on function public.set_delivery_network_partner_status(uuid,text,text) to authenticated;
grant execute on function public.upsert_delivery_network_staff(uuid,uuid,text,text,text,text,text[],text,text,text) to authenticated;

comment on table public.delivery_network_partners is 'NEXORA-owned delivery teams and contracted courier/logistics companies. Independent people remain transport_providers.';
comment on table public.delivery_network_staff is 'Admin-managed roster for NEXORA-owned delivery teams; no separate public account or role is created in this phase.';

commit;
