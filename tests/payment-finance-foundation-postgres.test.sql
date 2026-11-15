\set ON_ERROR_STOP on
\pset pager off

-- Focused disposable PostgreSQL harness; not a full Supabase/Auth/PostgREST stack.
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
  order_code text not null,total_price numeric(18,2) not null,currency text not null,order_status text not null
);
\ir ../supabase/migrations/20261115220000_payment_intent_webhook_foundation.sql

insert into public.profiles(id,role,account_status) values
 ('00000000-0000-4000-8000-000000000001','buyer','active'),
 ('00000000-0000-4000-8000-000000000002','seller','active'),
 ('00000000-0000-4000-8000-000000000003','buyer','active');
insert into public.commerce_orders(id,buyer_id,seller_id,order_code,total_price,currency,order_status) values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','NXO-PAYTEST01',123.45,'BDT','accepted'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','NXO-PAYTEST02',99.99,'BDT','ready_for_confirmation'),
 ('10000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','NXO-PAYTEST03',50.00,'JPY','accepted'),
 ('10000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','NXO-PAYTEST04',10.00,'BDT','accepted'),
 ('10000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','NXO-PAYTEST05',20.00,'BDT','accepted');

set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claim.role','authenticated',false);
create temporary table test_intent as select * from public.create_payment_intent('10000000-0000-4000-8000-000000000001','payment-intent-key-0001',30);
do $$ begin
  if (select amount_minor from test_intent)<>12345 or (select currency from test_intent)<>'BDT' then raise exception 'Payment intent amount/currency snapshot failed'; end if;
  if (select count(*) from public.get_my_payment_intents())<>1 then raise exception 'Buyer payment intent read scope failed'; end if;
  if has_table_privilege('authenticated','private.payment_intents','SELECT') then raise exception 'Authenticated unexpectedly has private payment table access'; end if;
  if has_function_privilege('anon','public.create_payment_intent(uuid,text,integer)','EXECUTE') then raise exception 'Anonymous role can create payment intents'; end if;
end $$;
create temporary table test_intent_retry as select * from public.create_payment_intent('10000000-0000-4000-8000-000000000001','payment-intent-key-0001',30);
do $$ begin
  if (select id from test_intent)<>(select id from test_intent_retry) then raise exception 'Payment intent idempotency failed'; end if;
end $$;
do $$ begin
  perform * from public.create_payment_intent('10000000-0000-4000-8000-000000000001','payment-intent-key-alt-01',30);
  raise exception 'Second unresolved payment intent for one Order unexpectedly succeeded';
exception when unique_violation then null;
end $$;
do $$ begin
  perform * from public.create_payment_intent('10000000-0000-4000-8000-000000000002','payment-intent-key-0001',30);
  raise exception 'Reused idempotency key across orders unexpectedly succeeded';
exception when unique_violation then null;
end $$;
do $$ begin
  perform * from public.create_payment_intent('10000000-0000-4000-8000-000000000003','payment-intent-key-jpy-0001',30);
  raise exception 'Unsupported currency precision unexpectedly succeeded';
exception when invalid_parameter_value then null;
end $$;
create temporary table test_intent_2 as select * from public.create_payment_intent('10000000-0000-4000-8000-000000000002','payment-intent-key-0002',30);
create temporary table test_intent_3 as select * from public.create_payment_intent('10000000-0000-4000-8000-000000000004','payment-intent-key-0003',30);
create temporary table test_intent_4 as select * from public.create_payment_intent('10000000-0000-4000-8000-000000000005','payment-intent-key-0004',30);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
do $$ begin if (select count(*) from public.get_my_payment_intents())<>0 then raise exception 'Cross-Buyer payment intent access was not isolated'; end if; end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
grant select on test_intent,test_intent_2,test_intent_3,test_intent_4 to service_role;
reset role;

set role service_role;
select set_config('request.jwt.claim.role','service_role',false);
select public.ingest_verified_payment_event('sandbox','event-001','payment.captured','provider-ref-001','captured',12345,'BDT','txn-001',repeat('a',64));
select public.attach_payment_provider_reference((select id from test_intent),'sandbox','provider-ref-001');
select public.ingest_verified_payment_event('sandbox','event-001','payment.captured','provider-ref-001','captured',12345,'BDT','txn-001',repeat('a',64));
create temporary table duplicate_event as select public.ingest_verified_payment_event('sandbox','event-001','payment.captured','provider-ref-001','captured',12345,'BDT','txn-001',repeat('a',64)) as result;
reset role;
do $$ begin
  if (select result->>'duplicate' from duplicate_event)<>'true' then raise exception 'Duplicate webhook was not idempotent'; end if;
  if (select status from private.payment_intents where id=(select id from test_intent))<>'captured' then raise exception 'Verified capture did not update intent'; end if;
  if (select count(*) from private.payment_transactions where payment_intent_id=(select id from test_intent))<>1 then raise exception 'Duplicate webhook created duplicate transaction'; end if;
end $$;
do $$ begin
  perform * from public.create_payment_intent('10000000-0000-4000-8000-000000000001','payment-intent-key-after-capture',30);
  raise exception 'New payment attempt after captured Order unexpectedly succeeded';
exception when object_not_in_prerequisite_state then null;
end $$;
select public.attach_payment_provider_reference((select id from test_intent_2),'sandbox','provider-ref-002');
select public.attach_payment_provider_reference((select id from test_intent_3),'sandbox','provider-ref-003');
select public.attach_payment_provider_reference((select id from test_intent_4),'sandbox','provider-ref-004');
update private.payment_intents set expires_at=now()-interval '1 minute' where id=(select id from test_intent_3);
select public.expire_stale_payment_intents();
select public.ingest_verified_payment_event('sandbox','event-003','payment.captured','provider-ref-003','captured',1000,'BDT','txn-003',repeat('c',64));
select public.ingest_verified_payment_event('sandbox','event-004','payment.captured','provider-ref-004','captured',2000,'BDT','txn-001',repeat('d',64));
select public.ingest_verified_payment_event('sandbox','event-002','payment.captured','provider-ref-002','captured',9998,'BDT','txn-002',repeat('b',64));
do $$ begin
  if (select status from private.payment_intents where order_id='10000000-0000-4000-8000-000000000002')<>'requires_review' then raise exception 'Amount mismatch did not enter review'; end if;
  if (select count(*) from private.payment_transactions where provider_event_id='event-002')<>0 then raise exception 'Mismatched payment created a transaction'; end if;
  if (select status from private.payment_intents where id=(select id from test_intent_3))<>'requires_review' then raise exception 'Expired payment capture did not enter review'; end if;
  if (select status from private.payment_intents where id=(select id from test_intent_4))<>'requires_review' then raise exception 'Reused provider transaction reference did not enter review'; end if;
  if has_function_privilege('authenticated','public.attach_payment_provider_reference(uuid,text,text)','EXECUTE') then raise exception 'Authenticated role can attach provider references'; end if;
end $$;

create temporary table accounts as
select public.create_finance_account('CASH.BDT','Cash BDT','asset','BDT','debit') as cash_id,
       public.create_finance_account('SELLER.PAYABLE.BDT','Seller Payable BDT','liability','BDT','credit') as payable_id;
create temporary table posted_journal as
select public.post_finance_journal('entry-payment-001','payment_capture',(select id from test_intent),'BDT','Captured payment journal',
  jsonb_build_array(
    jsonb_build_object('account_id',(select cash_id from accounts),'debit_minor',12345,'credit_minor',0,'memo','Captured funds'),
    jsonb_build_object('account_id',(select payable_id from accounts),'debit_minor',0,'credit_minor',12345,'memo','Seller funds payable')
  )) as id;
do $$ begin
  if (select sum(debit_minor) from private.finance_journal_lines where journal_id=(select id from posted_journal)) <>
     (select sum(credit_minor) from private.finance_journal_lines where journal_id=(select id from posted_journal)) then raise exception 'Journal not balanced'; end if;
end $$;
create temporary table posted_retry as
select public.post_finance_journal('entry-payment-001','payment_capture',(select id from test_intent),'BDT','Captured payment journal',
  jsonb_build_array(
    jsonb_build_object('account_id',(select cash_id from accounts),'debit_minor',12345,'credit_minor',0,'memo','Captured funds'),
    jsonb_build_object('account_id',(select payable_id from accounts),'debit_minor',0,'credit_minor',12345,'memo','Seller funds payable')
  )) as id;
do $$ begin
  if (select id from posted_journal)<>(select id from posted_retry) then raise exception 'Journal idempotency failed'; end if;
end $$;
do $$ begin
  perform public.post_finance_journal('entry-unbalanced-001','manual_adjustment',null,'BDT','Unbalanced test',
    jsonb_build_array(jsonb_build_object('account_id',(select cash_id from accounts),'debit_minor',100,'credit_minor',0),jsonb_build_object('account_id',(select payable_id from accounts),'debit_minor',0,'credit_minor',99)));
  raise exception 'Unbalanced journal unexpectedly posted';
exception when check_violation then null;
end $$;
create temporary table reversal as select public.reverse_finance_journal((select id from posted_journal),'entry-reversal-001','Reverse captured payment') as id;
do $$ begin
  if (select reversal_of from private.finance_journals where id=(select id from reversal))<>(select id from posted_journal) then raise exception 'Journal reversal link missing'; end if;
  if (select sum(debit_minor) from private.finance_journal_lines where journal_id=(select id from reversal))<>12345 then raise exception 'Reversal debit was not mirrored'; end if;
  if (select sum(credit_minor) from private.finance_journal_lines where journal_id=(select id from reversal))<>12345 then raise exception 'Reversal credit was not mirrored'; end if;
end $$;
reset role;
do $$ begin
  update private.finance_journals set description='tampered' where id=(select id from posted_journal);
  raise exception 'Posted journal mutation unexpectedly succeeded';
exception when object_not_in_prerequisite_state then null;
end $$;
do $$ begin
  insert into private.finance_journal_lines(journal_id,line_no,account_id,debit_minor,credit_minor)
  values((select id from posted_journal),99,(select cash_id from accounts),1,0);
  raise exception 'Line insert into posted journal unexpectedly succeeded';
exception when object_not_in_prerequisite_state then null;
end $$;

select 'payment-finance-foundation: PASS' as result;
