\set ON_ERROR_STOP on
\pset pager off

do $roles$ begin create role anon nologin; exception when duplicate_object then null; end $roles$;
do $roles$ begin create role authenticated nologin; exception when duplicate_object then null; end $roles$;
create schema if not exists auth;
create schema if not exists private;
create schema if not exists storage;
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
 commerce_order_id uuid,assigned_staff_id uuid,assignment_source text,created_at timestamptz default now(),updated_at timestamptz default now()
);
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
insert into public.delivery_jobs values
 ('a5000000-0000-4000-8000-000000000001','NXD-OPS-01','assigned','a2000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','nexora_team',now()),
 ('a5000000-0000-4000-8000-000000000002','NXD-OPS-02','assigned','a2000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000002','nexora_team',now());

\ir ../supabase/migrations/20261115190000_delivery_staff_status_proof_partial_and_disputes.sql

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
