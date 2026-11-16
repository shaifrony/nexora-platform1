-- Provider-neutral payment intent, verified webhook inbox and immutable ledger foundation.
-- Development branch only. No provider is configured and no funds are moved by this migration.
begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create table private.payment_intents (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.commerce_orders(id) on delete restrict,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'created' check (status in ('created','pending_provider','authorized','captured','failed','expired','cancelled','requires_review')),
  idempotency_key text not null check (length(idempotency_key) between 16 and 128),
  provider_code text check (provider_code is null or provider_code ~ '^[a-z0-9][a-z0-9_-]{1,47}$'),
  provider_payment_ref text check (provider_payment_ref is null or length(provider_payment_ref) between 1 and 200),
  expires_at timestamptz not null,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (buyer_id,idempotency_key),
  check ((status='captured') = (captured_at is not null)),
  check ((provider_code is null) = (provider_payment_ref is null))
);
create unique index payment_intents_provider_ref_uidx on private.payment_intents(provider_code,provider_payment_ref) where provider_code is not null;
create unique index payment_intents_one_open_per_order_uidx on private.payment_intents(order_id) where status in ('created','pending_provider','authorized','requires_review');
create index payment_intents_buyer_created_idx on private.payment_intents(buyer_id,created_at desc);
create index payment_intents_seller_created_idx on private.payment_intents(seller_id,created_at desc);

create table private.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  payment_intent_id uuid not null references private.payment_intents(id) on delete restrict,
  provider_code text not null check (provider_code ~ '^[a-z0-9][a-z0-9_-]{1,47}$'),
  provider_transaction_ref text not null check (length(provider_transaction_ref) between 1 and 200),
  transaction_kind text not null check (transaction_kind in ('authorized','captured','failed')),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  provider_event_id text not null,
  created_at timestamptz not null default now(),
  unique(provider_code,provider_transaction_ref),
  unique(provider_code,provider_event_id)
);
create index payment_transactions_intent_idx on private.payment_transactions(payment_intent_id,created_at);

create table private.provider_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9][a-z0-9_-]{1,47}$'),
  provider_event_id text not null check (length(provider_event_id) between 1 and 200),
  event_type text not null check (length(event_type) between 1 and 120),
  provider_payment_ref text not null check (length(provider_payment_ref) between 1 and 200),
  provider_transaction_ref text not null check (length(provider_transaction_ref) between 1 and 200),
  outcome text not null check (outcome in ('authorized','captured','failed')),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  signature_verified boolean not null default true check (signature_verified),
  payment_intent_id uuid references private.payment_intents(id) on delete restrict,
  processing_status text not null default 'received' check (processing_status in ('received','processed','unmatched','requires_review')),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error_code text,
  unique(provider_code,provider_event_id)
);
create index provider_webhook_events_pending_idx on private.provider_webhook_events(received_at) where processing_status='received';

create table private.payment_currency_minor_units (
  currency text primary key check (currency ~ '^[A-Z]{3}$'),
  minor_unit_exponent smallint not null check (minor_unit_exponent between 0 and 3),
  enabled boolean not null default false
);
insert into private.payment_currency_minor_units(currency,minor_unit_exponent,enabled) values
  ('BDT',2,true),('USD',2,true),('EUR',2,true),('GBP',2,true),
  ('INR',2,true),('PKR',2,true),('SAR',2,true),('AED',2,true),
  ('SGD',2,true),('MYR',2,true),('THB',2,true),('AUD',2,true),
  ('CAD',2,true),('JPY',0,false),('KWD',3,false),('BHD',3,false)
on conflict(currency) do nothing;

create table private.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  account_code text not null check (account_code ~ '^[A-Z0-9][A-Z0-9._-]{1,47}$'),
  account_name text not null check (length(btrim(account_name)) between 2 and 120),
  account_type text not null check (account_type in ('asset','liability','equity','revenue','expense')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  normal_balance text not null check (normal_balance in ('debit','credit')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(account_code,currency)
);

create table private.finance_journals (
  id uuid primary key default gen_random_uuid(),
  entry_ref text not null unique check (length(entry_ref) between 8 and 160),
  source_type text not null check (source_type in ('payment_capture','refund','commission','seller_payable','payout','provider_fee','tax','chargeback','manual_adjustment','fx_conversion')),
  source_id uuid,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  description text not null check (length(btrim(description)) between 3 and 500),
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{32}$'),
  status text not null default 'draft' check (status in ('draft','posted')),
  reversal_of uuid references private.finance_journals(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  posted_at timestamptz,
  unique(reversal_of),
  check ((status='draft') = (posted_at is null))
);
create index finance_journals_source_idx on private.finance_journals(source_type,source_id);
create index finance_journals_posted_idx on private.finance_journals(posted_at desc) where status='posted';

create table private.finance_journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_id uuid not null references private.finance_journals(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  account_id uuid not null references private.finance_accounts(id) on delete restrict,
  debit_minor bigint not null default 0 check (debit_minor >= 0),
  credit_minor bigint not null default 0 check (credit_minor >= 0),
  memo text check (memo is null or length(memo) <= 240),
  unique(journal_id,line_no),
  check ((debit_minor > 0 and credit_minor=0) or (credit_minor > 0 and debit_minor=0))
);
create index finance_journal_lines_account_idx on private.finance_journal_lines(account_id,journal_id);

alter table private.payment_currency_minor_units enable row level security;
alter table private.payment_intents enable row level security;
alter table private.payment_transactions enable row level security;
alter table private.provider_webhook_events enable row level security;
alter table private.finance_accounts enable row level security;
alter table private.finance_journals enable row level security;
alter table private.finance_journal_lines enable row level security;
revoke all on private.payment_currency_minor_units,private.payment_intents,private.payment_transactions,private.provider_webhook_events,private.finance_accounts,private.finance_journals,private.finance_journal_lines from public,anon,authenticated;
revoke all on all sequences in schema private from public,anon,authenticated;

create or replace function public.create_payment_intent(
  p_order_id uuid,
  p_idempotency_key text,
  p_expiry_minutes integer default 30
) returns table (id uuid,order_id uuid,amount_minor bigint,currency text,status text,expires_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_order public.commerce_orders%rowtype;
  v_existing private.payment_intents%rowtype;
  v_id uuid;
  v_minor_exponent smallint;
begin
  if v_user is null then raise exception 'Login required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtext(v_user::text||':'||coalesce(p_idempotency_key,'')));
  if p_idempotency_key is null or length(p_idempotency_key) not between 16 and 128 then
    raise exception 'A 16-128 character idempotency key is required' using errcode='22023';
  end if;
  if p_expiry_minutes is null or p_expiry_minutes not between 5 and 60 then
    raise exception 'Payment intent expiry must be between 5 and 60 minutes' using errcode='22023';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_user and p.role='buyer' and p.account_status='active') then
    raise exception 'Active Buyer account required' using errcode='42501';
  end if;
  select * into v_existing from private.payment_intents where buyer_id=v_user and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.order_id<>p_order_id then raise exception 'Idempotency key is already used for another order' using errcode='23505'; end if;
    return query select v_existing.id,v_existing.order_id,v_existing.amount_minor,v_existing.currency,v_existing.status,v_existing.expires_at;
    return;
  end if;
  select o.* into v_order from public.commerce_orders o where o.id=p_order_id and o.buyer_id=v_user for update;
  if not found then raise exception 'Order not found' using errcode='P0002'; end if;
  if v_order.order_status not in ('accepted','ready_for_confirmation') then
    raise exception 'Order must be accepted before payment can be initiated' using errcode='55000';
  end if;
  if exists(select 1 from private.payment_intents pi where pi.order_id=v_order.id and pi.status='captured') then
    raise exception 'Order already has a captured payment' using errcode='55000';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_order.seller_id and p.role='seller' and p.account_status='active') then
    raise exception 'Active Seller account required' using errcode='42501';
  end if;
  select cmu.minor_unit_exponent into v_minor_exponent from private.payment_currency_minor_units cmu where cmu.currency=v_order.currency and cmu.enabled;
  if not found then raise exception 'Currency is not enabled for payment; minor-unit precision is not configured' using errcode='22023'; end if;
  if v_order.grand_total is null or v_order.grand_total<=0 or v_order.grand_total*power(10::numeric,v_minor_exponent)>9223372036854775807 then
    raise exception 'Order total cannot be represented as minor units' using errcode='22003';
  end if;
  insert into private.payment_intents(order_id,buyer_id,seller_id,amount_minor,currency,idempotency_key,expires_at)
  values(v_order.id,v_user,v_order.seller_id,round(v_order.grand_total*power(10::numeric,v_minor_exponent))::bigint,v_order.currency,p_idempotency_key,now()+make_interval(mins=>p_expiry_minutes))
  returning private.payment_intents.id into v_id;
  return query select pi.id,pi.order_id,pi.amount_minor,pi.currency,pi.status,pi.expires_at from private.payment_intents pi where pi.id=v_id;
end;
$$;
revoke all on function public.create_payment_intent(uuid,text,integer) from public,anon;
grant execute on function public.create_payment_intent(uuid,text,integer) to authenticated;

create or replace function public.get_my_payment_intents()
returns table(id uuid,order_id uuid,order_code text,amount_minor bigint,currency text,status text,expires_at timestamptz,captured_at timestamptz,created_at timestamptz)
language sql stable security definer set search_path=''
as $$
  select pi.id,pi.order_id,o.order_code,pi.amount_minor,pi.currency,pi.status,pi.expires_at,pi.captured_at,pi.created_at
  from private.payment_intents pi join public.commerce_orders o on o.id=pi.order_id
  where auth.uid() is not null and (pi.buyer_id=auth.uid() or pi.seller_id=auth.uid())
  order by pi.created_at desc limit 100;
$$;
revoke all on function public.get_my_payment_intents() from public,anon;
grant execute on function public.get_my_payment_intents() to authenticated;

create or replace function public.attach_payment_provider_reference(p_payment_intent_id uuid,p_provider_code text,p_provider_payment_ref text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_intent private.payment_intents%rowtype;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if p_provider_code is null or p_provider_code !~ '^[a-z0-9][a-z0-9_-]{1,47}$' or p_provider_payment_ref is null or length(p_provider_payment_ref) not between 1 and 200 then
    raise exception 'Invalid provider reference' using errcode='22023';
  end if;
  select * into v_intent from private.payment_intents where id=p_payment_intent_id for update;
  if not found then raise exception 'Payment intent not found' using errcode='P0002'; end if;
  if v_intent.status not in ('created','pending_provider') then raise exception 'Payment intent cannot be attached in its current state' using errcode='55000'; end if;
  if v_intent.expires_at<=now() then
    update private.payment_intents set status='expired',updated_at=now() where id=p_payment_intent_id;
    return false;
  end if;
  if v_intent.provider_code is not null then
    if v_intent.provider_code=p_provider_code and v_intent.provider_payment_ref=p_provider_payment_ref then return true; end if;
    raise exception 'Payment intent already has a different provider reference' using errcode='23505';
  end if;
  update private.payment_intents set provider_code=p_provider_code,provider_payment_ref=p_provider_payment_ref,status='pending_provider',updated_at=now() where id=p_payment_intent_id;
  return true;
end;
$$;
revoke all on function public.attach_payment_provider_reference(uuid,text,text) from public,anon,authenticated;
grant execute on function public.attach_payment_provider_reference(uuid,text,text) to service_role;

create or replace function public.ingest_verified_payment_event(
  p_provider_code text,p_provider_event_id text,p_event_type text,
  p_provider_payment_ref text,p_outcome text,p_amount_minor bigint,
  p_currency text,p_provider_transaction_ref text,p_payload_sha256 text
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_event_id uuid;
  v_existing_event private.provider_webhook_events%rowtype;
  v_intent private.payment_intents%rowtype;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if p_provider_code is null or p_provider_code !~ '^[a-z0-9][a-z0-9_-]{1,47}$'
     or p_provider_event_id is null or length(p_provider_event_id) not between 1 and 200
     or p_event_type is null or length(p_event_type) not between 1 and 120
     or p_provider_payment_ref is null or length(p_provider_payment_ref) not between 1 and 200
     or p_outcome is null or p_outcome not in ('authorized','captured','failed')
     or p_amount_minor is null or p_amount_minor<=0
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or p_provider_transaction_ref is null or length(p_provider_transaction_ref) not between 1 and 200
     or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid normalized provider event' using errcode='22023';
  end if;
  insert into private.provider_webhook_events(
    provider_code,provider_event_id,event_type,provider_payment_ref,provider_transaction_ref,outcome,amount_minor,currency,payload_sha256
  ) values(p_provider_code,p_provider_event_id,p_event_type,p_provider_payment_ref,p_provider_transaction_ref,p_outcome,p_amount_minor,p_currency,p_payload_sha256)
  on conflict(provider_code,provider_event_id) do nothing returning id into v_event_id;
  if v_event_id is null then
    select * into v_existing_event from private.provider_webhook_events where provider_code=p_provider_code and provider_event_id=p_provider_event_id;
    if v_existing_event.payload_sha256<>p_payload_sha256
       or v_existing_event.event_type<>p_event_type
       or v_existing_event.provider_payment_ref<>p_provider_payment_ref
       or v_existing_event.provider_transaction_ref<>p_provider_transaction_ref
       or v_existing_event.outcome<>p_outcome
       or v_existing_event.amount_minor<>p_amount_minor
       or v_existing_event.currency<>p_currency then
      raise exception 'Provider event ID was reused with different normalized content' using errcode='23505';
    end if;
    if v_existing_event.processing_status<>'unmatched' then
      return jsonb_build_object('event_id',v_existing_event.id,'status',v_existing_event.processing_status,'duplicate',true);
    end if;
    v_event_id:=v_existing_event.id;
  end if;
  select * into v_intent from private.payment_intents
  where provider_code=p_provider_code and provider_payment_ref=p_provider_payment_ref for update;
  if not found then
    update private.provider_webhook_events set processing_status='unmatched',processed_at=now(),error_code='payment_reference_not_found' where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'status','unmatched');
  end if;
  perform 1 from public.commerce_orders o where o.id=v_intent.order_id for update;
  update private.provider_webhook_events set payment_intent_id=v_intent.id where id=v_event_id;
  if v_intent.amount_minor<>p_amount_minor or v_intent.currency<>p_currency then
    if v_intent.status<>'captured' then update private.payment_intents set status='requires_review',updated_at=now() where id=v_intent.id; end if;
    update private.provider_webhook_events set processing_status='requires_review',processed_at=now(),error_code='amount_or_currency_mismatch' where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'status','requires_review');
  end if;
  if p_outcome='captured' and v_intent.expires_at<=now() then
    if v_intent.status<>'captured' then update private.payment_intents set status='requires_review',updated_at=now() where id=v_intent.id; end if;
    update private.provider_webhook_events set processing_status='requires_review',processed_at=now(),error_code='capture_after_intent_expiry' where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'status','requires_review');
  end if;
  if p_outcome='captured' then
    if v_intent.status in ('failed','expired','cancelled','requires_review') then
      update private.provider_webhook_events set processing_status='requires_review',processed_at=now(),error_code='late_or_exception_capture' where id=v_event_id;
      if v_intent.status<>'requires_review' then update private.payment_intents set status='requires_review',updated_at=now() where id=v_intent.id; end if;
      return jsonb_build_object('event_id',v_event_id,'status','requires_review');
    end if;
    if v_intent.status='captured' then
      update private.provider_webhook_events set processing_status='requires_review',processed_at=now(),error_code='additional_capture_for_captured_intent' where id=v_event_id;
      return jsonb_build_object('event_id',v_event_id,'status','requires_review');
    end if;
  elsif p_outcome='authorized' then
    if v_intent.status<>'pending_provider' then
      update private.provider_webhook_events set processing_status='requires_review',processed_at=now(),error_code='unexpected_authorization_state' where id=v_event_id;
      return jsonb_build_object('event_id',v_event_id,'status','requires_review');
    end if;
  elsif p_outcome='failed' and v_intent.status in ('captured','authorized') then
    update private.provider_webhook_events set processing_status='requires_review',processed_at=now(),error_code=case when v_intent.status='captured' then 'failure_after_capture' else 'failure_after_authorization' end where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'status','requires_review');
  end if;
  begin
    insert into private.payment_transactions(payment_intent_id,provider_code,provider_transaction_ref,transaction_kind,amount_minor,currency,provider_event_id)
    values(v_intent.id,p_provider_code,p_provider_transaction_ref,p_outcome,p_amount_minor,p_currency,p_provider_event_id);
  exception when unique_violation then
    if v_intent.status<>'captured' then update private.payment_intents set status='requires_review',updated_at=now() where id=v_intent.id; end if;
    update private.provider_webhook_events set processing_status='requires_review',processed_at=now(),error_code='provider_transaction_reference_reused' where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'status','requires_review');
  end;
  update private.payment_intents
  set status=case p_outcome when 'captured' then 'captured' when 'authorized' then 'authorized' else 'failed' end,
      captured_at=case when p_outcome='captured' then now() else null end,updated_at=now()
  where id=v_intent.id;
  update private.provider_webhook_events set processing_status='processed',processed_at=now() where id=v_event_id;
  return jsonb_build_object('event_id',v_event_id,'status','processed','payment_intent_id',v_intent.id);
end;
$$;
revoke all on function public.ingest_verified_payment_event(text,text,text,text,text,bigint,text,text,text) from public,anon,authenticated;
grant execute on function public.ingest_verified_payment_event(text,text,text,text,text,bigint,text,text,text) to service_role;

create or replace function public.expire_stale_payment_intents()
returns integer language plpgsql security definer set search_path=''
as $$
declare v_count integer;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  update private.payment_intents set status='expired',updated_at=now()
  where status in ('created','pending_provider') and expires_at<=now();
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.expire_stale_payment_intents() from public,anon,authenticated;
grant execute on function public.expire_stale_payment_intents() to service_role;

create or replace function public.create_finance_account(p_account_code text,p_account_name text,p_account_type text,p_currency text,p_normal_balance text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if p_account_code is null or p_account_code !~ '^[A-Z0-9][A-Z0-9._-]{1,47}$'
     or length(btrim(coalesce(p_account_name,''))) not between 2 and 120
     or p_account_type is null or p_account_type not in ('asset','liability','equity','revenue','expense')
     or (p_account_type in ('asset','expense') and p_normal_balance<>'debit')
     or (p_account_type in ('liability','equity','revenue') and p_normal_balance<>'credit')
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or p_normal_balance is null or p_normal_balance not in ('debit','credit') then
    raise exception 'Invalid finance account definition' using errcode='22023';
  end if;
  insert into private.finance_accounts(account_code,account_name,account_type,currency,normal_balance)
  values(p_account_code,p_account_name,p_account_type,p_currency,p_normal_balance)
  on conflict(account_code,currency) do update set account_name=excluded.account_name,account_type=excluded.account_type,normal_balance=excluded.normal_balance
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.create_finance_account(text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.create_finance_account(text,text,text,text,text) to service_role;

create or replace function public.post_finance_journal(
  p_entry_ref text,p_source_type text,p_source_id uuid,p_currency text,
  p_description text,p_lines jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  v_existing private.finance_journals%rowtype;
  v_journal_id uuid;
  v_line jsonb;
  v_line_no integer:=0;
  v_debits numeric:=0;
  v_credits numeric:=0;
  v_account_currency text;
  v_account_active boolean;
  v_debit bigint;
  v_credit bigint;
  v_fingerprint text;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if p_entry_ref is null or length(p_entry_ref) not between 8 and 160
     or p_source_type is null or p_source_type not in ('payment_capture','refund','commission','seller_payable','payout','provider_fee','tax','chargeback','manual_adjustment','fx_conversion')
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or length(btrim(coalesce(p_description,''))) not between 3 and 500
     or p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 2 and 100 then
    raise exception 'Invalid journal request' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_entry_ref));
  v_fingerprint:=md5(jsonb_build_object('source_type',p_source_type,'source_id',p_source_id,'currency',p_currency,'description',p_description,'lines',p_lines)::text);
  select * into v_existing from private.finance_journals where entry_ref=p_entry_ref;
  if found then
    if v_existing.request_fingerprint<>v_fingerprint then raise exception 'Journal entry reference reused with different content' using errcode='23505'; end if;
    return v_existing.id;
  end if;
  insert into private.finance_journals(entry_ref,source_type,source_id,currency,description,request_fingerprint,status,created_by)
  values(p_entry_ref,p_source_type,p_source_id,p_currency,p_description,v_fingerprint,'draft',auth.uid())
  returning id into v_journal_id;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_line_no:=v_line_no+1;
    if jsonb_typeof(v_line)<>'object' or coalesce(v_line->>'account_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Invalid journal line account' using errcode='22023';
    end if;
    v_debit:=coalesce(nullif(v_line->>'debit_minor','')::bigint,0);
    v_credit:=coalesce(nullif(v_line->>'credit_minor','')::bigint,0);
    if v_debit<0 or v_credit<0 or not ((v_debit>0 and v_credit=0) or (v_credit>0 and v_debit=0)) then
      raise exception 'Each journal line must contain either a positive debit or a positive credit' using errcode='22023';
    end if;
    select currency,is_active into v_account_currency,v_account_active from private.finance_accounts where id=(v_line->>'account_id')::uuid;
    if not found or not v_account_active or v_account_currency<>p_currency then
      raise exception 'Journal account is missing, inactive or in another currency' using errcode='22023';
    end if;
    insert into private.finance_journal_lines(journal_id,line_no,account_id,debit_minor,credit_minor,memo)
    values(v_journal_id,v_line_no,(v_line->>'account_id')::uuid,v_debit,v_credit,nullif(left(coalesce(v_line->>'memo',''),240),''));
    v_debits:=v_debits+v_debit;
    v_credits:=v_credits+v_credit;
  end loop;
  if v_line_no<2 or v_debits<=0 or v_debits<>v_credits then raise exception 'Journal is not balanced' using errcode='23514'; end if;
  update private.finance_journals set status='posted',posted_at=now() where id=v_journal_id;
  return v_journal_id;
end;
$$;
revoke all on function public.post_finance_journal(text,text,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.post_finance_journal(text,text,uuid,text,text,jsonb) to service_role;

create or replace function public.reverse_finance_journal(p_original_journal_id uuid,p_entry_ref text,p_description text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_original private.finance_journals%rowtype;
  v_reversal_id uuid;
  v_fingerprint text;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if p_entry_ref is null or length(p_entry_ref) not between 8 and 160 or length(btrim(coalesce(p_description,''))) not between 3 and 500 then
    raise exception 'Invalid reversal request' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_entry_ref));
  select * into v_original from private.finance_journals where id=p_original_journal_id for update;
  if not found or v_original.status<>'posted' then raise exception 'Only a posted journal can be reversed' using errcode='55000'; end if;
  if exists(select 1 from private.finance_journals where reversal_of=p_original_journal_id) then
    select id into v_reversal_id from private.finance_journals where reversal_of=p_original_journal_id;
    return v_reversal_id;
  end if;
  v_fingerprint:=md5('reversal:'||p_original_journal_id::text||':'||p_description);
  insert into private.finance_journals(entry_ref,source_type,source_id,currency,description,request_fingerprint,status,reversal_of,created_by)
  values(p_entry_ref,'manual_adjustment',p_original_journal_id,v_original.currency,p_description,v_fingerprint,'draft',p_original_journal_id,auth.uid())
  returning id into v_reversal_id;
  insert into private.finance_journal_lines(journal_id,line_no,account_id,debit_minor,credit_minor,memo)
  select v_reversal_id,line_no,account_id,credit_minor,debit_minor,coalesce(memo,'Reversal') from private.finance_journal_lines where journal_id=p_original_journal_id order by line_no;
  if not exists(select 1 from private.finance_journal_lines where journal_id=v_reversal_id) then raise exception 'Original journal has no lines' using errcode='23514'; end if;
  update private.finance_journals set status='posted',posted_at=now() where id=v_reversal_id;
  return v_reversal_id;
end;
$$;
revoke all on function public.reverse_finance_journal(uuid,text,text) from public,anon,authenticated;
grant execute on function public.reverse_finance_journal(uuid,text,text) to service_role;

create or replace function private.prevent_posted_journal_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_status text;
begin
  if tg_table_name='finance_journals' then
    if (tg_op='DELETE' and old.status='posted') or (tg_op='UPDATE' and old.status='posted') then
      raise exception 'Posted finance journals are immutable' using errcode='55000';
    end if;
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if tg_op='DELETE' then
    select status into v_status from private.finance_journals where id=old.journal_id;
  elsif tg_op='INSERT' then
    select status into v_status from private.finance_journals where id=new.journal_id;
  else
    select status into v_status from private.finance_journals where id=old.journal_id;
    if v_status<>'posted' then
      select status into v_status from private.finance_journals where id=new.journal_id;
    end if;
  end if;
  if v_status='posted' then raise exception 'Lines belonging to posted finance journals are immutable' using errcode='55000'; end if;
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function private.prevent_posted_journal_mutation() from public,anon,authenticated;
create trigger finance_journals_immutable before update or delete on private.finance_journals for each row execute function private.prevent_posted_journal_mutation();
create trigger finance_journal_lines_immutable before insert or update or delete on private.finance_journal_lines for each row execute function private.prevent_posted_journal_mutation();

create or replace function private.prevent_finance_account_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='DELETE' then raise exception 'Finance accounts cannot be deleted; deactivate them instead' using errcode='55000'; end if;
  if old.account_code<>new.account_code or old.currency<>new.currency or old.account_type<>new.account_type or old.normal_balance<>new.normal_balance then
    raise exception 'Finance account identity and classification are immutable' using errcode='55000';
  end if;
  return new;
end;
$$;
revoke all on function private.prevent_finance_account_mutation() from public,anon,authenticated;
create trigger finance_accounts_guard before update or delete on private.finance_accounts for each row execute function private.prevent_finance_account_mutation();

commit;
