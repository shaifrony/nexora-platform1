\set ON_ERROR_STOP on
\pset pager off

do $roles$
begin
  create role anon nologin;
exception when duplicate_object then null;
end
$roles$;
do $roles$
begin
  create role authenticated nologin;
exception when duplicate_object then null;
end
$roles$;

create schema if not exists auth;
create schema if not exists private;
create or replace function auth.uid()
returns uuid language sql stable set search_path=''
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;

create table public.profiles(
 id uuid primary key, role text not null, account_status text not null
);
create table public.commerce_orders(
 id uuid primary key, buyer_id uuid not null references public.profiles(id)
);
create table public.delivery_jobs(
 id uuid primary key, job_reference text not null unique,
 commerce_order_id uuid references public.commerce_orders(id),
 job_status text not null
);

\ir ../supabase/migrations/20261115130000_buyer_safe_delivery_updates.sql

insert into public.profiles(id,role,account_status) values
 ('61000000-0000-4000-8000-000000000001','buyer','active'),
 ('61000000-0000-4000-8000-000000000002','buyer','active'),
 ('61000000-0000-4000-8000-000000000011','seller','active');
insert into public.commerce_orders(id,buyer_id) values
 ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001'),
 ('62000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000002');
insert into public.delivery_jobs(id,job_reference,commerce_order_id,job_status) values
 ('63000000-0000-4000-8000-000000000001','NXD-SAFE-ORDER-A','62000000-0000-4000-8000-000000000001','requested'),
 ('63000000-0000-4000-8000-000000000002','NXD-SAFE-ORDER-B','62000000-0000-4000-8000-000000000002','requested'),
 ('63000000-0000-4000-8000-000000000003','NXD-UNLINKED',null,'requested');

do $publish$
declare v_count integer;
begin
 update public.delivery_jobs set job_status='assigned' where id='63000000-0000-4000-8000-000000000001';
 update public.delivery_jobs set job_status='picked_up' where id='63000000-0000-4000-8000-000000000001';
 update public.delivery_jobs set job_status='in_transit' where id='63000000-0000-4000-8000-000000000001';
 update public.delivery_jobs set job_status='out_for_delivery' where id='63000000-0000-4000-8000-000000000001';
 update public.delivery_jobs set job_status='delivered' where id='63000000-0000-4000-8000-000000000001';
 select count(*) into v_count from private.delivery_customer_updates
  where commerce_order_id='62000000-0000-4000-8000-000000000001';
 if v_count<>5 then raise exception 'FAIL: expected five safe updates for first shipment, got %',v_count; end if;
 if (select customer_status from private.delivery_customer_updates
     where job_id='63000000-0000-4000-8000-000000000001'
     order by id desc limit 1)<>'delivered' then
  raise exception 'FAIL: delivered status was not projected';
 end if;
 if (select count(*) from private.delivery_customer_updates where job_id='63000000-0000-4000-8000-000000000003')<>0 then
  raise exception 'FAIL: unlinked operational job leaked into Buyer updates';
 end if;
 if exists(select 1 from information_schema.columns
   where table_schema='private' and table_name='delivery_customer_updates'
   and column_name in ('phone','address','internal_note','gps_latitude','gps_longitude','provider_id')) then
  raise exception 'FAIL: private customer projection contains prohibited operational fields';
 end if;
end
$publish$;

-- Buyers see only their own order updates through the narrow RPC.
set role authenticated;
select set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000001',false);
do $buyer_a$
declare v_count integer; v_order_count integer;
begin
 select count(*),count(distinct order_id) into v_count,v_order_count
 from public.get_my_order_delivery_updates(array[
  '62000000-0000-4000-8000-000000000001'::uuid,
  '62000000-0000-4000-8000-000000000002'::uuid
 ]);
 if v_count<>5 or v_order_count<>1 then
  raise exception 'FAIL: Buyer A saw unexpected tracking rows %, orders %',v_count,v_order_count;
 end if;
 if has_table_privilege('authenticated','private.delivery_customer_updates','SELECT') then
  raise exception 'FAIL: authenticated users can read the private projection table directly';
 end if;
 if has_function_privilege('anon','public.get_my_order_delivery_updates(uuid[])','EXECUTE') then
  raise exception 'FAIL: anonymous users can execute the Buyer tracking RPC';
 end if;
end
$buyer_a$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000002',false);
do $buyer_b$
declare v_count integer;
begin
 select count(*) into v_count
 from public.get_my_order_delivery_updates(array['62000000-0000-4000-8000-000000000001'::uuid]);
 if v_count<>0 then raise exception 'FAIL: Buyer B read Buyer A delivery updates'; end if;
end
$buyer_b$;
reset role;

-- Customer projection rows cannot be edited or deleted.
do $append_only$
declare v_denied boolean:=false;
begin
 begin
  update private.delivery_customer_updates set customer_message='Tampered'
   where job_id='63000000-0000-4000-8000-000000000001';
 exception when insufficient_privilege then v_denied:=true;
 end;
 if not v_denied then raise exception 'FAIL: append-only customer update table accepted direct update'; end if;
end
$append_only$;

\echo 'PASS: customer-safe delivery status mapping, append-only history, Buyer ownership isolation, no raw operational table access, and no anonymous RPC execution'
