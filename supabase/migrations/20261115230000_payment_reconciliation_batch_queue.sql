-- Provider-neutral transaction reconciliation inbox. No settlement or fund movement occurs here.
begin;

create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated,service_role;

create table private.payment_reconciliation_batches (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9][a-z0-9_-]{1,47}$'),
  statement_ref text not null check (length(statement_ref) between 1 and 200),
  period_start timestamptz not null,
  period_end timestamptz not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  row_count integer not null default 0 check (row_count between 1 and 10000),
  matched_count integer not null default 0 check (matched_count between 0 and row_count),
  exception_count integer not null default 0 check (exception_count between 0 and row_count),
  status text not null default 'review_required' check (status in ('matched','review_required','reviewed')),
  imported_by uuid references public.profiles(id) on delete set null,
  imported_at timestamptz not null default now(),
  reviewed_at timestamptz,
  check (period_end>period_start),
  check (row_count=matched_count+exception_count),
  check ((status='reviewed')=(reviewed_at is not null)),
  unique(provider_code,statement_ref)
);
create index payment_reconciliation_batches_status_idx
  on private.payment_reconciliation_batches(status,imported_at desc);

create table private.payment_reconciliation_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references private.payment_reconciliation_batches(id) on delete restrict,
  row_no integer not null check (row_no between 1 and 10000),
  provider_transaction_ref text not null check (length(provider_transaction_ref) between 1 and 200),
  provider_event_id text check (provider_event_id is null or length(provider_event_id) between 1 and 200),
  provider_status text not null check (provider_status in ('authorized','captured','failed')),
  amount_minor bigint not null check (amount_minor>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  payment_transaction_id uuid references private.payment_transactions(id) on delete restrict,
  payment_intent_id uuid references private.payment_intents(id) on delete restrict,
  match_status text not null check (match_status in ('matched','unmatched_provider_transaction','amount_mismatch','currency_mismatch','state_mismatch','event_mismatch','duplicate_provider_transaction')),
  review_status text not null default 'open' check (review_status in ('not_required','open','resolved','dismissed')),
  review_note text check (review_note is null or length(review_note)<=500),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(batch_id,row_no),
  check ((match_status='matched')=(review_status='not_required')),
  check ((review_status in ('resolved','dismissed'))=(reviewed_at is not null))
);
create index payment_reconciliation_rows_batch_idx
  on private.payment_reconciliation_rows(batch_id,row_no);
create index payment_reconciliation_rows_open_idx
  on private.payment_reconciliation_rows(batch_id,match_status)
  where review_status='open';
create index payment_reconciliation_rows_transaction_idx
  on private.payment_reconciliation_rows(payment_transaction_id)
  where payment_transaction_id is not null;

alter table private.payment_reconciliation_batches enable row level security;
alter table private.payment_reconciliation_rows enable row level security;
revoke all on private.payment_reconciliation_batches,private.payment_reconciliation_rows
  from public,anon,authenticated;

create or replace function public.ingest_payment_reconciliation_batch(
  p_provider_code text,p_statement_ref text,p_period_start timestamptz,
  p_period_end timestamptz,p_currency text,p_source_sha256 text,p_rows jsonb
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_batch_id uuid;
  v_existing private.payment_reconciliation_batches%rowtype;
  v_row jsonb;
  v_row_no integer:=0;
  v_provider_ref text;
  v_provider_event_id text;
  v_provider_status text;
  v_amount_minor bigint;
  v_currency text;
  v_match_status text;
  v_transaction private.payment_transactions%rowtype;
  v_matched_count integer:=0;
  v_exception_count integer:=0;
  v_duplicate boolean;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if p_provider_code is null or p_provider_code !~ '^[a-z0-9][a-z0-9_-]{1,47}$'
     or p_statement_ref is null or length(p_statement_ref) not between 1 and 200
     or p_period_start is null or p_period_end is null or p_period_end<=p_period_start
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or p_source_sha256 is null or p_source_sha256 !~ '^[0-9a-f]{64}$'
     or p_rows is null or jsonb_typeof(p_rows)<>'array'
     or jsonb_array_length(p_rows) not between 1 and 10000 then
    raise exception 'Invalid reconciliation batch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_provider_code||':'||p_statement_ref));
  insert into private.payment_reconciliation_batches(
    provider_code,statement_ref,period_start,period_end,currency,source_sha256,row_count,exception_count,imported_by
  ) values(
    p_provider_code,p_statement_ref,p_period_start,p_period_end,p_currency,p_source_sha256,
    jsonb_array_length(p_rows),jsonb_array_length(p_rows),auth.uid()
  ) on conflict(provider_code,statement_ref) do nothing returning id into v_batch_id;
  if v_batch_id is null then
    select * into v_existing from private.payment_reconciliation_batches
    where provider_code=p_provider_code and statement_ref=p_statement_ref;
    if v_existing.source_sha256<>p_source_sha256
       or v_existing.period_start<>p_period_start or v_existing.period_end<>p_period_end
       or v_existing.currency<>p_currency or v_existing.row_count<>jsonb_array_length(p_rows) then
      raise exception 'Statement reference was reused with different content' using errcode='23505';
    end if;
    return jsonb_build_object('batch_id',v_existing.id,'status',v_existing.status,'duplicate',true,
      'row_count',v_existing.row_count,'matched_count',v_existing.matched_count,'exception_count',v_existing.exception_count);
  end if;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_row_no:=v_row_no+1;
    if jsonb_typeof(v_row)<>'object' then raise exception 'Reconciliation row must be an object' using errcode='22023'; end if;
    v_provider_ref:=v_row->>'provider_transaction_ref';
    v_provider_event_id:=nullif(v_row->>'provider_event_id','');
    v_provider_status:=v_row->>'provider_status';
    v_amount_minor:=nullif(v_row->>'amount_minor','')::bigint;
    v_currency:=v_row->>'currency';
    if v_provider_ref is null or length(v_provider_ref) not between 1 and 200
       or (v_provider_event_id is not null and length(v_provider_event_id)>200)
       or v_provider_status is null or v_provider_status not in ('authorized','captured','failed')
       or v_amount_minor is null or v_amount_minor<=0
       or v_currency is null or v_currency !~ '^[A-Z]{3}$' then
      raise exception 'Invalid normalized reconciliation row %',v_row_no using errcode='22023';
    end if;

    v_match_status:=null;
    v_duplicate:=exists(
      select 1 from private.payment_reconciliation_rows r
      where r.batch_id=v_batch_id and r.provider_transaction_ref=v_provider_ref
    );
    v_transaction:=null;
    if v_duplicate then
      v_match_status:='duplicate_provider_transaction';
    else
      select * into v_transaction from private.payment_transactions t
      where t.provider_code=p_provider_code and t.provider_transaction_ref=v_provider_ref;
      if not found then
        v_match_status:='unmatched_provider_transaction';
      elsif v_currency<>p_currency or v_transaction.currency<>v_currency then
        v_match_status:='currency_mismatch';
      elsif v_transaction.amount_minor<>v_amount_minor then
        v_match_status:='amount_mismatch';
      elsif v_transaction.transaction_kind<>v_provider_status then
        v_match_status:='state_mismatch';
      elsif v_provider_event_id is not null and v_transaction.provider_event_id<>v_provider_event_id then
        v_match_status:='event_mismatch';
      else
        v_match_status:='matched';
      end if;
    end if;

    insert into private.payment_reconciliation_rows(
      batch_id,row_no,provider_transaction_ref,provider_event_id,provider_status,
      amount_minor,currency,payment_transaction_id,payment_intent_id,match_status,review_status
    ) values(
      v_batch_id,v_row_no,v_provider_ref,v_provider_event_id,v_provider_status,
      v_amount_minor,v_currency,
      case when v_match_status in ('matched','amount_mismatch','currency_mismatch','state_mismatch','event_mismatch') then v_transaction.id else null end,
      case when v_match_status in ('matched','amount_mismatch','currency_mismatch','state_mismatch','event_mismatch') then v_transaction.payment_intent_id else null end,
      v_match_status,case when v_match_status='matched' then 'not_required' else 'open' end
    );
    if v_match_status='matched' then v_matched_count:=v_matched_count+1; else v_exception_count:=v_exception_count+1; end if;
  end loop;

  update private.payment_reconciliation_batches
  set matched_count=v_matched_count,exception_count=v_exception_count,
      status=case when v_exception_count=0 then 'matched' else 'review_required' end
  where id=v_batch_id;
  return jsonb_build_object('batch_id',v_batch_id,
    'status',case when v_exception_count=0 then 'matched' else 'review_required' end,
    'duplicate',false,'row_count',v_row_no,'matched_count',v_matched_count,'exception_count',v_exception_count);
end;
$$;
revoke all on function public.ingest_payment_reconciliation_batch(text,text,timestamptz,timestamptz,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.ingest_payment_reconciliation_batch(text,text,timestamptz,timestamptz,text,text,jsonb)
  to service_role;

create or replace function public.get_payment_reconciliation_batch(p_batch_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'batch',to_jsonb(b),
    'rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.row_no)
      from private.payment_reconciliation_rows r where r.batch_id=b.id),'[]'::jsonb)
  ) into v_result
  from private.payment_reconciliation_batches b where b.id=p_batch_id;
  if v_result is null then raise exception 'Reconciliation batch not found' using errcode='P0002'; end if;
  return v_result;
end;
$$;
revoke all on function public.get_payment_reconciliation_batch(uuid) from public,anon,authenticated;
grant execute on function public.get_payment_reconciliation_batch(uuid) to service_role;

create or replace function public.review_payment_reconciliation_exception(
  p_row_id uuid,p_resolution text,p_note text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  v_row private.payment_reconciliation_rows%rowtype;
  v_batch_id uuid;
  v_open_count integer;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if p_resolution is null or p_resolution not in ('resolved','dismissed') or length(btrim(coalesce(p_note,''))) not between 10 and 500 then
    raise exception 'Resolution and a 10-500 character note are required' using errcode='22023';
  end if;
  select * into v_row from private.payment_reconciliation_rows where id=p_row_id for update;
  if not found then raise exception 'Reconciliation exception not found' using errcode='P0002'; end if;
  if v_row.match_status='matched' then raise exception 'Matched rows do not require exception review' using errcode='55000'; end if;
  if v_row.review_status<>'open' then
    if v_row.review_status=p_resolution and v_row.review_note=p_note then return v_row.batch_id; end if;
    raise exception 'Reconciliation exception has already been reviewed' using errcode='55000';
  end if;
  update private.payment_reconciliation_rows
  set review_status=p_resolution,review_note=p_note,reviewed_by=auth.uid(),reviewed_at=now()
  where id=p_row_id;
  v_batch_id:=v_row.batch_id;
  select count(*) into v_open_count from private.payment_reconciliation_rows
  where batch_id=v_batch_id and review_status='open';
  if v_open_count=0 then
    update private.payment_reconciliation_batches set status='reviewed',reviewed_at=now() where id=v_batch_id;
  end if;
  return v_batch_id;
end;
$$;
revoke all on function public.review_payment_reconciliation_exception(uuid,text,text) from public,anon,authenticated;
grant execute on function public.review_payment_reconciliation_exception(uuid,text,text) to service_role;

commit;
