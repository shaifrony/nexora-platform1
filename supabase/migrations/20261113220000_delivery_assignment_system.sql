-- NEXORA Delivery Assignment System.
-- Staged migration only. Do not apply to hosted DB without explicit approval.
begin;

-- Logistics permissions are separately grantable by the Super Admin.
insert into public.admin_departments(department_key,department_name,description,is_assignable)
values('logistics','Logistics & Delivery','Transport Provider verification, delivery job assignment and operational oversight.',true)
on conflict(department_key) do update
set department_name=excluded.department_name,description=excluded.description,is_assignable=true;

insert into public.admin_permission_catalog(permission_key,department_key,permission_name,description,is_sensitive)
values
 ('logistics.view','logistics','View Logistics','View approved transport providers, vehicles and delivery job operational/contact details.',true),
 ('logistics.assign','logistics','Manage Delivery Assignments','Create, assign, reassign and cancel delivery jobs; approve or suspend transport providers and vehicles.',true)
on conflict(permission_key) do update
set department_key=excluded.department_key,permission_name=excluded.permission_name,
    description=excluded.description,is_sensitive=excluded.is_sensitive;

create table if not exists public.delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  job_reference text not null unique,
  external_reference text,
  package_description text not null check(length(btrim(package_description)) between 3 and 1000),
  package_count integer not null default 1 check(package_count between 1 and 10000),
  pickup_contact_name text,
  pickup_contact_phone text,
  pickup_address text not null check(length(btrim(pickup_address)) between 5 and 1000),
  pickup_city text not null check(length(btrim(pickup_city)) between 2 and 120),
  pickup_country text not null check(length(btrim(pickup_country)) between 2 and 120),
  recipient_contact_name text,
  recipient_contact_phone text,
  delivery_address text not null check(length(btrim(delivery_address)) between 5 and 1000),
  delivery_city text not null check(length(btrim(delivery_city)) between 2 and 120),
  delivery_country text not null check(length(btrim(delivery_country)) between 2 and 120),
  requested_pickup_at timestamptz,
  delivery_deadline timestamptz,
  special_instructions text,
  assigned_provider_id uuid not null references public.transport_providers(id) on delete restrict,
  assigned_vehicle_id uuid not null references public.transport_vehicles(id) on delete restrict,
  job_status text not null default 'assigned'
    check(job_status in ('assigned','in_transit','delivered','cancelled')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_by uuid references public.profiles(id) on delete set null,
  cancelled_at timestamptz,
  cancellation_reason text,
  check(delivery_deadline is null or requested_pickup_at is null or delivery_deadline >= requested_pickup_at),
  check((job_status='cancelled') = (cancelled_at is not null))
);

create index if not exists delivery_jobs_provider_status_idx
  on public.delivery_jobs(assigned_provider_id,job_status,created_at desc);
create index if not exists delivery_jobs_vehicle_status_idx
  on public.delivery_jobs(assigned_vehicle_id,job_status,created_at desc);
create index if not exists delivery_jobs_queue_idx
  on public.delivery_jobs(job_status,created_at desc);

create table if not exists public.delivery_job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.delivery_jobs(id) on delete restrict,
  event_type text not null check(event_type in ('created_assigned','reassigned','cancelled')),
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  actor_admin_code text not null,
  reason text,
  event_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists delivery_job_events_job_idx
  on public.delivery_job_events(job_id,created_at desc);

alter table public.delivery_jobs enable row level security;
alter table public.delivery_job_events enable row level security;

create policy delivery_jobs_admin_read on public.delivery_jobs
 for select to authenticated
 using(private.has_nexora_permission('logistics.view'));

create policy delivery_jobs_assigned_provider_read on public.delivery_jobs
 for select to authenticated
 using(exists(
   select 1 from public.transport_providers p
   where p.id=assigned_provider_id and p.owner_user_id=(select auth.uid())
 ));

create policy delivery_job_events_admin_read on public.delivery_job_events
 for select to authenticated
 using(private.has_nexora_permission('logistics.view'));

create policy delivery_job_events_provider_read on public.delivery_job_events
 for select to authenticated
 using(exists(
   select 1 from public.delivery_jobs j
   join public.transport_providers p on p.id=j.assigned_provider_id
   where j.id=job_id and p.owner_user_id=(select auth.uid())
 ));

grant select on public.delivery_jobs,public.delivery_job_events to authenticated;
revoke insert,update,delete on public.delivery_jobs,public.delivery_job_events from public,anon,authenticated;

create or replace function private.create_delivery_assignment(
  p_external_reference text,
  p_package_description text,
  p_package_count integer,
  p_pickup_contact_name text,
  p_pickup_contact_phone text,
  p_pickup_address text,
  p_pickup_city text,
  p_pickup_country text,
  p_recipient_contact_name text,
  p_recipient_contact_phone text,
  p_delivery_address text,
  p_delivery_city text,
  p_delivery_country text,
  p_requested_pickup_at timestamptz,
  p_delivery_deadline timestamptz,
  p_special_instructions text,
  p_provider_id uuid,
  p_vehicle_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_admin_code text;
  v_job_id uuid;
  v_job_reference text;
  v_provider_status text;
  v_vehicle_status text;
  v_vehicle_provider uuid;
  v_vehicle_available boolean;
begin
  if v_actor is null
     or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;

  select s.admin_code into v_admin_code
  from public.admin_staff s join public.profiles p on p.id=s.user_id
  where s.user_id=v_actor and s.is_active=true
    and p.role='admin' and p.account_status='active';
  if v_admin_code is null then
    raise exception 'Active Admin membership required' using errcode='42501';
  end if;

  if p_package_count is null or p_package_count<1 or p_package_count>10000 then
    raise exception 'Package count must be between 1 and 10000' using errcode='22023';
  end if;
  if length(btrim(coalesce(p_package_description,''))) not between 3 and 1000
     or length(btrim(coalesce(p_pickup_address,''))) not between 5 and 1000
     or length(btrim(coalesce(p_pickup_city,''))) not between 2 and 120
     or length(btrim(coalesce(p_pickup_country,''))) not between 2 and 120
     or length(btrim(coalesce(p_delivery_address,''))) not between 5 and 1000
     or length(btrim(coalesce(p_delivery_city,''))) not between 2 and 120
     or length(btrim(coalesce(p_delivery_country,''))) not between 2 and 120 then
    raise exception 'Required delivery details are missing or invalid' using errcode='22023';
  end if;
  if p_delivery_deadline is not null and p_requested_pickup_at is not null
     and p_delivery_deadline<p_requested_pickup_at then
    raise exception 'Delivery deadline cannot precede pickup time' using errcode='22023';
  end if;
  if length(coalesce(p_external_reference,''))>120
     or length(coalesce(p_special_instructions,''))>2000 then
    raise exception 'Reference or instructions exceed allowed length' using errcode='22023';
  end if;

  select application_status into v_provider_status
  from public.transport_providers where id=p_provider_id for update;
  if not found or v_provider_status is distinct from 'approved' then
    raise exception 'Selected Transport Provider is not approved' using errcode='23514';
  end if;

  select approval_status,provider_id,is_available
    into v_vehicle_status,v_vehicle_provider,v_vehicle_available
  from public.transport_vehicles where id=p_vehicle_id for update;
  if not found or v_vehicle_status is distinct from 'approved'
     or v_vehicle_provider is distinct from p_provider_id
     or v_vehicle_available is distinct from true then
    raise exception 'Selected Vehicle is not approved, available, or linked to this Provider'
      using errcode='23514';
  end if;
  if exists(select 1 from public.delivery_jobs j
    where j.assigned_vehicle_id=p_vehicle_id
      and j.job_status in ('requested','assigned','accepted','picked_up','in_transit','out_for_delivery','partially_delivered','disputed')) then
    raise exception 'Selected Vehicle already has an active Delivery Job' using errcode='23514';
  end if;

  v_job_id:=gen_random_uuid();
  v_job_reference:='NXD-'||upper(substr(replace(v_job_id::text,'-',''),1,12));

  insert into public.delivery_jobs(
    id,job_reference,external_reference,package_description,package_count,
    pickup_contact_name,pickup_contact_phone,pickup_address,pickup_city,pickup_country,
    recipient_contact_name,recipient_contact_phone,delivery_address,delivery_city,delivery_country,
    requested_pickup_at,delivery_deadline,special_instructions,
    assigned_provider_id,assigned_vehicle_id,job_status,created_by,assigned_by
  ) values (
    v_job_id,v_job_reference,nullif(btrim(coalesce(p_external_reference,'')),''),
    btrim(p_package_description),p_package_count,
    nullif(btrim(coalesce(p_pickup_contact_name,'')),''),
    nullif(btrim(coalesce(p_pickup_contact_phone,'')),''),
    btrim(p_pickup_address),btrim(p_pickup_city),btrim(p_pickup_country),
    nullif(btrim(coalesce(p_recipient_contact_name,'')),''),
    nullif(btrim(coalesce(p_recipient_contact_phone,'')),''),
    btrim(p_delivery_address),btrim(p_delivery_city),btrim(p_delivery_country),
    p_requested_pickup_at,p_delivery_deadline,
    nullif(btrim(coalesce(p_special_instructions,'')),''),
    p_provider_id,p_vehicle_id,'assigned',v_actor,v_actor
  );

  insert into public.delivery_job_events(job_id,event_type,actor_user_id,actor_admin_code,event_data)
  values(v_job_id,'created_assigned',v_actor,v_admin_code,
    jsonb_build_object('provider_id',p_provider_id,'vehicle_id',p_vehicle_id,
      'job_reference',v_job_reference));

  insert into public.admin_audit_logs(
    actor_user_id,actor_admin_code,action_key,target_type,target_id,details
  ) values(v_actor,v_admin_code,'delivery_job.created_assigned',
    'delivery_job',v_job_id::text,
    jsonb_build_object('job_reference',v_job_reference,'provider_id',p_provider_id,'vehicle_id',p_vehicle_id));

  return jsonb_build_object('job_id',v_job_id,'job_reference',v_job_reference,'status','assigned');
end;
$$;

create or replace function private.reassign_delivery_job(
  p_job_id uuid,p_provider_id uuid,p_vehicle_id uuid,p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_admin_code text;
  v_old_provider uuid;
  v_old_vehicle uuid;
  v_status text;
  v_provider_status text;
  v_vehicle_status text;
  v_vehicle_provider uuid;
  v_available boolean;
begin
  if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_reason,'')))<5 or length(p_reason)>1000 then
    raise exception 'Reassignment reason must be 5-1000 characters' using errcode='22023';
  end if;
  select s.admin_code into v_admin_code from public.admin_staff s
    join public.profiles p on p.id=s.user_id
    where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
  if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;

  select assigned_provider_id,assigned_vehicle_id,job_status
    into v_old_provider,v_old_vehicle,v_status
    from public.delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'Delivery Job not found' using errcode='P0002'; end if;
  if v_status<>'assigned' then
    raise exception 'Only jobs with assigned status can be reassigned' using errcode='22023';
  end if;

  select application_status into v_provider_status
    from public.transport_providers where id=p_provider_id for update;
  if v_provider_status is distinct from 'approved' then
    raise exception 'New Provider is not approved' using errcode='23514';
  end if;
  select approval_status,provider_id,is_available into v_vehicle_status,v_vehicle_provider,v_available
    from public.transport_vehicles where id=p_vehicle_id for update;
  if v_vehicle_status is distinct from 'approved' or v_vehicle_provider is distinct from p_provider_id
     or v_available is distinct from true then
    raise exception 'New Vehicle must be approved, available and belong to the selected Provider'
      using errcode='23514';
  end if;
  if exists(select 1 from public.delivery_jobs j
    where j.assigned_vehicle_id=p_vehicle_id and j.id<>p_job_id
      and j.job_status in ('requested','assigned','accepted','picked_up','in_transit','out_for_delivery','partially_delivered','disputed')) then
    raise exception 'New Vehicle already has another active Delivery Job' using errcode='23514';
  end if;
  if v_old_provider=p_provider_id and v_old_vehicle=p_vehicle_id then
    raise exception 'The selected Provider and Vehicle are already assigned' using errcode='22023';
  end if;

  update public.delivery_jobs set assigned_provider_id=p_provider_id,
    assigned_vehicle_id=p_vehicle_id,assigned_by=v_actor,assigned_at=now(),updated_at=now()
    where id=p_job_id;
  insert into public.delivery_job_events(job_id,event_type,actor_user_id,actor_admin_code,reason,event_data)
    values(p_job_id,'reassigned',v_actor,v_admin_code,btrim(p_reason),
      jsonb_build_object('old_provider_id',v_old_provider,'old_vehicle_id',v_old_vehicle,
        'new_provider_id',p_provider_id,'new_vehicle_id',p_vehicle_id));
  insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details)
    values(v_actor,v_admin_code,'delivery_job.reassigned','delivery_job',p_job_id::text,btrim(p_reason),
      jsonb_build_object('old_provider_id',v_old_provider,'old_vehicle_id',v_old_vehicle,
        'new_provider_id',p_provider_id,'new_vehicle_id',p_vehicle_id));
  return jsonb_build_object('job_id',p_job_id,'status','assigned','provider_id',p_provider_id,'vehicle_id',p_vehicle_id);
end;
$$;

create or replace function private.cancel_delivery_job(p_job_id uuid,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_admin_code text;
  v_status text;
begin
  if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_reason,'')))<5 or length(p_reason)>1000 then
    raise exception 'Cancellation reason must be 5-1000 characters' using errcode='22023';
  end if;
  select s.admin_code into v_admin_code from public.admin_staff s
    join public.profiles p on p.id=s.user_id
    where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
  if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;

  select job_status into v_status from public.delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'Delivery Job not found' using errcode='P0002'; end if;
  if v_status in ('delivered','cancelled') then
    raise exception 'Delivered or already cancelled jobs cannot be cancelled' using errcode='22023';
  end if;

  update public.delivery_jobs set job_status='cancelled',cancelled_by=v_actor,
    cancelled_at=now(),cancellation_reason=btrim(p_reason),updated_at=now()
    where id=p_job_id;
  insert into public.delivery_job_events(job_id,event_type,actor_user_id,actor_admin_code,reason,event_data)
    values(p_job_id,'cancelled',v_actor,v_admin_code,btrim(p_reason),
      jsonb_build_object('previous_status',v_status));
  insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details)
    values(v_actor,v_admin_code,'delivery_job.cancelled','delivery_job',p_job_id::text,btrim(p_reason),
      jsonb_build_object('previous_status',v_status));
  return jsonb_build_object('job_id',p_job_id,'status','cancelled');
end;
$$;

revoke all on function private.create_delivery_assignment(text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,uuid,uuid) from public,anon;
revoke all on function private.reassign_delivery_job(uuid,uuid,uuid,text) from public,anon;
revoke all on function private.cancel_delivery_job(uuid,text) from public,anon;
grant execute on function private.create_delivery_assignment(text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,uuid,uuid) to authenticated;
grant execute on function private.reassign_delivery_job(uuid,uuid,uuid,text) to authenticated;
grant execute on function private.cancel_delivery_job(uuid,text) to authenticated;

create or replace function public.create_delivery_assignment(
  p_external_reference text,p_package_description text,p_package_count integer,
  p_pickup_contact_name text,p_pickup_contact_phone text,p_pickup_address text,p_pickup_city text,p_pickup_country text,
  p_recipient_contact_name text,p_recipient_contact_phone text,p_delivery_address text,p_delivery_city text,p_delivery_country text,
  p_requested_pickup_at timestamptz,p_delivery_deadline timestamptz,p_special_instructions text,
  p_provider_id uuid,p_vehicle_id uuid
)
returns jsonb language sql security invoker set search_path=''
as $rpc$
  select private.create_delivery_assignment(
    p_external_reference,p_package_description,p_package_count,
    p_pickup_contact_name,p_pickup_contact_phone,p_pickup_address,p_pickup_city,p_pickup_country,
    p_recipient_contact_name,p_recipient_contact_phone,p_delivery_address,p_delivery_city,p_delivery_country,
    p_requested_pickup_at,p_delivery_deadline,p_special_instructions,p_provider_id,p_vehicle_id
  );
$rpc$;

create or replace function public.reassign_delivery_job(p_job_id uuid,p_provider_id uuid,p_vehicle_id uuid,p_reason text)
returns jsonb language sql security invoker set search_path=''
as $rpc$ select private.reassign_delivery_job(p_job_id,p_provider_id,p_vehicle_id,p_reason); $rpc$;

create or replace function public.cancel_delivery_job(p_job_id uuid,p_reason text)
returns jsonb language sql security invoker set search_path=''
as $rpc$ select private.cancel_delivery_job(p_job_id,p_reason); $rpc$;

revoke all on function public.create_delivery_assignment(text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,uuid,uuid) from public,anon;
revoke all on function public.reassign_delivery_job(uuid,uuid,uuid,text) from public,anon;
revoke all on function public.cancel_delivery_job(uuid,text) from public,anon;
grant execute on function public.create_delivery_assignment(text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,uuid,uuid) to authenticated;
grant execute on function public.reassign_delivery_job(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.cancel_delivery_job(uuid,text) to authenticated;

comment on table public.delivery_jobs is 'Admin-created delivery jobs assigned only to approved NEXORA transport providers and approved vehicles.';
comment on table public.delivery_job_events is 'Append-only operational event history for delivery job assignment changes.';

commit;
