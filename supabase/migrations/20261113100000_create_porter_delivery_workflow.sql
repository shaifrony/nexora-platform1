-- NEXORA Porter delivery workflow. Staged only; not applied to the hosted database.
insert into public.admin_departments (department_key,department_name,description,is_assignable)
values ('logistics_transport','Logistics & Transport','পরিবহন, ডেলিভারি কাজ ও রুট ব্যবস্থাপনা',true)
on conflict (department_key) do update set department_name=excluded.department_name,description=excluded.description,is_assignable=excluded.is_assignable;

insert into public.admin_permission_catalog (permission_key,department_key,permission_name,description,is_sensitive)
values
('logistics.view','logistics_transport','ডেলিভারি কাজ দেখা','Porter delivery jobs ও অগ্রগতি দেখা',false),
('logistics.assign','logistics_transport','ডেলিভারি কাজ বরাদ্দ','সক্রিয় Porter-কে ডেলিভারি কাজ বরাদ্দ ও পুনর্বণ্টন',true)
on conflict (permission_key) do update set department_key=excluded.department_key,permission_name=excluded.permission_name,description=excluded.description,is_sensitive=excluded.is_sensitive;

create table if not exists public.porter_delivery_jobs (
 id uuid primary key default gen_random_uuid(),
 job_code text not null unique default ('NXJ-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
 assigned_porter_id uuid not null references public.profiles(id),
 assigned_by uuid not null references public.profiles(id),
 source_reference text,
 package_description text not null check(length(btrim(package_description)) between 2 and 1000),
 package_count integer not null default 1 check(package_count>0),
 pickup_contact_name text,pickup_contact_phone text,
 pickup_address text not null check(length(btrim(pickup_address)) between 3 and 1000),
 pickup_city text not null,pickup_country text not null,
 dropoff_contact_name text,dropoff_contact_phone text,
 dropoff_address text not null check(length(btrim(dropoff_address)) between 3 and 1000),
 dropoff_city text not null,dropoff_country text not null,
 scheduled_pickup_at timestamptz,
 status text not null default 'assigned' check(status in ('assigned','accepted','pickup_in_progress','picked_up','in_transit','delivered','declined','failed','cancelled')),
 porter_note text check(porter_note is null or length(porter_note)<=2000),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 accepted_at timestamptz,picked_up_at timestamptz,delivered_at timestamptz
);
create index if not exists porter_delivery_jobs_assigned_status_created_idx on public.porter_delivery_jobs(assigned_porter_id,status,created_at desc);

create table if not exists public.porter_delivery_job_events (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.porter_delivery_jobs(id) on delete cascade,
 actor_id uuid not null references public.profiles(id),
 from_status text,
 to_status text not null check(to_status in ('assigned','accepted','pickup_in_progress','picked_up','in_transit','delivered','declined','failed','cancelled')),
 note text check(note is null or length(note)<=2000),
 created_at timestamptz not null default now()
);
create index if not exists porter_delivery_job_events_job_created_idx on public.porter_delivery_job_events(job_id,created_at desc);

alter table public.porter_delivery_jobs enable row level security;
alter table public.porter_delivery_job_events enable row level security;

drop policy if exists porter_jobs_active_account_gate on public.porter_delivery_jobs;
create policy porter_jobs_active_account_gate on public.porter_delivery_jobs as restrictive for all to authenticated
using((select private.is_active_nexora_user())) with check((select private.is_active_nexora_user()));

drop policy if exists porter_jobs_assigned_or_logistics_view on public.porter_delivery_jobs;
create policy porter_jobs_assigned_or_logistics_view on public.porter_delivery_jobs for select to authenticated
using(assigned_porter_id=(select auth.uid()) or (select private.has_nexora_permission('logistics.view')));

drop policy if exists porter_jobs_logistics_assign on public.porter_delivery_jobs;
create policy porter_jobs_logistics_assign on public.porter_delivery_jobs for insert to authenticated
with check(
 assigned_by=(select auth.uid()) and status='assigned'
 and (select private.has_nexora_permission('logistics.assign'))
 and exists(select 1 from public.profiles p where p.id=assigned_porter_id and p.role='porter' and p.account_status='active')
);

drop policy if exists porter_events_active_account_gate on public.porter_delivery_job_events;
create policy porter_events_active_account_gate on public.porter_delivery_job_events as restrictive for all to authenticated
using((select private.is_active_nexora_user())) with check((select private.is_active_nexora_user()));

drop policy if exists porter_events_assigned_or_logistics_view on public.porter_delivery_job_events;
create policy porter_events_assigned_or_logistics_view on public.porter_delivery_job_events for select to authenticated
using(
 exists(select 1 from public.porter_delivery_jobs j where j.id=job_id and j.assigned_porter_id=(select auth.uid()))
 or (select private.has_nexora_permission('logistics.view'))
);

grant select,insert on public.porter_delivery_jobs to authenticated;
grant select on public.porter_delivery_job_events to authenticated;
revoke update,delete on public.porter_delivery_jobs from anon,authenticated;
revoke insert,update,delete on public.porter_delivery_job_events from anon,authenticated;

create or replace function private.record_porter_job_assignment()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
 insert into public.porter_delivery_job_events(job_id,actor_id,from_status,to_status,note)
 values(new.id,new.assigned_by,null,'assigned','Delivery job assigned to Porter');
 return new;
end;
$function$;
revoke all on function private.record_porter_job_assignment() from public,anon,authenticated;
drop trigger if exists trg_record_porter_job_assignment on public.porter_delivery_jobs;
create trigger trg_record_porter_job_assignment after insert on public.porter_delivery_jobs
for each row execute function private.record_porter_job_assignment();

create or replace function private.porter_update_delivery_job_status(p_job_id uuid,p_new_status text,p_note text default null)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_job public.porter_delivery_jobs%rowtype;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 if p_new_status not in ('accepted','declined','pickup_in_progress','picked_up','in_transit','delivered','failed') then raise exception 'Invalid status target'; end if;
 if p_note is not null and length(p_note)>2000 then raise exception 'Note is too long'; end if;
 if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='porter' and p.account_status='active') then raise exception 'An active Porter account is required'; end if;
 select * into v_job from public.porter_delivery_jobs where id=p_job_id for update;
 if not found or v_job.assigned_porter_id<>v_uid then raise exception 'Delivery job not found or not assigned to this Porter'; end if;
 if not(
  (v_job.status='assigned' and p_new_status in ('accepted','declined'))
  or (v_job.status='accepted' and p_new_status='pickup_in_progress')
  or (v_job.status='pickup_in_progress' and p_new_status='picked_up')
  or (v_job.status='picked_up' and p_new_status='in_transit')
  or (v_job.status='in_transit' and p_new_status in ('delivered','failed'))
 ) then raise exception 'This status transition is not allowed'; end if;
 if p_new_status in ('declined','delivered','failed') and length(btrim(coalesce(p_note,'')))<5 then raise exception 'A note of at least 5 characters is required'; end if;
 update public.porter_delivery_jobs set status=p_new_status,porter_note=nullif(btrim(coalesce(p_note,'')),''),
  accepted_at=case when p_new_status='accepted' then now() else accepted_at end,
  picked_up_at=case when p_new_status='picked_up' then now() else picked_up_at end,
  delivered_at=case when p_new_status='delivered' then now() else delivered_at end,
  updated_at=now() where id=p_job_id;
 insert into public.porter_delivery_job_events(job_id,actor_id,from_status,to_status,note)
 values(p_job_id,v_uid,v_job.status,p_new_status,nullif(btrim(coalesce(p_note,'')),''));
 return p_job_id;
end;
$function$;
revoke all on function private.porter_update_delivery_job_status(uuid,text,text) from public,anon;
grant execute on function private.porter_update_delivery_job_status(uuid,text,text) to authenticated;

create or replace function public.porter_update_delivery_job_status(p_job_id uuid,p_new_status text,p_note text default null)
returns uuid language sql security invoker set search_path=''
as $function$ select private.porter_update_delivery_job_status(p_job_id,p_new_status,p_note); $function$;
revoke all on function public.porter_update_delivery_job_status(uuid,text,text) from public,anon;
grant execute on function public.porter_update_delivery_job_status(uuid,text,text) to authenticated;

comment on table public.porter_delivery_jobs is 'Private delivery assignments readable only by the assigned Porter and authorized logistics staff.';
comment on table public.porter_delivery_job_events is 'Append-only status history for Porter delivery assignments.';
