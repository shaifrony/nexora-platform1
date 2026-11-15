\set ON_ERROR_STOP on
\pset pager off

do $block$ begin create role anon nologin; exception when duplicate_object then null; end $block$;
do $block$ begin create role authenticated nologin; exception when duplicate_object then null; end $block$;
create schema if not exists auth;
create schema if not exists private;
create schema if not exists extensions;
grant usage on schema private to authenticated;
create or replace function auth.uid() returns uuid language sql stable set search_path=''
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable set search_path=''
as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb) $$;
create or replace function private.has_nexora_permission(text) returns boolean
language sql stable set search_path='' as $$ select false $$;

create table public.profiles(id uuid primary key,role text not null,account_status text not null);
create table public.commerce_orders(id uuid primary key,buyer_id uuid not null references public.profiles(id));
create table public.transport_providers(id uuid primary key,owner_user_id uuid not null,application_status text not null default 'approved');
create table public.admin_staff(user_id uuid primary key,admin_code text,is_active boolean);
create table public.admin_audit_logs(actor_user_id uuid,actor_admin_code text,action_key text,target_type text,target_id text,details jsonb);
create table public.delivery_jobs(
 id uuid primary key,job_reference text not null,commerce_order_id uuid references public.commerce_orders(id),
 job_status text not null,assigned_provider_id uuid references public.transport_providers(id),updated_at timestamptz default now()
);
create table public.delivery_tracking_events(
 id bigint generated always as identity primary key,job_id uuid not null references public.delivery_jobs(id),
 previous_status text,new_status text not null,location_description text,note text,external_tracking_code text,
 actor_user_id uuid not null,actor_type text not null,created_at timestamptz default now()
);

-- A legacy implementation and public wrapper simulate the previously deployed RPC contract.
create function private.update_delivery_network_job_status(uuid,text,text,text,text)
returns jsonb language sql security definer set search_path=''
as $$ select jsonb_build_object('status',$2) $$;
grant execute on function private.update_delivery_network_job_status(uuid,text,text,text,text) to authenticated;
create function public.update_delivery_network_job_status(p_job_id uuid,p_next_status text,p_location_description text default null,p_note text default null,p_external_tracking_code text default null)
returns jsonb language sql security invoker set search_path=''
as $legacy_public$ select private.update_delivery_network_job_status($1,$2,$3,$4,$5) $legacy_public$;
grant execute on function public.update_delivery_network_job_status(uuid,text,text,text,text) to authenticated;

\ir ../supabase/migrations/20261115140000_buyer_delivery_receipt_otp.sql
\ir ../supabase/migrations/20261115150000_receipt_otp_work_queues.sql
\ir ../supabase/migrations/20261115160000_receipt_otp_sha256_provider_guard.sql

insert into public.profiles values
 ('71000000-0000-4000-8000-000000000001','buyer','active'),
 ('71000000-0000-4000-8000-000000000002','buyer','active'),
 ('71000000-0000-4000-8000-000000000011','porter','active');
insert into public.commerce_orders values
 ('72000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001'),
 ('72000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000002');
insert into public.transport_providers values
 ('73000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000011');
insert into public.delivery_jobs(id,job_reference,commerce_order_id,job_status,assigned_provider_id) values
 ('74000000-0000-4000-8000-000000000001','NXD-OTP-OWN','72000000-0000-4000-8000-000000000001','out_for_delivery','73000000-0000-4000-8000-000000000001'),
 ('74000000-0000-4000-8000-000000000002','NXD-OTP-OTHER','72000000-0000-4000-8000-000000000002','out_for_delivery','73000000-0000-4000-8000-000000000001');

-- Buyer receipt queue exposes only the authenticated Buyer's own shipment identifiers.
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',false);
do $buyer_queue$ begin
 if (select count(*) from public.get_my_order_receipt_jobs(array['72000000-0000-4000-8000-000000000001'::uuid]))<>1 then
  raise exception 'FAIL: Buyer receipt queue did not return own shipment';
 end if;
 if (select count(*) from public.get_my_order_receipt_jobs(array['72000000-0000-4000-8000-000000000002'::uuid]))<>0 then
  raise exception 'FAIL: Buyer receipt queue exposed another Buyer shipment';
 end if;
end $buyer_queue$;
reset role;
-- Only the owner of an approved assigned independent Provider sees its receipt queue.
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $provider_queue$ begin
 if (select count(*) from public.get_my_assigned_receipt_jobs())<>2 then
  raise exception 'FAIL: assigned Provider queue did not return its eligible shipments';
 end if;
end $provider_queue$;
reset role;

-- Direct table writes cannot mark a shipment delivered without a verified challenge.
do $block$ begin
 begin
  update public.delivery_jobs set job_status='delivered'
   where id='74000000-0000-4000-8000-000000000001';
  raise exception 'FAIL: direct delivery_jobs update bypassed receipt proof';
 exception when insufficient_privilege then null;
 end;
end $block$;

-- Only the owning active Buyer can request a code, and raw code is not stored.
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',false);
create temporary table otp_result as
 select public.request_delivery_receipt_code('74000000-0000-4000-8000-000000000001') as payload;
do $block$ begin
 if (select length(payload->>'code') from otp_result)<>32 or (select payload->>'code' !~ '^[0-9A-F]{32}$' from otp_result) then raise exception 'FAIL: Buyer did not receive a 32-character hexadecimal OTP'; end if;
 if (select length(code_hash) from private.delivery_receipt_challenges limit 1)<>64 then raise exception 'FAIL: OTP digest is not SHA-256'; end if;
end $block$;
reset role;
do $block$ begin
 if (select code_hash from private.delivery_receipt_challenges limit 1)=(select payload->>'code' from otp_result) then
   raise exception 'FAIL: raw OTP was stored';
 end if;
end $block$;
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',false);
do $block$ begin
 perform public.request_delivery_receipt_code('74000000-0000-4000-8000-000000000002');
 raise exception 'FAIL: unrelated Buyer requested another Buyer shipment OTP';
exception when insufficient_privilege then null; end $block$;
reset role;

-- The old status RPC cannot bypass receipt verification, and its renamed implementation is private.
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $block$ begin
 perform public.update_delivery_network_job_status(
  '74000000-0000-4000-8000-000000000001','delivered',null,null,null
 );
 raise exception 'FAIL: legacy public status RPC bypassed OTP';
exception when insufficient_privilege then null; end $block$;
do $block$ begin
 if has_function_privilege('authenticated','private.update_delivery_network_job_status_legacy(uuid,text,text,text,text)','EXECUTE') then
  raise exception 'FAIL: authenticated can execute renamed legacy transition function';
 end if;
end $block$;
reset role;

-- Provider eligibility is re-checked at verification time, not only when the queue loads.
update public.profiles set account_status='suspended'
where id='71000000-0000-4000-8000-000000000011';
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $inactive_provider$ begin
 begin
  perform public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001',repeat('A',32),null,null);
  raise exception 'FAIL: inactive Provider verified a receipt';
 exception when insufficient_privilege then null;
 end;
end $inactive_provider$;
reset role;
update public.profiles set account_status='active'
where id='71000000-0000-4000-8000-000000000011';
update public.transport_providers set application_status='suspended'
where id='73000000-0000-4000-8000-000000000001';
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $provider_queue_suspended$ begin
 if (select count(*) from public.get_my_assigned_receipt_jobs())<>0 then
  raise exception 'FAIL: suspended Provider still sees receipt queue';
 end if;
end $provider_queue_suspended$;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $unapproved_provider$ begin
 begin
  perform public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001',repeat('A',32),null,null);
  raise exception 'FAIL: unapproved Provider verified a receipt';
 exception when insufficient_privilege then null;
 end;
end $unapproved_provider$;
reset role;
update public.transport_providers set application_status='approved'
where id='73000000-0000-4000-8000-000000000001';

-- The assigned Provider verifies the Buyer code once; wrong codes consume attempts.
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $wrong$
declare v jsonb; i integer;
begin
 for i in 1..4 loop
  v:=public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001','00000000000000000000000000000000');
  if coalesce((v->>'verified')::boolean,true) then raise exception 'FAIL: wrong OTP verified'; end if;
 end loop;
end
$wrong$;
reset role;

-- Use a fresh challenge after cooldown simulation, then verify success and one-time consumption.
update private.delivery_receipt_challenges set created_at=now()-interval '2 minutes',consumed_at=now()
where job_id='74000000-0000-4000-8000-000000000001';
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',false);
create temporary table otp_result_2 as
 select public.request_delivery_receipt_code('74000000-0000-4000-8000-000000000001') as payload;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $success$
declare v_code text; v_result jsonb;
begin
 select payload->>'code' into v_code from otp_result_2;
 v_result:=public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001',v_code,null,'Buyer receipt verified');
 if (v_result->>'verified')::boolean is distinct from true then raise exception 'FAIL: valid OTP did not verify'; end if;
 v_result:=public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001',v_code,null,null);
 if coalesce((v_result->>'verified')::boolean,false) then raise exception 'FAIL: OTP was reusable'; end if;
end
$success$;
reset role;
do $assert_delivered$ begin
 if (select job_status from public.delivery_jobs where id='74000000-0000-4000-8000-000000000001')<>'delivered' then
  raise exception 'FAIL: successful OTP did not set delivered status';
 end if;
end $assert_delivered$;

\echo 'PASS: Buyer ownership, private OTP storage, rate/attempt controls, legacy bypass denial, assigned Provider verification and one-time receipt confirmation'
 from otp_result) then raise exception 'FAIL: Buyer did not receive a 32-character hexadecimal OTP'; end if;
 if (select length(code_hash) from private.delivery_receipt_challenges limit 1)<>64 then raise exception 'FAIL: OTP digest is not SHA-256'; end if;
end $block$;
reset role;
do $block$ begin
 if (select code_hash from private.delivery_receipt_challenges limit 1)=(select payload->>'code' from otp_result) then
   raise exception 'FAIL: raw OTP was stored';
 end if;
end $block$;
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',false);
do $block$ begin
 perform public.request_delivery_receipt_code('74000000-0000-4000-8000-000000000002');
 raise exception 'FAIL: unrelated Buyer requested another Buyer shipment OTP';
exception when insufficient_privilege then null; end $block$;
reset role;

-- The old status RPC cannot bypass receipt verification, and its renamed implementation is private.
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $block$ begin
 perform public.update_delivery_network_job_status(
  '74000000-0000-4000-8000-000000000001','delivered',null,null,null
 );
 raise exception 'FAIL: legacy public status RPC bypassed OTP';
exception when insufficient_privilege then null; end $block$;
do $block$ begin
 if has_function_privilege('authenticated','private.update_delivery_network_job_status_legacy(uuid,text,text,text,text)','EXECUTE') then
  raise exception 'FAIL: authenticated can execute renamed legacy transition function';
 end if;
end $block$;
reset role;

-- Provider eligibility is re-checked at verification time, not only when the queue loads.
update public.profiles set account_status='suspended'
where id='71000000-0000-4000-8000-000000000011';
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $inactive_provider$ begin
 begin
  perform public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001',repeat('A',32),null,null);
  raise exception 'FAIL: inactive Provider verified a receipt';
 exception when insufficient_privilege then null;
 end;
end $inactive_provider$;
reset role;
update public.profiles set account_status='active'
where id='71000000-0000-4000-8000-000000000011';
update public.transport_providers set application_status='suspended'
where id='73000000-0000-4000-8000-000000000001';
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $unapproved_provider$ begin
 begin
  perform public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001',repeat('A',32),null,null);
  raise exception 'FAIL: unapproved Provider verified a receipt';
 exception when insufficient_privilege then null;
 end;
end $unapproved_provider$;
reset role;
update public.transport_providers set application_status='approved'
where id='73000000-0000-4000-8000-000000000001';

-- The assigned Provider verifies the Buyer code once; wrong codes consume attempts.
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $wrong$
declare v jsonb; i integer;
begin
 for i in 1..4 loop
  v:=public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001','00000000000000000000000000000000');
  if coalesce((v->>'verified')::boolean,true) then raise exception 'FAIL: wrong OTP verified'; end if;
 end loop;
end
$wrong$;
reset role;

-- Use a fresh challenge after cooldown simulation, then verify success and one-time consumption.
update private.delivery_receipt_challenges set created_at=now()-interval '2 minutes',consumed_at=now()
where job_id='74000000-0000-4000-8000-000000000001';
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',false);
create temporary table otp_result_2 as
 select public.request_delivery_receipt_code('74000000-0000-4000-8000-000000000001') as payload;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000011',false);
do $success$
declare v_code text; v_result jsonb;
begin
 select payload->>'code' into v_code from otp_result_2;
 v_result:=public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001',v_code,null,'Buyer receipt verified');
 if (v_result->>'verified')::boolean is distinct from true then raise exception 'FAIL: valid OTP did not verify'; end if;
 v_result:=public.verify_delivery_receipt_code('74000000-0000-4000-8000-000000000001',v_code,null,null);
 if coalesce((v_result->>'verified')::boolean,false) then raise exception 'FAIL: OTP was reusable'; end if;
end
$success$;
reset role;
do $assert_delivered$ begin
 if (select job_status from public.delivery_jobs where id='74000000-0000-4000-8000-000000000001')<>'delivered' then
  raise exception 'FAIL: successful OTP did not set delivered status';
 end if;
end $assert_delivered$;

\echo 'PASS: Buyer ownership, private OTP storage, rate/attempt controls, legacy bypass denial, assigned Provider verification and one-time receipt confirmation'
