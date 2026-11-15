-- Harden receipt OTP hashing and re-check Provider eligibility at verification time.
-- Development branch staging only; no hosted database mutation.
begin;

create extension if not exists pgcrypto with schema extensions;

-- The preceding foundation migration used a 32-character MD5 column constraint.
-- Invalidate short-lived legacy MD5 challenges before enforcing 64-character digests.
delete from private.delivery_receipt_challenges where length(code_hash)<>64;
-- Replace it before writing SHA-256 digests (64 hex characters).
alter table private.delivery_receipt_challenges
  drop constraint if exists delivery_receipt_challenges_code_hash_check;
alter table private.delivery_receipt_challenges
  add constraint delivery_receipt_challenges_code_hash_check
  check (length(code_hash)=64);

create or replace function private.request_delivery_receipt_code(p_job_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid(); v_order_id uuid; v_code text; v_challenge_id uuid;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if not exists(select 1 from public.profiles p where p.id=v_actor and p.role='buyer' and p.account_status='active') then
   raise exception 'Active Buyer account required' using errcode='42501';
 end if;
 select j.commerce_order_id into v_order_id
 from public.delivery_jobs j join public.commerce_orders o on o.id=j.commerce_order_id
 where j.id=p_job_id and o.buyer_id=v_actor and j.job_status='out_for_delivery'
 for update of j;
 if not found or v_order_id is null then
   raise exception 'Only your own out-for-delivery shipment can request a receipt code' using errcode='42501';
 end if;
 if exists(select 1 from private.delivery_receipt_challenges c
   where c.job_id=p_job_id and c.buyer_id=v_actor and c.created_at>now()-interval '60 seconds') then
   raise exception 'Please wait before requesting another receipt code' using errcode='P0001';
 end if;
 update private.delivery_receipt_challenges set consumed_at=coalesce(consumed_at,now())
 where job_id=p_job_id and buyer_id=v_actor and consumed_at is null;
 v_code:=upper(encode(extensions.gen_random_bytes(16),'hex'));
 insert into private.delivery_receipt_challenges(job_id,commerce_order_id,buyer_id,code_hash,expires_at)
 values(p_job_id,v_order_id,v_actor,
   encode(extensions.digest(v_code||p_job_id::text||v_actor::text||'NEXORA-RECEIPT-V1','sha256'),'hex'),
   now()+interval '10 minutes')
 returning id into v_challenge_id;
 return jsonb_build_object('challenge_id',v_challenge_id,'code',v_code,'expires_in_seconds',600);
end;
$$;

create or replace function private.verify_delivery_receipt_code(
 p_job_id uuid,p_code text,p_location_description text default null,p_note text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid(); v_admin_code text; v_owner uuid; v_old text;
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
 select job_status into v_old from public.delivery_jobs where id=p_job_id for update;
 if v_old not in ('out_for_delivery','partially_delivered') then
   raise exception 'Shipment is not awaiting receipt confirmation' using errcode='22023';
 end if;
 select * into v_challenge from private.delivery_receipt_challenges c
 where c.job_id=p_job_id and c.consumed_at is null
 order by c.created_at desc limit 1 for update;
 if not found then return jsonb_build_object('verified',false,'reason','no_active_challenge'); end if;
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
 return jsonb_build_object('verified',true,'job_id',p_job_id,'previous_status',v_old,'status','delivered');
end;
$$;

comment on table private.delivery_receipt_challenges is
 'Private one-time Buyer receipt challenges. Only a SHA-256 digest of the high-entropy code bound to the shipment and Buyer is stored; raw OTP is never stored.';
comment on column private.delivery_receipt_challenges.code_hash is
 '64-character SHA-256 digest of the one-time code combined with the job and Buyer identifiers; raw OTP is never stored.';
commit;

    or length(coalesce(p_location_description,''))>500
    or length(coalesce(p_note,''))>1500 then
   raise exception 'Invalid receipt verification input' using errcode='22023';
 end if;
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
   from public.delivery_jobs j
   join public.transport_providers tp on tp.id=j.assigned_provider_id
   join public.profiles owner_profile on owner_profile.id=tp.owner_user_id
   where j.id=p_job_id and tp.application_status='approved'
     and owner_profile.account_status='active'
     and tp.owner_user_id=v_actor;
   if v_owner is distinct from v_actor then
     raise exception 'Only the active owner of the approved assigned Provider or authorized Admin can verify receipt' using errcode='42501';
   end if;
   v_actor_type:='independent_provider';
 end if;
 select * into v_challenge from private.delivery_receipt_challenges c
 where c.job_id=p_job_id and c.consumed_at is null
 order by c.created_at desc limit 1 for update;
 if not found then return jsonb_build_object('verified',false,'reason','no_active_challenge'); end if;
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
 select job_status into v_old from public.delivery_jobs where id=p_job_id for update;
 if v_old not in ('out_for_delivery','partially_delivered') then
   raise exception 'Shipment is not awaiting receipt confirmation' using errcode='22023';
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
 return jsonb_build_object('verified',true,'job_id',p_job_id,'previous_status',v_old,'status','delivered');
end;
$$;

comment on column private.delivery_receipt_challenges.code_hash is
 'SHA-256 digest of the one-time code combined with the job and Buyer identifiers; raw OTP is never stored.';
commit;
