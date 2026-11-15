\set ON_ERROR_STOP on
\pset pager off

do $block$ begin create role anon nologin; exception when duplicate_object then null; end $block$;
do $block$ begin create role authenticated nologin; exception when duplicate_object then null; end $block$;
create schema if not exists auth;
create schema if not exists private;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
grant usage on schema private,extensions to authenticated;

create or replace function auth.uid() returns uuid language sql stable set search_path=''
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable set search_path=''
as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb) $$;
create or replace function private.has_nexora_permission(text) returns boolean
language sql stable set search_path=''
as $$ select coalesce(current_setting('test.admin.permission',true),'false')='true' $$;

create table public.profiles(id uuid primary key,role text not null,account_status text not null,full_name text);
create table auth.users(
 id uuid primary key,email text,email_confirmed_at timestamptz,phone text,phone_confirmed_at timestamptz
);
create table public.admin_staff(user_id uuid primary key,admin_code text,is_active boolean);
create table public.admin_audit_logs(
 actor_user_id uuid,actor_admin_code text,action_key text,target_type text,target_id text,
 reason text,details jsonb
);
create table public.delivery_network_partners(
 id uuid primary key,partner_kind text not null,partner_status text not null,display_name text not null
);
create table public.delivery_network_staff(
 id uuid primary key,staff_code text,partner_id uuid not null,full_name text not null,
 contact_phone text not null,contact_email text,employment_type text not null,
 service_cities text[] default '{}',vehicle_type text,staff_status text not null,
 admin_notes text,created_by uuid not null,updated_by uuid not null,
 created_at timestamptz default now(),updated_at timestamptz default now()
);
create table public.transport_providers(id uuid primary key,owner_user_id uuid not null,application_status text not null);
create table public.transport_vehicles(
 id uuid primary key,provider_id uuid not null,approval_status text not null,is_available boolean not null
);
create table public.delivery_jobs(
 id uuid primary key,job_reference text not null,job_status text not null,
 assigned_provider_id uuid,assigned_partner_id uuid,assigned_staff_id uuid,assignment_source text,
 assigned_vehicle_id uuid,assigned_by uuid,assigned_at timestamptz,updated_at timestamptz default now()
);
create table public.delivery_job_assignment_history(
 id bigint generated always as identity primary key,job_id uuid,assignment_source text,
 provider_id uuid,partner_id uuid,staff_id uuid,vehicle_id uuid,assigned_by uuid,reason text
);
create table public.delivery_tracking_events(
 id bigint generated always as identity primary key,job_id uuid,previous_status text,new_status text,
 location_description text,note text,external_tracking_code text,actor_user_id uuid,actor_type text,
 created_at timestamptz default now()
);
create table private.delivery_receipt_challenges(
 id uuid primary key default gen_random_uuid(),job_id uuid not null,commerce_order_id uuid,buyer_id uuid not null,
 code_hash text not null,expires_at timestamptz not null,attempts integer not null default 0,
 consumed_at timestamptz,verified_at timestamptz,created_at timestamptz default now()
);

insert into public.profiles values
 ('91000000-0000-4000-8000-000000000001','admin','active','NEXORA Admin'),
 ('91000000-0000-4000-8000-000000000002','porter','active','Team Driver'),
 ('91000000-0000-4000-8000-000000000003','seller','active','Courier Driver'),
 ('91000000-0000-4000-8000-000000000004','buyer','active','Other User');
insert into auth.users values
 ('91000000-0000-4000-8000-000000000001','admin@nexora.test',now(),null,null),
 ('91000000-0000-4000-8000-000000000002','team.driver@nexora.test',now(),'+8801711111111',now()),
 ('91000000-0000-4000-8000-000000000003','courier.driver@nexora.test',now(),'+8801722222222',now()),
 ('91000000-0000-4000-8000-000000000004','unverified@nexora.test',null,null,null);
insert into public.admin_staff values('91000000-0000-4000-8000-000000000001','ADM-STAFF-TEST',true);
insert into public.delivery_network_partners values
 ('92000000-0000-4000-8000-000000000001','nexora_team','approved','NEXORA Dhaka Team'),
 ('92000000-0000-4000-8000-000000000002','courier_company','approved','Trusted Courier Ltd');
insert into public.delivery_network_staff(
 id,staff_code,partner_id,full_name,contact_phone,contact_email,employment_type,staff_status,created_by,updated_by
) values
 ('93000000-0000-4000-8000-000000000001','NXDS-TEAM-01','92000000-0000-4000-8000-000000000001','Team Driver','01711111111','team.driver@nexora.test','employee','active','91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001'),
 ('93000000-0000-4000-8000-000000000002','NXDS-COURIER-01','92000000-0000-4000-8000-000000000002','Courier Driver','01722222222','courier.driver@nexora.test','contract','active','91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001'),
 ('93000000-0000-4000-8000-000000000003','NXDS-UNVERIFIED','92000000-0000-4000-8000-000000000001','Unverified Driver','01733333333','unverified@nexora.test','employee','active','91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001');
insert into public.delivery_jobs(id,job_reference,job_status) values
 ('94000000-0000-4000-8000-000000000001','NXD-TEAM-STAFF','requested'),
 ('94000000-0000-4000-8000-000000000002','NXD-COURIER-STAFF','requested');

\ir ../supabase/migrations/20261115180000_delivery_staff_receipt_identity.sql

-- Only an active AAL2 Admin with logistics.assign can bind identities.
set role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
select set_config('test.admin.permission','true',false);
select public.bind_delivery_network_staff_identity('93000000-0000-4000-8000-000000000001');
select public.bind_delivery_network_staff_identity('93000000-0000-4000-8000-000000000002');
do $unverified$ begin
 begin
  perform public.bind_delivery_network_staff_identity('93000000-0000-4000-8000-000000000003');
  raise exception 'FAIL: unverified Auth email was allowed to bind';
 exception when sqlstate '22023' then null;
 end;
end $unverified$;
reset role;

do $bound$ begin
 if (select auth_user_id from public.delivery_network_staff where id='93000000-0000-4000-8000-000000000001')
   <>'91000000-0000-4000-8000-000000000002' then raise exception 'FAIL: Team staff identity not bound'; end if;
 if (select auth_user_id from public.delivery_network_staff where id='93000000-0000-4000-8000-000000000002')
   <>'91000000-0000-4000-8000-000000000003' then raise exception 'FAIL: Courier staff identity not bound'; end if;
end $bound$;

-- AAL2 Admin can assign identity-bound staff for both partner kinds; an unbound worker is rejected.
set role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
select set_config('test.admin.permission','true',false);
select public.assign_delivery_job_network(
 '94000000-0000-4000-8000-000000000001','nexora_team',null,
 '92000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001',null,'Team dispatch'
);
select public.assign_delivery_job_network(
 '94000000-0000-4000-8000-000000000002','courier_partner',null,
 '92000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000002',null,'Courier dispatch'
);
do $bad_assignment$ begin
 begin
  perform public.assign_delivery_job_network(
   '94000000-0000-4000-8000-000000000001','nexora_team',null,
   '92000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000003',null,'Unverified staff'
  );
  raise exception 'FAIL: unbound staff was assigned';
 exception when check_violation then null;
 end;
end $bad_assignment$;
reset role;

update public.delivery_jobs set job_status='out_for_delivery' where id in (
 '94000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000002'
);

-- Staff sees only their own assigned work. A generic active user sees none.
set role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',false);
do $team_queue$ begin
 if (select count(*) from public.get_my_assigned_staff_receipt_jobs())<>1 then
  raise exception 'FAIL: NEXORA team worker queue did not return exactly its own job';
 end if;
 if (select partner_name from public.get_my_assigned_staff_receipt_jobs() limit 1)<>'NEXORA Dhaka Team' then
  raise exception 'FAIL: NEXORA team worker queue returned incorrect partner';
 end if;
end $team_queue$;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000004',false);
do $other_queue$ begin
 if (select count(*) from public.get_my_assigned_staff_receipt_jobs())<>0 then
  raise exception 'FAIL: unrelated account can see staff work';
 end if;
end $other_queue$;
reset role;

-- A staff member can verify only a job assigned to their own identity.
insert into private.delivery_receipt_challenges(job_id,buyer_id,code_hash,expires_at)
values('94000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000004',
 encode(extensions.digest('ABCDEF0123456789ABCDEF0123456789'||
 '94000000-0000-4000-8000-000000000001'||
 '91000000-0000-4000-8000-000000000004'||'NEXORA-RECEIPT-V1','sha256'),'hex'),
 now()+interval '10 minutes');
set role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000003',false);
do $denied_verify$ begin
 begin
  perform public.verify_delivery_receipt_code(
   '94000000-0000-4000-8000-000000000001','ABCDEF0123456789ABCDEF0123456789',null,null
  );
  raise exception 'FAIL: courier worker verified another staff member shipment';
 exception when insufficient_privilege then null;
 end;
end $denied_verify$;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',false);
do $verified$ begin
 if (public.verify_delivery_receipt_code(
   '94000000-0000-4000-8000-000000000001','ABCDEF0123456789ABCDEF0123456789',null,'Staff handover'
 )->>'verified')::boolean is not true then
  raise exception 'FAIL: identity-bound Team worker could not verify own delivery';
 end if;
end $verified$;
reset role;

do $audit$ begin
 if (select job_status from public.delivery_jobs where id='94000000-0000-4000-8000-000000000001')<>'delivered' then
  raise exception 'FAIL: staff receipt verification did not mark shipment delivered';
 end if;
 if (select actor_type from public.delivery_tracking_events where job_id='94000000-0000-4000-8000-000000000001')<>'delivery_staff' then
  raise exception 'FAIL: staff verification actor type was not recorded';
 end if;
 if (select count(*) from public.admin_audit_logs where action_key='delivery_network.staff_identity_bound')<>2 then
  raise exception 'FAIL: staff identity binding audit trail missing';
 end if;
end $audit$;

\echo 'PASS: verified staff identity binding, NEXORA Team and Courier assignment, own-job queue isolation, and staff-only OTP receipt verification'
