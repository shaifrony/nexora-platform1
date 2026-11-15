-- Bind managed NEXORA Team / Courier staff to existing verified NEXORA accounts.
-- Staff retain their existing Buyer/Seller/Porter role; no privileged public role is introduced.
-- Development branch staging only. Do not apply to hosted Supabase without release approval.
begin;

alter table public.delivery_network_staff
  add column if not exists auth_user_id uuid references public.profiles(id) on delete restrict;

create unique index if not exists delivery_network_staff_auth_user_uidx
  on public.delivery_network_staff(auth_user_id) where auth_user_id is not null;
create index if not exists delivery_network_staff_identity_queue_idx
  on public.delivery_network_staff(auth_user_id,staff_status,partner_id)
  where auth_user_id is not null;

create or replace function private.bind_delivery_network_staff_identity(p_staff_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_admin_code text;
  v_staff public.delivery_network_staff%rowtype;
  v_partner_status text;
  v_matches uuid[];
  v_user_id uuid;
begin
  if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  select s.admin_code into v_admin_code
  from public.admin_staff s join public.profiles p on p.id=s.user_id
  where s.user_id=v_actor and s.is_active=true
    and p.role='admin' and p.account_status='active';
  if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;

  select * into v_staff from public.delivery_network_staff where id=p_staff_id for update;
  if not found then raise exception 'Delivery staff record not found' using errcode='P0002'; end if;
  if v_staff.staff_status<>'active' then raise exception 'Only active delivery staff can be linked' using errcode='23514'; end if;
  select partner_status into v_partner_status
  from public.delivery_network_partners where id=v_staff.partner_id for share;
  if v_partner_status is distinct from 'approved' then
    raise exception 'Delivery partner must be approved before identity binding' using errcode='23514';
  end if;
  if v_staff.contact_email is null and v_staff.contact_phone is null then
    raise exception 'A verified staff email or phone is required' using errcode='22023';
  end if;

  -- Match only a confirmed Auth email or confirmed Auth phone. This avoids
  -- account enumeration and prevents an Admin from binding an unrelated account.
  select array_agg(candidate.id) into v_matches
  from (
    select distinct u.id
    from auth.users u
    join public.profiles p on p.id=u.id
    where p.account_status='active'
      and p.role in ('buyer','seller','porter')
      and (
        (v_staff.contact_email is not null
          and u.email_confirmed_at is not null
          and lower(btrim(coalesce(u.email,'')))=lower(btrim(v_staff.contact_email)))
        or
        (v_staff.contact_phone is not null
          and u.phone_confirmed_at is not null
          and regexp_replace(coalesce(u.phone,''),'[^0-9]','','g')
              =regexp_replace(v_staff.contact_phone,'[^0-9]','','g'))
      )
  ) candidate;

  if coalesce(cardinality(v_matches),0)<>1 then
    raise exception 'Exactly one active account with a verified matching staff email or phone is required' using errcode='22023';
  end if;
  v_user_id:=v_matches[1];
  if exists(select 1 from public.delivery_network_staff s
            where s.auth_user_id=v_user_id and s.id<>p_staff_id) then
    raise exception 'This account is already linked to another delivery staff record' using errcode='23505';
  end if;

  update public.delivery_network_staff set auth_user_id=v_user_id,updated_by=v_actor,updated_at=now()
  where id=p_staff_id;
  insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
  values(v_actor,v_admin_code,'delivery_network.staff_identity_bound','delivery_network_staff',p_staff_id::text,
    jsonb_build_object('partner_id',v_staff.partner_id,'identity_bound',true));
  return jsonb_build_object('staff_id',p_staff_id,'identity_bound',true);
end;
$$;

create or replace function private.unbind_delivery_network_staff_identity(p_staff_id uuid,p_reason text)
returns void
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_admin_code text;v_partner uuid;
begin
  if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  select s.admin_code into v_admin_code from public.admin_staff s join public.profiles p on p.id=s.user_id
  where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
  if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
  if length(btrim(coalesce(p_reason,'')))<5 or length(p_reason)>1000 then
    raise exception 'A reason of 5 to 1000 characters is required' using errcode='22023';
  end if;
  update public.delivery_network_staff set auth_user_id=null,updated_by=v_actor,updated_at=now()
  where id=p_staff_id and auth_user_id is not null returning partner_id into v_partner;
  if not found then raise exception 'Linked delivery staff identity not found' using errcode='P0002'; end if;
  insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details)
  values(v_actor,v_admin_code,'delivery_network.staff_identity_unbound','delivery_network_staff',p_staff_id::text,
    btrim(p_reason),jsonb_build_object('partner_id',v_partner,'identity_bound',false));
end;
$$;

-- Staff roster management supports both approved NEXORA teams and approved courier companies.
-- Changing the staff email/phone invalidates an existing identity link.
create or replace function private.upsert_delivery_network_staff(
  p_staff_id uuid,p_partner_id uuid,p_full_name text,p_contact_phone text,p_contact_email text,
  p_employment_type text,p_service_cities text[],p_vehicle_type text,p_staff_status text,p_admin_notes text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_admin_code text;v_partner_kind text;v_id uuid;
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
  if v_partner_kind is null or v_partner_kind not in ('nexora_team','courier_company') then
    raise exception 'Staff must belong to an approved NEXORA team or courier company' using errcode='23514';
  end if;
  if length(btrim(coalesce(p_full_name,''))) not between 2 and 160
     or length(btrim(coalesce(p_contact_phone,''))) not between 5 and 40
     or p_employment_type not in ('employee','contract')
     or p_staff_status not in ('active','inactive','suspended')
     or length(coalesce(p_admin_notes,''))>1500
     or (nullif(btrim(coalesce(p_contact_email,'')),'') is not null
         and length(btrim(p_contact_email))>254) then
    raise exception 'Invalid delivery staff details' using errcode='22023';
  end if;
  if p_staff_id is null then
    insert into public.delivery_network_staff(partner_id,full_name,contact_phone,contact_email,employment_type,
      service_cities,vehicle_type,staff_status,admin_notes,created_by,updated_by)
    values(p_partner_id,btrim(p_full_name),btrim(p_contact_phone),nullif(lower(btrim(coalesce(p_contact_email,''))),''),
      p_employment_type,coalesce(p_service_cities,'{}'),nullif(btrim(coalesce(p_vehicle_type,'')),''),
      p_staff_status,nullif(btrim(coalesce(p_admin_notes,'')),''),v_actor,v_actor)
    returning id into v_id;
  else
    update public.delivery_network_staff set partner_id=p_partner_id,full_name=btrim(p_full_name),
      auth_user_id=case
        when lower(coalesce(contact_email,'')) is distinct from lower(coalesce(nullif(btrim(coalesce(p_contact_email,'')),''),''))
          or regexp_replace(contact_phone,'[^0-9]','','g') is distinct from regexp_replace(btrim(p_contact_phone),'[^0-9]','','g')
        then null else auth_user_id end,
      contact_phone=btrim(p_contact_phone),contact_email=nullif(lower(btrim(coalesce(p_contact_email,''))),''),
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

-- A selected field worker must have a unique, active, verified login identity.
create or replace function private.assign_delivery_job_network(
 p_job_id uuid,p_assignment_source text,p_provider_id uuid,p_partner_id uuid,
 p_staff_id uuid,p_vehicle_id uuid,p_reason text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_admin_code text;v_status text;
 v_provider_status text;v_partner_kind text;v_partner_status text;v_staff_partner uuid;v_staff_user uuid;
 v_vehicle_status text;v_vehicle_provider uuid;v_vehicle_available boolean;
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
     select approval_status,provider_id,is_available into v_vehicle_status,v_vehicle_provider,v_vehicle_available from public.transport_vehicles where id=p_vehicle_id for update;
     if v_vehicle_status is distinct from 'approved' or v_vehicle_provider is distinct from p_provider_id or v_vehicle_available is distinct from true then
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
     select s.partner_id,s.auth_user_id into v_staff_partner,v_staff_user
     from public.delivery_network_staff s join public.profiles worker on worker.id=s.auth_user_id
     where s.id=p_staff_id and s.staff_status='active' and worker.account_status='active'
       and worker.role in ('buyer','seller','porter')
     for update of s,worker;
     if v_staff_partner is distinct from p_partner_id or v_staff_user is null then
       raise exception 'Assigned field staff must be active, identity-bound, and belong to the selected partner' using errcode='23514';
     end if;
   end if;
 else raise exception 'Unsupported assignment source' using errcode='22023';
 end if;
 if p_vehicle_id is not null and exists(
   select 1 from public.delivery_jobs j
   where j.assigned_vehicle_id=p_vehicle_id and j.id<>p_job_id
     and j.job_status in ('requested','assigned','accepted','picked_up','in_transit','out_for_delivery','partially_delivered','disputed')
 ) then
   raise exception 'Selected Vehicle already has another active Delivery Job' using errcode='23514';
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

create or replace function private.get_my_assigned_staff_receipt_jobs()
returns table(job_id uuid,job_reference text,job_status text,partner_name text)
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if not exists(select 1 from public.profiles p where p.id=v_actor
   and p.role in ('buyer','seller','porter') and p.account_status='active') then
   raise exception 'Active staff account required' using errcode='42501';
 end if;
 return query
 select j.id,j.job_reference,j.job_status,dp.display_name
 from public.delivery_jobs j
 join public.delivery_network_staff s on s.id=j.assigned_staff_id
 join public.delivery_network_partners dp on dp.id=s.partner_id
 where s.auth_user_id=v_actor and s.staff_status='active'
   and dp.partner_status='approved'
   and j.assignment_source in ('nexora_team','courier_partner')
   and j.job_status in ('out_for_delivery','partially_delivered')
 order by j.updated_at desc limit 100;
end;
$$;

create or replace function private.verify_delivery_receipt_code(
 p_job_id uuid,p_code text,p_location_description text default null,p_note text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_admin_code text;v_owner uuid;v_old text;
 v_challenge private.delivery_receipt_challenges%rowtype;v_actor_type text;
 v_staff_id uuid;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if length(coalesce(p_code,''))<>32 or p_code !~ '^[0-9A-Fa-f]{32}$'
    or length(coalesce(p_location_description,''))>500
    or length(coalesce(p_note,''))>1500 then
   raise exception 'Invalid receipt verification input' using errcode='22023';
 end if;
 select job_status into v_old from public.delivery_jobs where id=p_job_id for update;
 if not found then return jsonb_build_object('verified',false,'reason','no_active_challenge'); end if;

 if private.has_nexora_permission('logistics.assign') then
   if (select auth.jwt()->>'aal') is distinct from 'aal2' then
     raise exception 'Admin MFA (AAL2) is required' using errcode='42501';
   end if;
   select s.admin_code into v_admin_code from public.admin_staff s join public.profiles p on p.id=s.user_id
    where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
   if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
   v_actor_type:='admin';
 else
   select tp.owner_user_id into v_owner
   from public.delivery_jobs j join public.transport_providers tp on tp.id=j.assigned_provider_id
   join public.profiles owner_profile on owner_profile.id=tp.owner_user_id
   where j.id=p_job_id and tp.application_status='approved'
     and owner_profile.account_status='active' and tp.owner_user_id=v_actor
   for share of tp,owner_profile;
   if v_owner is not distinct from v_actor then
     v_actor_type:='independent_provider';
   else
     select s.id into v_staff_id
     from public.delivery_jobs j
     join public.delivery_network_staff s on s.id=j.assigned_staff_id
     join public.delivery_network_partners dp on dp.id=s.partner_id
     join public.profiles worker on worker.id=s.auth_user_id
     where j.id=p_job_id and s.auth_user_id=v_actor and s.staff_status='active'
       and dp.partner_status='approved' and worker.account_status='active'
       and worker.role in ('buyer','seller','porter')
       and j.assignment_source in ('nexora_team','courier_partner')
     for share of s,dp,worker;
     if v_staff_id is null then
       raise exception 'Only the assigned active Provider owner or identity-bound staff member can verify this receipt' using errcode='42501';
     end if;
     v_actor_type:='delivery_staff';
   end if;
 end if;

 select * into v_challenge from private.delivery_receipt_challenges c
 where c.job_id=p_job_id and c.consumed_at is null
 order by c.created_at desc limit 1 for update;
 if not found then return jsonb_build_object('verified',false,'reason','no_active_challenge'); end if;
 if v_old not in ('out_for_delivery','partially_delivered') then
   raise exception 'Shipment is not awaiting receipt confirmation' using errcode='22023';
 end if;
 if v_challenge.expires_at<=now() then
   update private.delivery_receipt_challenges set consumed_at=now() where id=v_challenge.id;
   return jsonb_build_object('verified',false,'reason','expired');
 end if;
 if v_challenge.attempts>=5 then
   update private.delivery_receipt_challenges set consumed_at=now() where id=v_challenge.id;
   return jsonb_build_object('verified',false,'reason','attempt_limit');
 end if;
 if v_challenge.code_hash<>encode(extensions.digest(upper(p_code)||p_job_id::text||v_challenge.buyer_id::text||'NEXORA-RECEIPT-V1','sha256'),'hex') then
   update private.delivery_receipt_challenges set attempts=attempts+1,
     consumed_at=case when attempts+1>=5 then now() else null end
   where id=v_challenge.id;
   return jsonb_build_object('verified',false,'attempts_remaining',greatest(0,4-v_challenge.attempts));
 end if;
 update private.delivery_receipt_challenges set consumed_at=now(),verified_at=now() where id=v_challenge.id;
 update public.delivery_jobs set job_status='delivered',updated_at=now() where id=p_job_id;
 update private.delivery_receipt_challenges set verified_at=null where id=v_challenge.id;
 insert into public.delivery_tracking_events(job_id,previous_status,new_status,location_description,note,
   external_tracking_code,actor_user_id,actor_type)
 values(p_job_id,v_old,'delivered',nullif(btrim(coalesce(p_location_description,'')),''),
   nullif(btrim(coalesce(p_note,'')),''),null,v_actor,v_actor_type);
 if v_actor_type='admin' then
   insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
   values(v_actor,v_admin_code,'delivery_job.receipt_verified','delivery_job',p_job_id::text,
     jsonb_build_object('previous_status',v_old,'new_status','delivered','verification','buyer_otp'));
 end if;
 return jsonb_build_object('verified',true,'job_id',p_job_id,'previous_status',v_old,'status','delivered',
   'verified_by',v_actor_type);
end;
$$;

create or replace function public.bind_delivery_network_staff_identity(p_staff_id uuid)
returns jsonb language sql security invoker set search_path=''
as $$ select private.bind_delivery_network_staff_identity($1); $$;
create or replace function public.unbind_delivery_network_staff_identity(p_staff_id uuid,p_reason text)
returns void language sql security invoker set search_path=''
as $$ select private.unbind_delivery_network_staff_identity($1,$2); $$;
create or replace function public.get_my_assigned_staff_receipt_jobs()
returns table(job_id uuid,job_reference text,job_status text,partner_name text)
language sql security invoker set search_path=''
as $$ select * from private.get_my_assigned_staff_receipt_jobs(); $$;
create or replace function public.verify_delivery_receipt_code(
 p_job_id uuid,p_code text,p_location_description text default null,p_note text default null
) returns jsonb language sql security invoker set search_path=''
as $$ select private.verify_delivery_receipt_code($1,$2,$3,$4); $$;
create or replace function public.upsert_delivery_network_staff(
 p_staff_id uuid,p_partner_id uuid,p_full_name text,p_contact_phone text,p_contact_email text,
 p_employment_type text,p_service_cities text[],p_vehicle_type text,p_staff_status text,p_admin_notes text
) returns uuid language sql security invoker set search_path=''
as $$ select private.upsert_delivery_network_staff($1,$2,$3,$4,$5,$6,$7,$8,$9,$10); $$;
create or replace function public.assign_delivery_job_network(
 p_job_id uuid,p_assignment_source text,p_provider_id uuid default null,p_partner_id uuid default null,
 p_staff_id uuid default null,p_vehicle_id uuid default null,p_reason text default null
) returns jsonb language sql security invoker set search_path=''
as $$ select private.assign_delivery_job_network($1,$2,$3,$4,$5,$6,$7); $$;

revoke all on function private.bind_delivery_network_staff_identity(uuid) from public,anon,authenticated;
revoke all on function private.unbind_delivery_network_staff_identity(uuid,text) from public,anon,authenticated;
revoke all on function private.get_my_assigned_staff_receipt_jobs() from public,anon,authenticated;
revoke all on function private.verify_delivery_receipt_code(uuid,text,text,text) from public,anon,authenticated;
revoke all on function private.upsert_delivery_network_staff(uuid,uuid,text,text,text,text,text[],text,text,text) from public,anon,authenticated;
revoke all on function private.assign_delivery_job_network(uuid,text,uuid,uuid,uuid,uuid,text) from public,anon,authenticated;

revoke all on function public.bind_delivery_network_staff_identity(uuid) from public,anon;
revoke all on function public.unbind_delivery_network_staff_identity(uuid,text) from public,anon;
revoke all on function public.get_my_assigned_staff_receipt_jobs() from public,anon;
revoke all on function public.verify_delivery_receipt_code(uuid,text,text,text) from public,anon;
revoke all on function public.upsert_delivery_network_staff(uuid,uuid,text,text,text,text,text[],text,text,text) from public,anon;
revoke all on function public.assign_delivery_job_network(uuid,text,uuid,uuid,uuid,uuid,text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.bind_delivery_network_staff_identity(uuid) to authenticated;
grant execute on function private.unbind_delivery_network_staff_identity(uuid,text) to authenticated;
grant execute on function private.get_my_assigned_staff_receipt_jobs() to authenticated;
grant execute on function private.verify_delivery_receipt_code(uuid,text,text,text) to authenticated;
grant execute on function private.upsert_delivery_network_staff(uuid,uuid,text,text,text,text,text[],text,text,text) to authenticated;
grant execute on function private.assign_delivery_job_network(uuid,text,uuid,uuid,uuid,uuid,text) to authenticated;
grant execute on function public.bind_delivery_network_staff_identity(uuid) to authenticated;
grant execute on function public.unbind_delivery_network_staff_identity(uuid,text) to authenticated;
grant execute on function public.get_my_assigned_staff_receipt_jobs() to authenticated;
grant execute on function public.verify_delivery_receipt_code(uuid,text,text,text) to authenticated;
grant execute on function public.upsert_delivery_network_staff(uuid,uuid,text,text,text,text,text[],text,text,text) to authenticated;
grant execute on function public.assign_delivery_job_network(uuid,text,uuid,uuid,uuid,uuid,text) to authenticated;

comment on column public.delivery_network_staff.auth_user_id is
 'Unique identity link to an existing active Buyer/Seller/Porter profile; set only by verified-contact Admin RPC. Never a new public role.';
comment on function public.bind_delivery_network_staff_identity(uuid) is
 'AAL2 logistics Admin binds one staff roster record to exactly one active account with a confirmed matching Auth email or phone.';
comment on function public.get_my_assigned_staff_receipt_jobs() is
 'Returns only receipt-eligible jobs assigned to the authenticated active identity-bound NEXORA Team or approved courier worker.';

commit;
