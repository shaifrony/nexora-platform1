\set ON_ERROR_STOP on
\pset pager off

create extension if not exists pgcrypto;
do $r$ begin create role anon nologin; exception when duplicate_object then null; end $r$;
do $r$ begin create role authenticated nologin; exception when duplicate_object then null; end $r$;
do $r$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $r$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable set search_path='' as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create or replace function auth.role() returns text language sql stable set search_path='' as $$ select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),current_user) $$;
create table public.profiles(id uuid primary key,role text not null,account_status text not null);
create table public.commerce_orders(
  id uuid primary key,buyer_id uuid not null references public.profiles(id),seller_id uuid not null references public.profiles(id),
  order_code text not null,
  quantity numeric(18,3) not null,
  unit_price numeric(18,2) not null,
  total_price numeric(18,2) generated always as (round(quantity*unit_price,2)) stored,
  delivery_charge numeric(18,2) not null default 0,
  source_offer_total numeric(18,2),
  grand_total numeric(18,2) generated always as (round(coalesce(source_offer_total,quantity*unit_price)+delivery_charge,2)) stored,
  currency text not null,
  order_status text not null
);
\ir ../supabase/migrations/20261115220000_payment_intent_webhook_foundation.sql
\ir ../supabase/migrations/20261115230000_payment_reconciliation_batch_queue.sql

insert into public.profiles(id,role,account_status) values
 ('00000000-0000-4000-8000-000000000001','buyer','active'),
 ('00000000-0000-4000-8000-000000000002','seller','active');
insert into public.commerce_orders(id,buyer_id,seller_id,order_code,quantity,unit_price,currency,order_status,delivery_charge,source_offer_total) values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','NXO-RECON001',1,123.45,'BDT','accepted',0,null),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','NXO-RECON002',1,99.99,'BDT','accepted',0,null),
 ('10000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','NXO-RECON003',1,30.00,'USD','accepted',0,null);

set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claim.role','authenticated',false);
create temporary table intent_one as select * from public.create_payment_intent('10000000-0000-4000-8000-000000000001','recon-intent-key-0001',30);
create temporary table intent_two as select * from public.create_payment_intent('10000000-0000-4000-8000-000000000002','recon-intent-key-0002',30);
create temporary table intent_three as select * from public.create_payment_intent('10000000-0000-4000-8000-000000000003','recon-intent-key-0003',30);
reset role;
select set_config('request.jwt.claim.sub','',false);
select set_config('request.jwt.claim.role','service_role',false);
select public.attach_payment_provider_reference((select id from intent_one),'sandbox','recon-provider-ref-001');
select public.attach_payment_provider_reference((select id from intent_two),'sandbox','recon-provider-ref-002');
select public.attach_payment_provider_reference((select id from intent_three),'sandbox','recon-provider-ref-003');
select public.ingest_verified_payment_event('sandbox','recon-event-001','payment.captured','recon-provider-ref-001','captured',12345,'BDT','recon-txn-001',repeat('a',64));
select public.ingest_verified_payment_event('sandbox','recon-event-002','payment.captured','recon-provider-ref-002','captured',9999,'BDT','recon-txn-002',repeat('b',64));
select public.ingest_verified_payment_event('sandbox','recon-event-003','payment.captured','recon-provider-ref-003','captured',3000,'USD','recon-txn-003',repeat('e',64));

create temporary table batch_result as
select public.ingest_payment_reconciliation_batch(
  'sandbox','statement-2026-11-15','2026-11-15T00:00:00Z','2026-11-16T00:00:00Z','BDT',repeat('c',64),
  jsonb_build_array(
    jsonb_build_object('provider_transaction_ref','recon-txn-001','provider_event_id','recon-event-001','provider_status','captured','amount_minor',12345,'currency','BDT'),
    jsonb_build_object('provider_transaction_ref','recon-txn-002','provider_event_id','recon-event-002','provider_status','captured','amount_minor',9998,'currency','BDT'),
    jsonb_build_object('provider_transaction_ref','recon-txn-unknown','provider_event_id','recon-event-unknown','provider_status','captured','amount_minor',5000,'currency','BDT'),
    jsonb_build_object('provider_transaction_ref','recon-txn-001','provider_event_id','recon-event-001','provider_status','captured','amount_minor',12345,'currency','BDT'),
    jsonb_build_object('provider_transaction_ref','recon-txn-003','provider_event_id','recon-event-003','provider_status','captured','amount_minor',3000,'currency','USD')
  )
) as result;
do $$ begin
  if (select result->>'status' from batch_result)<>'review_required' then raise exception 'Reconciliation batch should require review'; end if;
  if (select (result->>'matched_count')::integer from batch_result)<>1 then raise exception 'Expected exactly one matched provider row'; end if;
  if (select (result->>'exception_count')::integer from batch_result)<>4 then raise exception 'Expected four reconciliation exceptions'; end if;
  if has_table_privilege('authenticated','private.payment_reconciliation_batches','SELECT') then raise exception 'Authenticated role can read private reconciliation batches'; end if;
  if has_function_privilege('authenticated','public.ingest_payment_reconciliation_batch(text,text,timestamptz,timestamptz,text,text,jsonb)','EXECUTE') then raise exception 'Authenticated role can ingest reconciliation batches'; end if;
end $$;
create temporary table batch_duplicate as
select public.ingest_payment_reconciliation_batch(
  'sandbox','statement-2026-11-15','2026-11-15T00:00:00Z','2026-11-16T00:00:00Z','BDT',repeat('c',64),
  jsonb_build_array(
    jsonb_build_object('provider_transaction_ref','recon-txn-001','provider_event_id','recon-event-001','provider_status','captured','amount_minor',12345,'currency','BDT'),
    jsonb_build_object('provider_transaction_ref','recon-txn-002','provider_event_id','recon-event-002','provider_status','captured','amount_minor',9998,'currency','BDT'),
    jsonb_build_object('provider_transaction_ref','recon-txn-unknown','provider_event_id','recon-event-unknown','provider_status','captured','amount_minor',5000,'currency','BDT'),
    jsonb_build_object('provider_transaction_ref','recon-txn-001','provider_event_id','recon-event-001','provider_status','captured','amount_minor',12345,'currency','BDT'),
    jsonb_build_object('provider_transaction_ref','recon-txn-003','provider_event_id','recon-event-003','provider_status','captured','amount_minor',3000,'currency','USD')
  )
) as result;
do $$ begin
  if (select result->>'duplicate' from batch_duplicate)<>'true' then raise exception 'Duplicate statement import was not idempotent'; end if;
end $$;
do $$ begin
  perform public.ingest_payment_reconciliation_batch('sandbox','statement-2026-11-15','2026-11-15T00:00:00Z','2026-11-16T00:00:00Z','BDT',repeat('d',64),jsonb_build_array(jsonb_build_object('provider_transaction_ref','different','provider_status','captured','amount_minor',1,'currency','BDT')));
  raise exception 'Statement reference reuse with different hash unexpectedly succeeded';
exception when unique_violation then null;
end $$;

create temporary table batch_id as select (result->>'batch_id')::uuid as id from batch_result;
do $$ begin
  if (select count(*) from private.payment_reconciliation_rows r where r.batch_id=(select id from batch_id) and r.match_status='matched')<>1 then raise exception 'Matched reconciliation row missing'; end if;
  if (select count(*) from private.payment_reconciliation_rows r where r.batch_id=(select id from batch_id) and r.match_status='amount_mismatch')<>1 then raise exception 'Amount mismatch not detected'; end if;
  if (select count(*) from private.payment_reconciliation_rows r where r.batch_id=(select id from batch_id) and r.match_status='unmatched_provider_transaction')<>1 then raise exception 'Unmatched provider transaction not detected'; end if;
  if (select count(*) from private.payment_reconciliation_rows r where r.batch_id=(select id from batch_id) and r.match_status='duplicate_provider_transaction')<>1 then raise exception 'Duplicate provider transaction not detected'; end if;
  if (select count(*) from private.payment_reconciliation_rows r where r.batch_id=(select id from batch_id) and r.match_status='currency_mismatch')<>1 then raise exception 'Batch currency mismatch not detected'; end if;
end $$;
create temporary table reconciliation_view as select public.get_payment_reconciliation_batch((select id from batch_id)) as result;
do $$ begin
  if (select jsonb_array_length(rv.result->'rows') from reconciliation_view rv)<>5 then raise exception 'Scoped reconciliation view did not include all batch rows'; end if;
end $$;
select public.review_payment_reconciliation_exception((select id from private.payment_reconciliation_rows where batch_id=(select id from batch_id) and match_status='amount_mismatch'),'resolved','Provider report amount verified against supporting evidence');
select public.review_payment_reconciliation_exception((select id from private.payment_reconciliation_rows where batch_id=(select id from batch_id) and match_status='unmatched_provider_transaction'),'dismissed','Provider report row confirmed outside the platform payment scope');
select public.review_payment_reconciliation_exception((select id from private.payment_reconciliation_rows where batch_id=(select id from batch_id) and match_status='duplicate_provider_transaction'),'resolved','Duplicate statement row confirmed and excluded from totals');
select public.review_payment_reconciliation_exception((select id from private.payment_reconciliation_rows where batch_id=(select id from batch_id) and match_status='currency_mismatch'),'dismissed','Currency mismatch traced to a report row outside this batch currency');
do $$ begin
  if (select status from private.payment_reconciliation_batches where id=(select id from batch_id))<>'reviewed' then raise exception 'Batch did not reach reviewed state'; end if;
  if (select count(*) from private.payment_reconciliation_rows where batch_id=(select id from batch_id) and review_status='open')<>0 then raise exception 'Open reconciliation exceptions remain'; end if;
  if (select count(*) from private.payment_intents where status='captured')<>3 then raise exception 'Reconciliation review must not change payment capture state'; end if;
end $$;
create temporary table clean_batch as
select public.ingest_payment_reconciliation_batch(
  'sandbox','statement-2026-11-16','2026-11-16T00:00:00Z','2026-11-17T00:00:00Z','BDT',repeat('f',64),
  jsonb_build_array(jsonb_build_object('provider_transaction_ref','recon-txn-001','provider_event_id','recon-event-001','provider_status','captured','amount_minor',12345,'currency','BDT'))
) as result;
do $$ begin
  if (select result->>'status' from clean_batch)<>'matched' then raise exception 'Fully matched batch did not reach matched status'; end if;
  if (select (result->>'exception_count')::integer from clean_batch)<>0 then raise exception 'Fully matched batch has unexpected exceptions'; end if;
end $$;
select 'payment-reconciliation: PASS' as result;
