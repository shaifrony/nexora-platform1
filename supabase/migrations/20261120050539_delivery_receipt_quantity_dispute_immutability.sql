-- Close Buyer receipt OTP quantity, replay, dispute and immutability gaps.
-- Forward-only Development migration; never apply to hosted Supabase without release approval.
begin;

create table if not exists private.delivery_receipt_confirmations (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.delivery_jobs(id) on delete restrict,
  commerce_order_id uuid not null references public.commerce_orders(id) on delete restrict,
  challenge_id uuid not null unique references private.delivery_receipt_challenges(id) on delete restrict,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  verified_by uuid not null references public.profiles(id) on delete restrict,
  verifier_actor_type text not null check (verifier_actor_type in ('admin','independent_provider')),
  confirmed_quantity numeric(14,3) not null check (confirmed_quantity > 0),
  verified_at timestamptz not null default now(),
  unique (job_id)
);

create index if not exists delivery_receipt_confirmations_order_idx
  on private.delivery_receipt_confirmations(commerce_order_id, verified_at desc);

revoke all on private.delivery_receipt_confirmations from public, anon, authenticated;

create or replace function private.reject_delivery_receipt_confirmation_mutation()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Delivery receipt confirmations are immutable' using errcode='42501';
end;
$$;
revoke all on function private.reject_delivery_receipt_confirmation_mutation() from public, anon, authenticated;

drop trigger if exists delivery_receipt_confirmations_immutable on private.delivery_receipt_confirmations;
create trigger delivery_receipt_confirmations_immutable
before update or delete on private.delivery_receipt_confirmations
for each row execute function private.reject_delivery_receipt_confirmation_mutation();

create or replace function private.invalidate_delivery_receipt_challenges_after_proof()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  update private.delivery_receipt_challenges
     set consumed_at=coalesce(consumed_at, now()), verified_at=null
   where job_id=new.job_id and consumed_at is null;
  return new;
end;
$$;
revoke all on function private.invalidate_delivery_receipt_challenges_after_proof() from public, anon, authenticated;

drop trigger if exists delivery_proof_invalidates_receipt_challenges on private.delivery_proof_records;
create trigger delivery_proof_invalidates_receipt_challenges
after insert on private.delivery_proof_records
for each row execute function private.invalidate_delivery_receipt_challenges_after_proof();

create or replace function private.reject_proof_after_delivery_completion()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if exists (
    select 1 from public.delivery_jobs j
     where j.id=new.job_id and j.job_status='delivered'
  ) then
    raise exception 'Delivery proof cannot be added after receipt completion' using errcode='22023';
  end if;
  return new;
end;
$$;
revoke all on function private.reject_proof_after_delivery_completion() from public, anon, authenticated;

drop trigger if exists delivery_proof_reject_after_completion on private.delivery_proof_records;
create trigger delivery_proof_reject_after_completion
before insert on private.delivery_proof_records
for each row execute function private.reject_proof_after_delivery_completion();

create or replace function private.request_delivery_receipt_code(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_order_id uuid;
  v_order_quantity numeric;
  v_delivered_quantity numeric;
  v_job_status text;
  v_code text;
  v_challenge_id uuid;
begin
  if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
  if not exists (
    select 1 from public.profiles p
     where p.id=v_actor and p.role='buyer' and p.account_status='active'
  ) then
    raise exception 'Active Buyer account required' using errcode='42501';
  end if;

  select j.commerce_order_id, j.job_status, o.quantity
    into v_order_id, v_job_status, v_order_quantity
    from public.delivery_jobs j
    join public.commerce_orders o on o.id=j.commerce_order_id
   where j.id=p_job_id and o.buyer_id=v_actor
   for update of j;

  if not found or v_order_id is null then
    raise exception 'Only your own Order-linked shipment can request a receipt code' using errcode='42501';
  end if;
  if v_job_status not in ('out_for_delivery','partially_delivered') then
    raise exception 'Shipment is not eligible for receipt verification' using errcode='22023';
  end if;
  if exists (
    select 1 from private.delivery_disputes d
     where d.job_id=p_job_id and d.dispute_status in ('open','under_review')
  ) then
    raise exception 'An active delivery dispute blocks receipt verification' using errcode='P0001';
  end if;

  select coalesce(sum(r.delivered_quantity),0)
    into v_delivered_quantity
    from private.delivery_proof_records r
   where r.job_id=p_job_id;

  if v_delivered_quantity > v_order_quantity then
    raise exception 'Recorded delivery quantity exceeds the Order quantity' using errcode='22023';
  end if;
  if v_job_status='partially_delivered' and v_delivered_quantity < v_order_quantity then
    raise exception 'The complete Order quantity must be proven before requesting the final receipt code' using errcode='22023';
  end if;
  if v_job_status='out_for_delivery' and v_delivered_quantity > 0
     and v_delivered_quantity < v_order_quantity then
    raise exception 'Partial delivery requires a fresh receipt code only after the remaining quantity is proven' using errcode='22023';
  end if;

  if exists (
    select 1 from private.delivery_receipt_challenges c
     where c.job_id=p_job_id and c.buyer_id=v_actor and c.consumed_at is null
       and c.created_at>now()-interval '60 seconds'
  ) then
    raise exception 'Please wait before requesting another receipt code' using errcode='P0001';
  end if;

  update private.delivery_receipt_challenges
     set consumed_at=coalesce(consumed_at,now()), verified_at=null
   where job_id=p_job_id and buyer_id=v_actor and consumed_at is null;

  v_code:=upper(encode(extensions.gen_random_bytes(16),'hex'));
  insert into private.delivery_receipt_challenges(job_id,commerce_order_id,buyer_id,code_hash,expires_at)
  values (
    p_job_id, v_order_id, v_actor,
    encode(extensions.digest(v_code||p_job_id::text||v_actor::text||'NEXORA-RECEIPT-V1','sha256'),'hex'),
    now()+interval '10 minutes'
  )
  returning id into v_challenge_id;

  return jsonb_build_object('challenge_id',v_challenge_id,'code',v_code,'expires_in_seconds',600);
end;
$$;

create or replace function private.verify_delivery_receipt_code(
  p_job_id uuid,p_code text,p_location_description text default null,p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_admin_code text;
  v_owner uuid;
  v_old text;
  v_order_id uuid;
  v_buyer_id uuid;
  v_order_quantity numeric;
  v_delivered_quantity numeric;
  v_challenge private.delivery_receipt_challenges%rowtype;
  v_actor_type text;
begin
  if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
  if length(coalesce(p_code,''))<>32
     or p_code !~ '^[0-9A-Fa-f]{32}$'
     or length(coalesce(p_location_description,''))>500
     or length(coalesce(p_note,''))>1500 then
    raise exception 'Invalid receipt verification input' using errcode='22023';
  end if;

  select j.job_status,j.commerce_order_id,o.buyer_id,o.quantity
    into v_old,v_order_id,v_buyer_id,v_order_quantity
    from public.delivery_jobs j
    join public.commerce_orders o on o.id=j.commerce_order_id
   where j.id=p_job_id
   for update of j;

  if not found or v_order_id is null then
    raise exception 'Order-linked Delivery Job not found' using errcode='P0002';
  end if;
  if v_old not in ('out_for_delivery','partially_delivered') then
    raise exception 'Shipment is not awaiting receipt confirmation' using errcode='22023';
  end if;

  if private.has_nexora_permission('logistics.assign') then
    if (select auth.jwt()->>'aal') is distinct from 'aal2' then
      raise exception 'Admin MFA (AAL2) is required' using errcode='42501';
    end if;
    select s.admin_code into v_admin_code
      from public.admin_staff s
      join public.profiles p on p.id=s.user_id
     where s.user_id=v_actor and s.is_active=true
       and p.role='admin' and p.account_status='active';
    if v_admin_code is null then
      raise exception 'Active Admin membership required' using errcode='42501';
    end if;
    v_actor_type:='admin';
  else
    select tp.owner_user_id into v_owner
      from public.delivery_jobs j
      join public.transport_providers tp on tp.id=j.assigned_provider_id
      join public.profiles owner_profile on owner_profile.id=tp.owner_user_id
     where j.id=p_job_id and tp.application_status='approved'
       and owner_profile.account_status='active'
       and tp.owner_user_id=v_actor
     for share of tp, owner_profile;
    if v_owner is distinct from v_actor then
      raise exception 'Only the active owner of the approved assigned Provider or authorized Admin can verify receipt' using errcode='42501';
    end if;
    v_actor_type:='independent_provider';
  end if;

  if exists (
    select 1 from private.delivery_disputes d
     where d.job_id=p_job_id and d.dispute_status in ('open','under_review')
  ) then
    raise exception 'An active delivery dispute blocks receipt verification' using errcode='P0001';
  end if;

  select coalesce(sum(r.delivered_quantity),0)
    into v_delivered_quantity
    from private.delivery_proof_records r
   where r.job_id=p_job_id;
  if v_delivered_quantity < v_order_quantity then
    raise exception 'Receipt cannot complete until the full Order quantity is proven' using errcode='22023';
  end if;
  if v_delivered_quantity > v_order_quantity then
    raise exception 'Recorded delivery quantity exceeds the Order quantity' using errcode='22023';
  end if;

  select * into v_challenge
    from private.delivery_receipt_challenges c
   where c.job_id=p_job_id and c.buyer_id=v_buyer_id
     and c.commerce_order_id=v_order_id and c.consumed_at is null
   order by c.created_at desc
   limit 1
   for update;

  if not found then
    return jsonb_build_object('verified',false,'reason','no_active_challenge');
  end if;
  if v_challenge.expires_at<=now() then
    update private.delivery_receipt_challenges set consumed_at=now() where id=v_challenge.id;
    return jsonb_build_object('verified',false,'reason','expired');
  end if;
  if v_challenge.attempts>=5 then
    update private.delivery_receipt_challenges set consumed_at=now() where id=v_challenge.id;
    return jsonb_build_object('verified',false,'reason','attempt_limit');
  end if;
  if v_challenge.code_hash<>encode(
    extensions.digest(upper(p_code)||p_job_id::text||v_challenge.buyer_id::text||'NEXORA-RECEIPT-V1','sha256'),
    'hex'
  ) then
    update private.delivery_receipt_challenges
       set attempts=attempts+1,
           consumed_at=case when attempts+1>=5 then now() else null end
     where id=v_challenge.id;
    return jsonb_build_object('verified',false,'attempts_remaining',greatest(0,4-v_challenge.attempts));
  end if;

  insert into private.delivery_receipt_confirmations(
    job_id,commerce_order_id,challenge_id,buyer_id,verified_by,verifier_actor_type,confirmed_quantity
  ) values (
    p_job_id,v_order_id,v_challenge.id,v_buyer_id,v_actor,v_actor_type,v_delivered_quantity
  );

  update private.delivery_receipt_challenges
     set consumed_at=now(),verified_at=now()
   where id=v_challenge.id;
  update public.delivery_jobs
     set job_status='delivered',updated_at=now()
   where id=p_job_id;
  update private.delivery_receipt_challenges
     set verified_at=null
   where id=v_challenge.id;

  insert into public.delivery_tracking_events(
    job_id,previous_status,new_status,location_description,note,
    external_tracking_code,actor_user_id,actor_type
  ) values (
    p_job_id,v_old,'delivered',
    nullif(btrim(coalesce(p_location_description,'')),''),
    nullif(btrim(coalesce(p_note,'')),''),
    null,v_actor,v_actor_type
  );

  if v_actor_type='admin' then
    insert into public.admin_audit_logs(
      actor_user_id,actor_admin_code,action_key,target_type,target_id,details
    ) values (
      v_actor,v_admin_code,'delivery_job.receipt_verified','delivery_job',p_job_id::text,
      jsonb_build_object(
        'previous_status',v_old,'new_status','delivered',
        'verification','buyer_otp','receipt_confirmation_id',
        (select id from private.delivery_receipt_confirmations where job_id=p_job_id)
      )
    );
  end if;

  return jsonb_build_object(
    'verified',true,'job_id',p_job_id,'previous_status',v_old,'status','delivered',
    'confirmed_quantity',v_delivered_quantity
  );
end;
$$;

comment on table private.delivery_receipt_confirmations is
  'Append-only evidence that the Buyer receipt OTP was verified after all ordered quantity was proven.';
comment on function private.request_delivery_receipt_code(uuid) is
  'Issues a fresh one-time Buyer receipt code only when the shipment is eligible and any partial quantity is fully proven.';
comment on function private.verify_delivery_receipt_code(uuid,text,text,text) is
  'Verifies a one-time Buyer receipt code only for full proven quantity and no active delivery dispute; stores immutable receipt confirmation.';

commit;
