\set ON_ERROR_STOP on
\pset pager off

do $roles$ begin create role anon nologin; exception when duplicate_object then null; end $roles$;
do $roles$ begin create role authenticated nologin; exception when duplicate_object then null; end $roles$;
create schema if not exists auth;
create schema if not exists private;
create schema if not exists storage;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create or replace function auth.uid() returns uuid language sql stable set search_path=''
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable set search_path=''
as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb) $$;
create or replace function private.has_nexora_permission(p text) returns boolean language sql stable set search_path=''
as $$ select coalesce(current_setting('test.admin.permission',true),'false')='true' $$;

create table public.profiles(id uuid primary key,role text not null,account_status text not null,full_name text);
create table public.admin_staff(user_id uuid primary key,admin_code text,is_active boolean);
create table public.admin_audit_logs(actor_user_id uuid,actor_admin_code text,action_key text,target_type text,target_id text,reason text,details jsonb);
create table public.commerce_orders(id uuid primary key,buyer_id uuid not null,seller_id uuid not null,quantity numeric not null);
create table public.delivery_network_partners(id uuid primary key,partner_status text not null,display_name text not null);
create table public.delivery_network_staff(id uuid primary key,partner_id uuid not null,auth_user_id uuid,staff_status text not null);
create table public.delivery_jobs(
 id uuid primary key,job_reference text not null,job_status text not null,
 commerce_order_id uuid,assigned_staff_id uuid,assignment_source text,created_at timestamptz default now(),updated_at timestamptz default now(),assigned_provider_id uuid
);
create table public.transport_providers(id uuid primary key,owner_user_id uuid not null,application_status text not null);
create table public.delivery_tracking_events(
 id bigint generated always as identity primary key,job_id uuid,previous_status text,new_status text,
 location_description text,note text,external_tracking_code text,actor_user_id uuid,actor_type text,
 created_at timestamptz default now(),constraint delivery_tracking_events_actor_type_check
 check(actor_type in ('admin','independent_provider'))
);
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text not null,name text not null,unique(bucket_id,name));

insert into public.profiles values
 ('a1000000-0000-4000-8000-000000000001','buyer','active','Buyer One'),
 ('a1000000-0000-4000-8000-000000000002','seller','active','Seller One'),
 ('a1000000-0000-4000-8000-000000000003','porter','active','Worker One'),
 ('a1000000-0000-4000-8000-000000000004','porter','active','Worker Two'),
 ('a1000000-0000-4000-8000-000000000005','admin','active','Admin One');
insert into public.admin_staff values('a1000000-0000-4000-8000-000000000005','ADM-OPS-TEST',true);
insert into public.commerce_orders values
 ('a2000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002',10);
insert into public.delivery_network_partners values
 ('a3000000-0000-4000-8000-000000000001','approved','NEXORA Dhaka');
insert into public.delivery_network_staff values
 ('a4000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003','active'),
 ('a4000000-0000-4000-8000-000000000002','a3000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000004','active');
insert into public.delivery_jobs(id,job_reference,job_status,commerce_order_id,assigned_staff_id,assignment_source,created_at) values
 ('a5000000-0000-4000-8000-000000000001','NXD-OPS-01','assigned','a2000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','nexora_team',now()),
 ('a5000000-0000-4000-8000-000000000002','NXD-OPS-02','assigned','a2000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000002','nexora_team',now());

\ir ../supabase/migrations/20261115190000_delivery_staff_status_proof_partial_and_disputes.sql

create table private.delivery_receipt_challenges (
 id uuid primary key default gen_random_uuid(),job_id uuid not null references public.delivery_jobs(id),
 commerce_order_id uuid not null references public.commerce_orders(id),buyer_id uuid not null references public.profiles(id),
 code_hash text not null,attempts integer not null default 0,created_at timestamptz not null default now(),
 expires_at timestamptz not null,consumed_at timestamptz,verified_at timestamptz
);
insert into public.transport_providers values
 ('a6000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003','approved');
\ir ../supabase/migrations/20261120050539_delivery_receipt_quantity_dispute_immutability.sql

grant usage on schema private to authenticated;

-- Assigned worker can advance only their own job through permitted statuses.
set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',false);
select set_config('request.jwt.claims','{}',false);
select public.update_my_delivery_job_status('a5000000-0000-4000-8000-000000000001','accepted',null,'Accepted dispatch');
select public.update_my_delivery_job_status('a5000000-0000-4000-8000-000000000001','picked_up',null,'Collected parcel');
select public.update_my_delivery_job_status('a5000000-0000-4000-8000-000000000001','in_transit',null,'On route');
select public.update_my_delivery_job_status('a5000000-0000-4000-8000-000000000001','out_for_delivery',null,'Near destination');

do $wrong_worker$ begin
 begin
  perform public.update_my_delivery_job_status('a5000000-0000-4000-8000-000000000002','accepted',null,null);
  raise exception 'FAIL: worker updated another worker job';
 exception when insufficient_privilege then null;
 end;
end $wrong_worker$;
do $no_direct_delivery$ begin
 begin
  perform public.update_my_delivery_job_status('a5000000-0000-4000-8000-000000000001','delivered',null,null);
  raise exception 'FAIL: worker bypassed Buyer receipt OTP to mark delivered';
 exception when check_violation or invalid_parameter_value then null;
 end;
end $no_direct_delivery$;
reset role;

-- Simulate successful private uploads. Paths must be in this job folder.
insert into storage.objects(bucket_id,name) values
 ('nexora-delivery-evidence','a5000000-0000-4000-8000-000000000001/photo-1.jpg'),
 ('nexora-delivery-evidence','a5000000-0000-4000-8000-000000000001/signature.png');

set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',false);
select set_config('request.jwt.claims','{}',false);
select public.record_delivery_proof(
 'a5000000-0000-4000-8000-000000000001',3,1,'Receiver One',true,
 array['a5000000-0000-4000-8000-000000000001/photo-1.jpg'],
 'a5000000-0000-4000-8000-000000000001/signature.png','Three units handed over'
);
reset role;
do $partial$ begin
 if (select job_status from public.delivery_jobs where id='a5000000-0000-4000-8000-000000000001')<>'partially_delivered' then
  raise exception 'FAIL: partial proof did not set partially_delivered';
 end if;
 if (select sum(delivered_quantity) from private.delivery_proof_records where job_id='a5000000-0000-4000-8000-000000000001')<>3 then
  raise exception 'FAIL: partial quantity proof not persisted';
 end if;
end $partial$;

-- A second proof cannot make cumulative delivered quantity exceed the order quantity.
set role authenticated;
do $over_delivery$ begin
 begin
  perform public.record_delivery_proof(
   'a5000000-0000-4000-8000-000000000001',8,1,'Receiver One',true,
   array['a5000000-0000-4000-8000-000000000001/photo-1.jpg'],null,'Excess quantity attempt'
  );
  raise exception 'FAIL: cumulative delivered quantity exceeded ordered quantity';
 exception when invalid_parameter_value then null;
 end;
end $over_delivery$;
reset role;

-- Buyer can open a dispute on their own order; another Buyer cannot.
set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{}',false);
select public.raise_delivery_dispute('a5000000-0000-4000-8000-000000000001','quantity_mismatch','Only three of ten units were received.');
reset role;
do $own_dispute$ begin
 if (select count(*) from private.delivery_disputes where job_id='a5000000-0000-4000-8000-000000000001' and raiser_role='buyer')<>1 then
  raise exception 'FAIL: Buyer dispute not recorded';
 end if;
 if (select job_status from public.delivery_jobs where id='a5000000-0000-4000-8000-000000000001')<>'disputed' then
  raise exception 'FAIL: dispute did not set operational status disputed';
 end if;
end $own_dispute$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000004',false);
select set_config('request.jwt.claims','{}',false);
do $foreign_dispute$ begin
 begin
  perform public.raise_delivery_dispute('a5000000-0000-4000-8000-000000000001','other','This user is not part of the order.');
  raise exception 'FAIL: unrelated user raised a dispute';
 exception when insufficient_privilege then null;
 end;
end $foreign_dispute$;
reset role;

-- Only active AAL2 logistics Admin can review and close disputes.
set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000005',false);
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
select set_config('test.admin.permission','true',false);
reset role;
select id as dispute_id from private.delivery_disputes where job_id='a5000000-0000-4000-8000-000000000001' \gset
set role authenticated;
do $admin_queue$ begin
 if (select count(*) from public.get_admin_delivery_disputes())<>1 then
  raise exception 'FAIL: AAL2 Admin dispute queue did not return the open dispute';
 end if;
end $admin_queue$;
select public.review_delivery_dispute(
 :'dispute_id'::uuid,
 'resolved','Seller will deliver the remaining seven units within the agreed window.'
);
reset role;

-- Buyer and Seller receive evidence/dispute history only through their own Order IDs.
set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{}',false);
do $buyer_order_ops$ begin
 if (select count(*) from public.get_my_order_delivery_operations(array['a2000000-0000-4000-8000-000000000001']::uuid[]))<>2 then
  raise exception 'FAIL: Buyer order-scoped delivery operations missing';
 end if;
end $buyer_order_ops$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',false);
select set_config('request.jwt.claims','{}',false);
do $seller_order_ops$ begin
 if (select count(*) from public.get_my_order_delivery_operations(array['a2000000-0000-4000-8000-000000000001']::uuid[]))<>2 then
  raise exception 'FAIL: Seller order-scoped delivery operations missing';
 end if;
end $seller_order_ops$;
reset role;

do $audit$ begin
 if (select dispute_status from private.delivery_disputes where job_id='a5000000-0000-4000-8000-000000000001')<>'resolved' then
  raise exception 'FAIL: Admin resolution not saved';
 end if;
 if (select count(*) from public.admin_audit_logs where action_key='delivery_dispute.reviewed')<>1 then
  raise exception 'FAIL: dispute review audit event missing';
 end if;
 if (select count(*) from public.delivery_tracking_events where actor_type='delivery_staff')<4 then
  raise exception 'FAIL: worker status events not attributed to delivery_staff';
 end if;
end $audit$;

\echo 'PASS: identity-bound worker status updates, no direct delivered bypass, private photo/signature proof, partial quantity ceiling, Buyer ownership dispute and AAL2 Admin resolution'

-- Receipt OTP can never close a partial quantity. A proof update consumes the old code.
create temp table receipt_test_codes(code_key text primary key,code text not null);
grant select,insert on receipt_test_codes to authenticated;
insert into public.delivery_jobs(id,job_reference,job_status,commerce_order_id,assigned_staff_id,assignment_source,assigned_provider_id)
values('a5000000-0000-4000-8000-000000000003','NXD-RECEIPT-03','out_for_delivery',
 'a2000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','nexora_team',
 'a6000000-0000-4000-8000-000000000001');

set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{}',false);
insert into receipt_test_codes values('stale',(private.request_delivery_receipt_code('a5000000-0000-4000-8000-000000000003')->>'code'));
reset role;

update public.delivery_jobs set job_status='partially_delivered'
 where id='a5000000-0000-4000-8000-000000000003';
insert into private.delivery_proof_records(job_id,commerce_order_id,delivered_quantity,created_by,actor_type)
values('a5000000-0000-4000-8000-000000000003','a2000000-0000-4000-8000-000000000001',3,
 'a1000000-0000-4000-8000-000000000003','delivery_staff');

set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',false);
do $partial_receipt_block$ begin
 begin
  perform private.request_delivery_receipt_code('a5000000-0000-4000-8000-000000000003');
  raise exception 'FAIL: receipt code was issued for only 3/10 units';
 exception when sqlstate '22023' then null;
 end;
end $partial_receipt_block$;
reset role;

insert into private.delivery_proof_records(job_id,commerce_order_id,delivered_quantity,created_by,actor_type)
values('a5000000-0000-4000-8000-000000000003','a2000000-0000-4000-8000-000000000001',7,
 'a1000000-0000-4000-8000-000000000003','delivery_staff');

set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',false);
insert into receipt_test_codes values('fresh',(private.request_delivery_receipt_code('a5000000-0000-4000-8000-000000000003')->>'code'));
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',false);
select set_config('request.jwt.claims','{}',false);
do $receipt_replay$ declare v_result jsonb; v_stale text; v_fresh text; begin
 select code into v_stale from pg_temp.receipt_test_codes where code_key='stale';
 select code into v_fresh from pg_temp.receipt_test_codes where code_key='fresh';
 v_result:=private.verify_delivery_receipt_code(
  'a5000000-0000-4000-8000-000000000003', v_stale);
 if coalesce((v_result->>'verified')::boolean,false) then
  raise exception 'FAIL: stale pre-partial OTP was accepted';
 end if;
 v_result:=private.verify_delivery_receipt_code(
  'a5000000-0000-4000-8000-000000000003', v_fresh);
 if not coalesce((v_result->>'verified')::boolean,false) then
  raise exception 'FAIL: fresh OTP did not confirm fully proven 10/10 quantity';
 end if;
end $receipt_replay$;
reset role;

do $receipt_immutable$ begin
 if (select confirmed_quantity from private.delivery_receipt_confirmations
      where job_id='a5000000-0000-4000-8000-000000000003')<>10 then
  raise exception 'FAIL: immutable receipt did not retain confirmed quantity 10';
 end if;
 begin
  update private.delivery_receipt_confirmations set confirmed_quantity=3
   where job_id='a5000000-0000-4000-8000-000000000003';
  raise exception 'FAIL: receipt confirmation update was allowed';
 exception when insufficient_privilege then null;
 end;
 begin
  delete from private.delivery_receipt_confirmations
   where job_id='a5000000-0000-4000-8000-000000000003';
  raise exception 'FAIL: receipt confirmation delete was allowed';
 exception when insufficient_privilege then null;
 end;
 begin
  insert into private.delivery_proof_records(job_id,commerce_order_id,delivered_quantity,created_by,actor_type)
  values('a5000000-0000-4000-8000-000000000003','a2000000-0000-4000-8000-000000000001',1,
   'a1000000-0000-4000-8000-000000000003','delivery_staff');
  raise exception 'FAIL: proof was accepted after delivery completion';
 exception when sqlstate '22023' then null;
 end;
end $receipt_immutable$;

-- An active dispute must block OTP verification even when all quantity is proven.
insert into public.delivery_jobs(id,job_reference,job_status,commerce_order_id,assigned_staff_id,assignment_source,assigned_provider_id)
values('a5000000-0000-4000-8000-000000000004','NXD-RECEIPT-04','out_for_delivery',
 'a2000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','nexora_team',
 'a6000000-0000-4000-8000-000000000001');
insert into private.delivery_proof_records(job_id,commerce_order_id,delivered_quantity,created_by,actor_type)
values('a5000000-0000-4000-8000-000000000004','a2000000-0000-4000-8000-000000000001',10,
 'a1000000-0000-4000-8000-000000000003','delivery_staff');
set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',false);
insert into receipt_test_codes values('disputed',(private.request_delivery_receipt_code('a5000000-0000-4000-8000-000000000004')->>'code'));
reset role;
insert into private.delivery_disputes(job_id,commerce_order_id,raised_by,raiser_role,reason_code,description)
values('a5000000-0000-4000-8000-000000000004','a2000000-0000-4000-8000-000000000001',
 'a1000000-0000-4000-8000-000000000001','buyer','quantity_mismatch','The delivered quantity is being disputed.');
set role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',false);
do $active_dispute_receipt_block$ declare v_disputed text; begin
 select code into v_disputed from pg_temp.receipt_test_codes where code_key='disputed';
 begin
  perform private.verify_delivery_receipt_code(
   'a5000000-0000-4000-8000-000000000004', v_disputed);
  raise exception 'FAIL: active dispute did not block receipt verification';
 exception when sqlstate 'P0001' then null;
 end;
end $active_dispute_receipt_block$;
reset role;

\echo 'PASS: partial quantity cannot close; partial proof invalidates stale OTP; fresh full-quantity OTP creates immutable receipt; active dispute and post-delivery proof are blocked'
