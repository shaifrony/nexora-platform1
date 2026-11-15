\set ON_ERROR_STOP on
\pset pager off

do $block$ begin create role anon nologin; exception when duplicate_object then null; end $block$;
do $block$ begin create role authenticated nologin; exception when duplicate_object then null; end $block$;
create schema if not exists auth;
create schema if not exists private;
create or replace function auth.uid() returns uuid language sql stable set search_path=''
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable set search_path=''
as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb) $$;
create or replace function private.has_nexora_permission(text) returns boolean
language sql stable set search_path=''
as $$ select coalesce(current_setting('test.admin.permission',true),'false')='true' $$;

create table public.profiles(
 id uuid primary key, role text not null, account_status text not null, full_name text
);
create table public.admin_staff(user_id uuid primary key,admin_code text,is_active boolean);
create table public.commerce_orders(
 id uuid primary key,order_code text not null,listing_type text not null,listing_id uuid not null,
 buyer_id uuid not null references public.profiles(id),seller_id uuid not null references public.profiles(id),
 quantity numeric not null,currency text not null,fulfilment_location text not null,
 order_status text not null,ready_at timestamptz,created_at timestamptz default now()
);
create table public.business_profiles(
 seller_id uuid primary key references public.profiles(id),display_name text not null,
 sales_center_address text not null,city text not null,country text not null
);
create table public.products(id uuid primary key,seller_id uuid not null,product_name text not null);
create table public.delivery_jobs(
 id uuid primary key default gen_random_uuid(),
 job_reference text,
 commerce_order_id uuid references public.commerce_orders(id),
 job_status text not null default 'requested',
 assigned_provider_id uuid,
 updated_at timestamptz default now()
);
create table public.transport_providers(
 id uuid primary key,owner_user_id uuid not null,application_status text not null default 'approved'
);

-- Minimal trusted stand-in for the existing internal Delivery Network creator.
create function private.create_delivery_network_job(
 p_external_reference text,p_package_description text,p_package_count integer,
 p_pickup_contact_name text,p_pickup_contact_phone text,p_pickup_address text,p_pickup_city text,p_pickup_country text,
 p_recipient_contact_name text,p_recipient_contact_phone text,p_delivery_address text,p_delivery_city text,p_delivery_country text,
 p_requested_pickup_at timestamptz,p_delivery_deadline timestamptz,p_special_instructions text,
 p_delivery_mode text,p_commerce_order_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 insert into public.delivery_jobs(job_reference,commerce_order_id,job_status) values('NXD-LINKED',p_commerce_order_id,'requested') returning id into v_id;
 return jsonb_build_object('job_id',v_id,'commerce_order_id',p_commerce_order_id);
end;
$$;

insert into public.profiles values
 ('81000000-0000-4000-8000-000000000001','admin','active','NEXORA Admin'),
 ('81000000-0000-4000-8000-000000000002','buyer','active','Buyer One'),
 ('81000000-0000-4000-8000-000000000004','buyer','active','Buyer Two'),
 ('81000000-0000-4000-8000-000000000003','seller','active','Seller One');
insert into public.admin_staff values('81000000-0000-4000-8000-000000000001','ADM-TEST',true);
insert into public.business_profiles values(
 '81000000-0000-4000-8000-000000000003','Seller Business','Sales Centre, Mirpur','Dhaka','Bangladesh'
);
insert into public.products values(
 '82000000-0000-4000-8000-000000000001',
 '81000000-0000-4000-8000-000000000003','Test Product'
);
insert into public.commerce_orders(
 id,order_code,listing_type,listing_id,buyer_id,seller_id,quantity,currency,fulfilment_location,order_status,ready_at
) values
 ('83000000-0000-4000-8000-000000000001','NXO-READY','product','82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000003',25,'BDT','Buyer destination address, Dhaka','ready_for_confirmation',now()),
 ('83000000-0000-4000-8000-000000000002','NXO-PENDING','product','82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000003',5,'BDT','Buyer destination address, Dhaka','pending',now()),
 ('83000000-0000-4000-8000-000000000003','NXO-SERVICE','service','82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000003',1,'BDT','Buyer destination address, Dhaka','ready_for_confirmation',now()),
 ('83000000-0000-4000-8000-000000000004','NXO-OTHER-BUYER','product','82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000004','81000000-0000-4000-8000-000000000003',5,'BDT','Another Buyer destination, Dhaka','pending',now());

\ir ../supabase/migrations/20261115170000_admin_delivery_order_linking.sql

-- No permission, insufficient MFA, and inactive membership must not expose the queue.
set role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
select set_config('test.admin.permission','false',false);
do $denied$ begin
 begin
  perform * from public.get_admin_delivery_order_candidates();
  raise exception 'FAIL: Admin without logistics.assign read the order queue';
 exception when insufficient_privilege then null;
 end;
end $denied$;
select set_config('test.admin.permission','true',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
do $mfa$ begin
 begin
  perform * from public.get_admin_delivery_order_candidates();
  raise exception 'FAIL: Admin without AAL2 read the order queue';
 exception when insufficient_privilege then null;
 end;
end $mfa$;
select set_config('request.jwt.claims','{"aal":"aal2"}',false);

do $candidate$ begin
 if (select count(*) from public.get_admin_delivery_order_candidates())<>1 then
  raise exception 'FAIL: only the ready Product Order should be available';
 end if;
 if (select order_code from public.get_admin_delivery_order_candidates() limit 1)<>'NXO-READY' then
  raise exception 'FAIL: incorrect eligible order was returned';
 end if;
end $candidate$;

select public.create_delivery_network_job_from_order(
 '83000000-0000-4000-8000-000000000001',
 'NXO-READY','Test Product · Order NXO-READY · Quantity 25',1,
 'Seller Business',null,'Sales Centre, Mirpur','Dhaka','Bangladesh',
 'Buyer One',null,'Buyer destination address, Dhaka','Dhaka','Bangladesh',
 null,null,null,'wholesale'
);
reset role;

do $linked$ begin
 if (select count(*) from public.delivery_jobs where commerce_order_id='83000000-0000-4000-8000-000000000001')<>1 then
  raise exception 'FAIL: Delivery Job was not linked to the source Commerce Order';
 end if;
end $linked$;

-- The linked job must appear in the owning Buyer's narrow Receipt OTP queue only.
set role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000002',false);
do $buyer_queue$ begin
 if (select count(*) from public.get_my_order_receipt_jobs(array['83000000-0000-4000-8000-000000000001'::uuid]))<>1 then
  raise exception 'FAIL: Buyer could not discover the newly linked Delivery Job';
 end if;
 if (select count(*) from public.get_my_order_receipt_jobs(array['83000000-0000-4000-8000-000000000004'::uuid]))<>0 then
  raise exception 'FAIL: Buyer could discover another Buyer's Order shipment';
 end if;
end $buyer_queue$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
select set_config('test.admin.permission','true',false);
do $invalid$ begin
 begin
  perform public.create_delivery_network_job_from_order(
   '83000000-0000-4000-8000-000000000002',null,'Pending order',1,null,null,
   'Sales Centre, Mirpur','Dhaka','Bangladesh',null,null,'Buyer destination address, Dhaka',
   'Dhaka','Bangladesh',null,null,null,'wholesale'
  );
  raise exception 'FAIL: pending Order was linked to a Delivery Job';
 exception when sqlstate '22023' then null;
 end;
 begin
  perform public.create_delivery_network_job_from_order(
   '83000000-0000-4000-8000-000000000003',null,'Service order',1,null,null,
   'Sales Centre, Mirpur','Dhaka','Bangladesh',null,null,'Buyer destination address, Dhaka',
   'Dhaka','Bangladesh',null,null,null,'wholesale'
  );
  raise exception 'FAIL: Service Order was linked to a Delivery Job';
 exception when sqlstate '22023' then null;
 end;
end $invalid$;
reset role;

\echo 'PASS: Admin AAL2 order candidate access, ready Product Order linking, Buyer-owned Receipt OTP queue discovery, and pending/service order denial'
