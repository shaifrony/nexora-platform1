-- NEXORA transport provider and vehicle Admin review workflow.
-- Staged migration only. Do not apply to hosted DB without explicit approval.
begin;

create or replace function private.review_transport_provider(
  p_provider_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_admin_code text;
  v_old_status text;
  v_new_status text;
begin
  if v_actor is null
     or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Insufficient privilege: active Admin MFA and logistics.assign are required'
      using errcode='42501';
  end if;

  if p_action not in ('approve','reject','suspend') then
    raise exception 'Unsupported provider review action' using errcode='22023';
  end if;
  if p_action in ('reject','suspend') and length(btrim(coalesce(p_reason,''))) < 5 then
    raise exception 'A review reason of at least 5 characters is required'
      using errcode='22023';
  end if;
  if length(coalesce(p_reason,'')) > 1000 then
    raise exception 'Review reason is too long' using errcode='22023';
  end if;

  select s.admin_code into v_admin_code
  from public.admin_staff s
  join public.profiles p on p.id=s.user_id
  where s.user_id=v_actor and s.is_active=true
    and p.role='admin' and p.account_status='active';

  if v_admin_code is null then
    raise exception 'Active Admin membership required' using errcode='42501';
  end if;

  select application_status into v_old_status
  from public.transport_providers
  where id=p_provider_id
  for update;

  if not found then
    raise exception 'Transport Provider not found' using errcode='P0002';
  end if;

  v_new_status := case p_action
    when 'approve' then 'approved'
    when 'reject' then 'rejected'
    when 'suspend' then 'suspended'
  end;

  if v_old_status = v_new_status then
    raise exception 'Provider already has this status' using errcode='22023';
  end if;
  if v_old_status = 'suspended' and p_action = 'suspend' then
    raise exception 'Provider is already suspended' using errcode='22023';
  end if;
  if v_old_status = 'approved' and p_action = 'reject' then
    raise exception 'Suspend an approved Provider instead of rejecting it' using errcode='22023';
  end if;

  update public.transport_providers
  set application_status=v_new_status,
      admin_note=nullif(btrim(coalesce(p_reason,'')),''),
      reviewed_by=v_actor,
      reviewed_at=now(),
      updated_at=now()
  where id=p_provider_id;

  insert into public.admin_audit_logs(
    actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details
  ) values (
    v_actor,v_admin_code,'transport_provider.'||p_action,
    'transport_provider',p_provider_id::text,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object('previous_status',v_old_status,'new_status',v_new_status)
  );

  return jsonb_build_object('provider_id',p_provider_id,'previous_status',v_old_status,'status',v_new_status);
end;
$$;

create or replace function private.review_transport_vehicle(
  p_vehicle_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_admin_code text;
  v_old_status text;
  v_new_status text;
  v_provider_id uuid;
  v_provider_status text;
begin
  if v_actor is null
     or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Insufficient privilege: active Admin MFA and logistics.assign are required'
      using errcode='42501';
  end if;

  if p_action not in ('approve','reject','suspend') then
    raise exception 'Unsupported vehicle review action' using errcode='22023';
  end if;
  if p_action in ('reject','suspend') and length(btrim(coalesce(p_reason,''))) < 5 then
    raise exception 'A review reason of at least 5 characters is required'
      using errcode='22023';
  end if;
  if length(coalesce(p_reason,'')) > 1000 then
    raise exception 'Review reason is too long' using errcode='22023';
  end if;

  select s.admin_code into v_admin_code
  from public.admin_staff s
  join public.profiles p on p.id=s.user_id
  where s.user_id=v_actor and s.is_active=true
    and p.role='admin' and p.account_status='active';

  if v_admin_code is null then
    raise exception 'Active Admin membership required' using errcode='42501';
  end if;

  select approval_status,provider_id into v_old_status,v_provider_id
  from public.transport_vehicles
  where id=p_vehicle_id
  for update;

  if not found then
    raise exception 'Transport Vehicle not found' using errcode='P0002';
  end if;

  select application_status into v_provider_status
  from public.transport_providers
  where id=v_provider_id
  for update;

  if p_action='approve' and v_provider_status is distinct from 'approved' then
    raise exception 'Approve the parent Provider before approving its vehicle'
      using errcode='23514';
  end if;

  v_new_status := case p_action
    when 'approve' then 'approved'
    when 'reject' then 'rejected'
    when 'suspend' then 'suspended'
  end;

  if v_old_status = v_new_status then
    raise exception 'Vehicle already has this status' using errcode='22023';
  end if;
  if v_old_status = 'approved' and p_action = 'reject' then
    raise exception 'Suspend an approved Vehicle instead of rejecting it' using errcode='22023';
  end if;

  update public.transport_vehicles
  set approval_status=v_new_status,
      admin_note=nullif(btrim(coalesce(p_reason,'')),''),
      reviewed_by=v_actor,
      reviewed_at=now(),
      updated_at=now()
  where id=p_vehicle_id;

  insert into public.admin_audit_logs(
    actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details
  ) values (
    v_actor,v_admin_code,'transport_vehicle.'||p_action,
    'transport_vehicle',p_vehicle_id::text,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'previous_status',v_old_status,'new_status',v_new_status,
      'provider_id',v_provider_id,'provider_status',v_provider_status
    )
  );

  return jsonb_build_object('vehicle_id',p_vehicle_id,'provider_id',v_provider_id,
    'previous_status',v_old_status,'status',v_new_status);
end;
$$;

revoke all on function private.review_transport_provider(uuid,text,text) from public,anon;
revoke all on function private.review_transport_vehicle(uuid,text,text) from public,anon;
grant execute on function private.review_transport_provider(uuid,text,text) to authenticated;
grant execute on function private.review_transport_vehicle(uuid,text,text) to authenticated;

commit;
