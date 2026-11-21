-- NEXORA delivery tracking events and guarded operational status transitions.
-- Staged only. Delivered does not itself complete the Commerce Order.
begin;

create table if not exists public.delivery_tracking_events (
 id bigint generated always as identity primary key,
 job_id uuid not null references public.delivery_jobs(id) on delete restrict,
 previous_status text,
 new_status text not null check(new_status in ('assigned','accepted','picked_up','in_transit','out_for_delivery','delivered','delivery_failed','partially_delivered','disputed','returned','cancelled')),
 location_description text,
 note text,
 external_tracking_code text,
 actor_user_id uuid not null references public.profiles(id) on delete restrict,
 actor_type text not null check(actor_type in ('admin','independent_provider')),
 created_at timestamptz not null default now(),
 check(length(coalesce(location_description,''))<=500),
 check(length(coalesce(note,''))<=1500),
 check(length(coalesce(external_tracking_code,''))<=160)
);
create index if not exists delivery_tracking_events_job_idx
 on public.delivery_tracking_events(job_id,created_at desc);
alter table public.delivery_tracking_events enable row level security;
revoke all on public.delivery_tracking_events from public,anon,authenticated;
grant select on public.delivery_tracking_events to authenticated;
create policy delivery_tracking_events_admin_read on public.delivery_tracking_events
 for select to authenticated using(private.has_nexora_permission('logistics.view'));
create policy delivery_tracking_events_provider_read on public.delivery_tracking_events
 for select to authenticated using(exists(
   select 1 from public.delivery_jobs j join public.transport_providers p on p.id=j.assigned_provider_id
   where j.id=job_id and p.owner_user_id=(select auth.uid())
 ));

create or replace function private.update_delivery_network_job_status(
 p_job_id uuid,p_next_status text,p_location_description text,p_note text,p_external_tracking_code text
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_admin_code text;v_old text;v_provider_owner uuid;v_actor_type text;
 v_allowed boolean:=false;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if private.has_nexora_permission('logistics.assign') then
   if (select auth.jwt()->>'aal') is distinct from 'aal2' then
     raise exception 'Admin MFA (AAL2) is required' using errcode='42501';
   end if;
   select s.admin_code into v_admin_code from public.admin_staff s join public.profiles p on p.id=s.user_id
    where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
   if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
   v_actor_type:='admin';
 else
   select tp.owner_user_id into v_provider_owner from public.delivery_jobs j
    join public.transport_providers tp on tp.id=j.assigned_provider_id
    where j.id=p_job_id;
   if v_provider_owner is distinct from v_actor then raise exception 'Only assigned Provider or authorized Admin can update this job' using errcode='42501'; end if;
   v_actor_type:='independent_provider';
 end if;
 select job_status into v_old from public.delivery_jobs where id=p_job_id for update;
 if not found then raise exception 'Delivery Job not found' using errcode='P0002'; end if;
 if p_next_status not in ('accepted','picked_up','in_transit','out_for_delivery','delivered','delivery_failed','partially_delivered','disputed','returned') then
   raise exception 'Unsupported delivery status' using errcode='22023';
 end if;
 v_allowed := case v_old
  when 'assigned' then p_next_status in ('accepted','delivery_failed')
  when 'accepted' then p_next_status in ('picked_up','delivery_failed')
  when 'picked_up' then p_next_status in ('in_transit','partially_delivered','delivery_failed')
  when 'in_transit' then p_next_status in ('out_for_delivery','partially_delivered','delivery_failed')
  when 'out_for_delivery' then p_next_status in ('delivered','partially_delivered','delivery_failed')
  when 'partially_delivered' then p_next_status in ('in_transit','out_for_delivery','delivered','disputed')
  when 'delivered' then p_next_status='disputed'
  when 'delivery_failed' then p_next_status='returned'
  when 'disputed' then p_next_status in ('delivered','returned')
  else false end;
 if not v_allowed then raise exception 'Invalid delivery status transition: % -> %',v_old,p_next_status using errcode='22023'; end if;
 if length(coalesce(p_location_description,''))>500 or length(coalesce(p_note,''))>1500
    or length(coalesce(p_external_tracking_code,''))>160 then
   raise exception 'Tracking details exceed allowed length' using errcode='22023';
 end if;
 update public.delivery_jobs set job_status=p_next_status,updated_at=now() where id=p_job_id;
 insert into public.delivery_tracking_events(job_id,previous_status,new_status,location_description,note,
   external_tracking_code,actor_user_id,actor_type)
 values(p_job_id,v_old,p_next_status,nullif(btrim(coalesce(p_location_description,'')),''),
   nullif(btrim(coalesce(p_note,'')),''),nullif(btrim(coalesce(p_external_tracking_code,'')),''),v_actor,v_actor_type);
 if v_actor_type='admin' then
   insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
   values(v_actor,v_admin_code,'delivery_job.status_updated','delivery_job',p_job_id::text,
     jsonb_build_object('previous_status',v_old,'new_status',p_next_status));
 end if;
 return jsonb_build_object('job_id',p_job_id,'previous_status',v_old,'status',p_next_status,'actor_type',v_actor_type);
end;
$$;
revoke all on function private.update_delivery_network_job_status(uuid,text,text,text,text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.update_delivery_network_job_status(uuid,text,text,text,text) to authenticated;
create or replace function public.update_delivery_network_job_status(
 p_job_id uuid,p_next_status text,p_location_description text default null,p_note text default null,p_external_tracking_code text default null
) returns jsonb language sql security invoker set search_path=''
as $$ select private.update_delivery_network_job_status($1,$2,$3,$4,$5); $$;
revoke all on function public.update_delivery_network_job_status(uuid,text,text,text,text) from public,anon;
grant execute on function public.update_delivery_network_job_status(uuid,text,text,text,text) to authenticated;

comment on table public.delivery_tracking_events is 'Append-only tracking history. A delivered scan is not Commerce Order completion.';
commit;
