-- NEXORA unified domestic delivery jobs and Admin assignment.
-- Staged only; depends on transport/provider and Delivery Network foundation migrations.
begin;

alter table public.delivery_jobs
  alter column assigned_provider_id drop not null,
  alter column assigned_vehicle_id drop not null,
  alter column assigned_by drop not null,
  alter column assigned_at drop not null,
  alter column assigned_at drop default;

alter table public.delivery_jobs
  add column if not exists assigned_partner_id uuid references public.delivery_network_partners(id) on delete restrict,
  add column if not exists assigned_staff_id uuid references public.delivery_network_staff(id) on delete restrict,
  add column if not exists assignment_source text,
  add column if not exists delivery_mode text not null default 'retail',
  add column if not exists commerce_order_id uuid references public.commerce_orders(id) on delete restrict,
  add column if not exists requested_by uuid references public.profiles(id) on delete restrict;

alter table public.delivery_jobs drop constraint if exists delivery_jobs_job_status_check;
alter table public.delivery_jobs add constraint delivery_jobs_job_status_check
 check(job_status in ('requested','assigned','accepted','picked_up','in_transit','out_for_delivery',
 'delivered','delivery_failed','partially_delivered','disputed','returned','cancelled'));
alter table public.delivery_jobs drop constraint if exists delivery_jobs_assignment_source_check;
alter table public.delivery_jobs add constraint delivery_jobs_assignment_source_check
 check(assignment_source is null or assignment_source in ('independent_provider','nexora_team','courier_partner'));
alter table public.delivery_jobs drop constraint if exists delivery_jobs_delivery_mode_check;
alter table public.delivery_jobs add constraint delivery_jobs_delivery_mode_check
 check(delivery_mode in ('retail','wholesale'));
alter table public.delivery_jobs drop constraint if exists delivery_jobs_single_assignment_check;
alter table public.delivery_jobs add constraint delivery_jobs_single_assignment_check check (
  (case when assigned_provider_id is not null then 1 else 0 end) +
  (case when assigned_partner_id is not null then 1 else 0 end) <= 1
  and (assigned_staff_id is null or assigned_partner_id is not null)
  and (assigned_vehicle_id is null or assigned_provider_id is not null)
);
create index if not exists delivery_jobs_network_dispatch_idx
 on public.delivery_jobs(job_status,delivery_mode,created_at desc);
create index if not exists delivery_jobs_order_idx on public.delivery_jobs(commerce_order_id);

create table if not exists public.delivery_job_assignment_history (
 id bigint generated always as identity primary key,
 job_id uuid not null references public.delivery_jobs(id) on delete restrict,
 assignment_source text not null check(assignment_source in ('independent_provider','nexora_team','courier_partner')),
 provider_id uuid references public.transport_providers(id) on delete restrict,
 partner_id uuid references public.delivery_network_partners(id) on delete restrict,
 staff_id uuid references public.delivery_network_staff(id) on delete restrict,
 vehicle_id uuid references public.transport_vehicles(id) on delete restrict,
 assigned_by uuid not null references public.profiles(id) on delete restrict,
 reason text,
 created_at timestamptz not null default now(),
 check ((provider_id is not null)::int + (partner_id is not null)::int = 1),
 check (staff_id is null or partner_id is not null),
 check (vehicle_id is null or provider_id is not null)
);
create index if not exists delivery_job_assignment_history_job_idx
 on public.delivery_job_assignment_history(job_id,created_at desc);
alter table public.delivery_job_assignment_history enable row level security;
revoke all on public.delivery_job_assignment_history from public,anon,authenticated;
grant select on public.delivery_job_assignment_history to authenticated;
create policy delivery_job_assignment_history_admin_read on public.delivery_job_assignment_history
 for select to authenticated using(private.has_nexora_permission('logistics.view'));

create or replace function private.create_delivery_network_job(
 p_external_reference text,p_package_description text,p_package_count integer,
 p_pickup_contact_name text,p_pickup_contact_phone text,p_pickup_address text,p_pickup_city text,p_pickup_country text,
 p_recipient_contact_name text,p_recipient_contact_phone text,p_delivery_address text,p_delivery_city text,p_delivery_country text,
 p_requested_pickup_at timestamptz,p_delivery_deadline timestamptz,p_special_instructions text,
 p_delivery_mode text,p_commerce_order_id uuid
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_admin_code text;v_id uuid;
begin
 if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
    or not private.has_nexora_permission('logistics.assign') then
   raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
 end if;
 select s.admin_code into v_admin_code from public.admin_staff s join public.profiles p on p.id=s.user_id
 where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
 if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
 if length(btrim(coalesce(p_package_description,''))) not between 3 and 1000
    or p_package_count not between 1 and 10000
    or p_delivery_mode not in ('retail','wholesale')
    or length(btrim(coalesce(p_pickup_address,''))) not between 5 and 1000
    or length(btrim(coalesce(p_delivery_address,''))) not between 5 and 1000 then
   raise exception 'Invalid delivery request details' using errcode='22023';
 end if;
 if p_commerce_order_id is not null and not exists(
   select 1 from public.commerce_orders o where o.id=p_commerce_order_id
   and o.order_status in ('accepted','ready_for_confirmation')
 ) then raise exception 'Linked commerce order must be accepted or ready for fulfilment' using errcode='23514'; end if;
 insert into public.delivery_jobs(
   external_reference,package_description,package_count,pickup_contact_name,pickup_contact_phone,
   pickup_address,pickup_city,pickup_country,recipient_contact_name,recipient_contact_phone,
   delivery_address,delivery_city,delivery_country,requested_pickup_at,delivery_deadline,
   special_instructions,job_status,created_by,assigned_by,assigned_at,delivery_mode,commerce_order_id,requested_by
 ) values (
   nullif(btrim(coalesce(p_external_reference,'')),''),
   btrim(p_package_description),p_package_count,
   nullif(btrim(coalesce(p_pickup_contact_name,'')),''),
   nullif(btrim(coalesce(p_pickup_contact_phone,'')),''),
   btrim(p_pickup_address),btrim(p_pickup_city),btrim(p_pickup_country),
   nullif(btrim(coalesce(p_recipient_contact_name,'')),''),
   nullif(btrim(coalesce(p_recipient_contact_phone,'')),''),
   btrim(p_delivery_address),btrim(p_delivery_city),btrim(p_delivery_country),
   p_requested_pickup_at,p_delivery_deadline,
   nullif(btrim(coalesce(p_special_instructions,'')),''),
   'requested',v_actor,null,null,p_delivery_mode,p_commerce_order_id,v_actor
 ) returning id into v_id;
 insert into public.delivery_job_events(job_id,event_type,actor_user_id,actor_admin_code,reason,event_data)
 values(v_id,'created',v_actor,v_admin_code,'Delivery request created',
   jsonb_build_object('delivery_mode',p_delivery_mode,'commerce_order_id',p_commerce_order_id));
 insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
 values(v_actor,v_admin_code,'delivery_job.requested','delivery_job',v_id::text,
   jsonb_build_object('delivery_mode',p_delivery_mode,'commerce_order_id',p_commerce_order_id));
 return v_id;
end;
$$;

create or replace function private.assign_delivery_job_network(
 p_job_id uuid,p_assignment_source text,p_provider_id uuid,p_partner_id uuid,
 p_staff_id uuid,p_vehicle_id uuid,p_reason text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_admin_code text;v_status text;
 v_provider_status text;v_partner_kind text;v_partner_status text;v_staff_partner uuid;v_vehicle_status text;v_vehicle_provider uuid;
begin
 if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
    or not private.has_nexora_permission('logistics.assign') then
   raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
 end if;
 select s.admin_code into v_admin_code from public.admin_staff s join public.profiles p on p.id=s.user_id
 where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
 if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
 select job_status into v_status from public.delivery_jobs where id=p_job_id for update;
 if not found then raise exception 'Delivery Job not found' using errcode='P0002'; end if;
 if v_status not in ('requested','assigned') then raise exception 'Only requested or assigned jobs can be assigned/reassigned' using errcode='22023'; end if;
 if p_assignment_source='independent_provider' then
   if p_provider_id is null or p_partner_id is not null or p_staff_id is not null then raise exception 'Invalid independent provider assignment'; end if;
   select application_status into v_provider_status from public.transport_providers where id=p_provider_id for update;
   if v_provider_status is distinct from 'approved' then raise exception 'Independent Provider is not approved' using errcode='23514'; end if;
   if p_vehicle_id is not null then
     select approval_status,provider_id into v_vehicle_status,v_vehicle_provider from public.transport_vehicles where id=p_vehicle_id for update;
     if v_vehicle_status is distinct from 'approved' or v_vehicle_provider is distinct from p_provider_id then
       raise exception 'Vehicle must be approved and belong to the selected Provider' using errcode='23514';
     end if;
   end if;
 elsif p_assignment_source in ('nexora_team','courier_partner') then
   if p_partner_id is null or p_provider_id is not null or p_vehicle_id is not null then raise exception 'Invalid partner assignment'; end if;
   select partner_kind,partner_status into v_partner_kind,v_partner_status
   from public.delivery_network_partners where id=p_partner_id for update;
   if v_partner_status is distinct from 'approved' then raise exception 'Delivery Partner is not approved' using errcode='23514'; end if;
   if (p_assignment_source='nexora_team' and v_partner_kind<>'nexora_team')
      or (p_assignment_source='courier_partner' and v_partner_kind<>'courier_company') then
     raise exception 'Partner type does not match assignment source' using errcode='23514';
   end if;
   if p_staff_id is not null then
     select partner_id into v_staff_partner from public.delivery_network_staff
     where id=p_staff_id and staff_status='active' for update;
     if v_staff_partner is distinct from p_partner_id or p_assignment_source<>'nexora_team' then
       raise exception 'Staff must be active and belong to the selected NEXORA team' using errcode='23514';
     end if;
   end if;
 else raise exception 'Unsupported assignment source' using errcode='22023';
 end if;
 update public.delivery_jobs set assigned_provider_id=p_provider_id,assigned_vehicle_id=p_vehicle_id,
   assigned_partner_id=p_partner_id,assigned_staff_id=p_staff_id,assignment_source=p_assignment_source,
   job_status='assigned',assigned_by=v_actor,assigned_at=now(),updated_at=now()
 where id=p_job_id;
 insert into public.delivery_job_assignment_history(job_id,assignment_source,provider_id,partner_id,staff_id,vehicle_id,assigned_by,reason)
 values(p_job_id,p_assignment_source,p_provider_id,p_partner_id,p_staff_id,p_vehicle_id,v_actor,nullif(btrim(coalesce(p_reason,'')),''));
 insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details)
 values(v_actor,v_admin_code,'delivery_job.network_assigned','delivery_job',p_job_id::text,
   nullif(btrim(coalesce(p_reason,'')),''),
   jsonb_build_object('source',p_assignment_source,'provider_id',p_provider_id,'partner_id',p_partner_id,'staff_id',p_staff_id,'vehicle_id',p_vehicle_id));
 return jsonb_build_object('job_id',p_job_id,'status','assigned','assignment_source',p_assignment_source);
end;
$$;

revoke all on function private.create_delivery_network_job(text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text,uuid) from public,anon;
revoke all on function private.assign_delivery_job_network(uuid,text,uuid,uuid,uuid,uuid,text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.create_delivery_network_job(text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text,uuid) to authenticated;
grant execute on function private.assign_delivery_job_network(uuid,text,uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function public.create_delivery_network_job(
 p_external_reference text,p_package_description text,p_package_count integer,
 p_pickup_contact_name text,p_pickup_contact_phone text,p_pickup_address text,p_pickup_city text,p_pickup_country text,
 p_recipient_contact_name text,p_recipient_contact_phone text,p_delivery_address text,p_delivery_city text,p_delivery_country text,
 p_requested_pickup_at timestamptz,p_delivery_deadline timestamptz,p_special_instructions text,
 p_delivery_mode text,p_commerce_order_id uuid
) returns uuid language sql security invoker set search_path=''
as $$ select private.create_delivery_network_job($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18); $$;

create or replace function public.assign_delivery_job_network(
 p_job_id uuid,p_assignment_source text,p_provider_id uuid default null,p_partner_id uuid default null,
 p_staff_id uuid default null,p_vehicle_id uuid default null,p_reason text default null
) returns jsonb language sql security invoker set search_path=''
as $$ select private.assign_delivery_job_network($1,$2,$3,$4,$5,$6,$7); $$;

revoke all on function public.create_delivery_network_job(text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text,uuid) from public,anon;
revoke all on function public.assign_delivery_job_network(uuid,text,uuid,uuid,uuid,uuid,text) from public,anon;
grant execute on function public.create_delivery_network_job(text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text,uuid) to authenticated;
grant execute on function public.assign_delivery_job_network(uuid,text,uuid,uuid,uuid,uuid,text) to authenticated;

comment on table public.delivery_job_assignment_history is 'Append-only assignment history for the unified NEXORA Delivery Network.';
commit;
