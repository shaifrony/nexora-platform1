\set ON_ERROR_STOP on
\pset pager off

-- Focused PostgreSQL integration harness for the staged Buyer Demand negotiation migration.
-- Uses a disposable CI database and minimal compatible fixtures; this is NOT a full Supabase stack.

create extension if not exists pgcrypto;

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

create table public.profiles (
  id uuid primary key,
  role text not null,
  account_status text not null
);

create table public.public_businesses (
  seller_id uuid not null references public.profiles(id)
);

create table public.buyer_demands (
  id uuid primary key,
  buyer_id uuid not null references public.profiles(id),
  demand_status text not null default 'open',
  required_quantity text not null,
  currency text not null,
  destination_city text not null,
  destination_country text not null,
  subcategory text
);
alter table public.buyer_demands enable row level security;
create policy buyer_demands_fixture_owner_read on public.buyer_demands
  for select to authenticated using (buyer_id=(select auth.uid()));
create policy buyer_demands_fixture_owner_update on public.buyer_demands
  for update to authenticated
  using (buyer_id=(select auth.uid()) and demand_status='open')
  with check (buyer_id=(select auth.uid()));
grant select,update on public.buyer_demands to authenticated;
grant update (subcategory) on public.buyer_demands to authenticated;

create table public.seller_offers (
  id uuid primary key default gen_random_uuid(),
  demand_id uuid not null references public.buyer_demands(id),
  seller_id uuid not null references public.profiles(id),
  offer_price numeric(18,2) not null,
  currency text not null,
  available_quantity text not null,
  message text,
  offer_status text not null default 'pending',
  price_basis text not null default 'per_unit',
  delivery_charge numeric(18,2) not null default 0,
  offer_valid_until date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.seller_offers enable row level security;
create policy seller_offers_fixture_participant_read on public.seller_offers
  for select to authenticated
  using (
    seller_id=(select auth.uid())
    or exists(select 1 from public.buyer_demands d
      where d.id=seller_offers.demand_id and d.buyer_id=(select auth.uid()))
  );
grant select on public.seller_offers to authenticated;

create table public.commerce_orders (
  id uuid primary key default gen_random_uuid(),
  order_code text not null default ('NXO-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  listing_type text not null,
  listing_id uuid not null,
  buyer_id uuid not null references public.profiles(id),
  seller_id uuid not null references public.profiles(id),
  quantity numeric(18,3) not null,
  unit_price numeric(18,2) not null,
  total_price numeric(18,2) generated always as (round(quantity*unit_price,2)) stored,
  currency text not null,
  fulfilment_location text not null,
  buyer_note text,
  seller_note text,
  order_status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  ready_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  constraint commerce_orders_listing_type_check check (listing_type in ('product','service')),
  constraint commerce_orders_status_check check (order_status in ('pending','accepted','ready_for_confirmation','completed','cancelled','rejected')),
  constraint commerce_orders_completed_at_check check ((order_status='completed')=(completed_at is not null)),
  constraint commerce_orders_cancelled_at_check check ((order_status='cancelled')=(cancelled_at is not null))
);

create table public.commerce_order_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.commerce_orders(id),
  actor_user_id uuid not null references public.profiles(id),
  event_type text not null,
  note text,
  created_at timestamptz not null default now()
);

-- Execute the exact staged migration against the disposable fixture schema.
\ir ../supabase/migrations/20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql

insert into public.profiles(id,role,account_status) values
  ('10000000-0000-4000-8000-000000000001','buyer','active'),
  ('10000000-0000-4000-8000-000000000002','buyer','active'),
  ('10000000-0000-4000-8000-000000000011','seller','active'),
  ('10000000-0000-4000-8000-000000000012','seller','active');

insert into public.public_businesses(seller_id) values
  ('10000000-0000-4000-8000-000000000011'),
  ('10000000-0000-4000-8000-000000000012');

insert into public.buyer_demands(id,buyer_id,required_quantity,currency,destination_city,destination_country)
values
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','5,000 KG','BDT','Dhaka','Bangladesh'),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','100 units','BDT','Dhaka','Bangladesh'),
  ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','KG only','BDT','Dhaka','Bangladesh'),
  ('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001','80 units','BDT','Dhaka','Bangladesh'),
  ('20000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000001','50 units','BDT','Dhaka','Bangladesh'),
  ('20000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000001','30 units','BDT','Dhaka','Bangladesh');

do $test$
declare
  v_offer uuid;
  v_order uuid;
  v_status text;
  v_qty numeric;
  v_total numeric;
  v_denied boolean;
begin
  -- Spoofed client-supplied negotiation fields must be reset by the INSERT trigger.
  insert into public.seller_offers(
    id,demand_id,seller_id,offer_price,currency,available_quantity,
    negotiation_status,last_negotiator_id,accepted_quantity,accepted_unit_price,demand_order_id
  ) values (
    '30000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011',
    100,'BDT','6000','ordered',
    '10000000-0000-4000-8000-000000000001',99,1,
    '40000000-0000-4000-8000-000000000099'
  ) returning id into v_offer;

  if not exists(
    select 1 from public.seller_offers
    where id=v_offer and negotiation_status='open'
      and last_negotiator_id=seller_id
      and accepted_quantity is null and accepted_unit_price is null and demand_order_id is null
      and current_quantity=6000 and current_unit_price=100
  ) then
    raise exception 'FAIL: initial quotation accepted forged protected state';
  end if;

  if (select count(*) from public.seller_offer_negotiations where offer_id=v_offer)<>1 then
    raise exception 'FAIL: initial Seller quote event was not logged';
  end if;

  -- A Buyer accepts no more than the numeric portion of "5,000 KG".
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
  v_order:=public.respond_to_demand_offer(v_offer,'accept',5000,null,'Accept requested quantity');
  select order_status,quantity,source_offer_total into v_status,v_qty,v_total
  from public.commerce_orders where id=v_order;
  if v_status<>'pending' or v_qty<>5000 or v_total<>500000 then
    raise exception 'FAIL: Buyer acceptance produced wrong order status, quantity or agreed total';
  end if;
  if (select grand_total from public.commerce_orders where id=v_order)<>500000 then
    raise exception 'FAIL: generated grand total is incorrect';
  end if;

  -- Only the assigned Seller may accept and mark ready; only Buyer may complete.
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000011',true);
  perform public.transition_buyer_demand_order(v_order,'accept','Seller accepted');
  perform public.transition_buyer_demand_order(v_order,'ready','Goods dispatched');
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
  perform public.transition_buyer_demand_order(v_order,'complete','Goods received');
  if (select order_status from public.commerce_orders where id=v_order)<>'completed' then
    raise exception 'FAIL: Buyer/Seller order lifecycle did not complete';
  end if;
  if (select count(*) from public.commerce_order_events where order_id=v_order)<>4 then
    raise exception 'FAIL: expected four order lifecycle events';
  end if;

  -- The same quotation cannot create a second order.
  v_denied:=false;
  begin
    perform public.respond_to_demand_offer(v_offer,'accept',5000,null,null);
  exception when raise_exception then
    v_denied:=true;
  end;
  if not v_denied then raise exception 'FAIL: duplicate quotation acceptance was allowed'; end if;

  -- Exercise the opposite turn: Buyer counter-offer followed by Seller acceptance.
  insert into public.seller_offers(
    id,demand_id,seller_id,offer_price,currency,available_quantity
  ) values (
    '30000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000012',
    120,'BDT','100'
  ) returning id into v_offer;
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
  perform public.respond_to_demand_offer(v_offer,'counter',70,90,'Buyer counter');
  v_denied:=false;
  begin
    perform public.respond_to_demand_offer(v_offer,'counter',60,85,'Repeated Buyer counter');
  exception when raise_exception then
    v_denied:=true;
  end;
  if not v_denied then raise exception 'FAIL: Buyer sent a second counter without Seller response'; end if;
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000012',true);
  v_order:=public.respond_to_demand_offer(v_offer,'accept',null,null,'Seller accepts Buyer counter');
  select order_status,quantity,source_offer_total into v_status,v_qty,v_total
  from public.commerce_orders where id=v_order;
  if v_status<>'accepted' or v_qty<>70 or v_total<>6300 then
    raise exception 'FAIL: Seller acceptance of Buyer counter produced incorrect order';
  end if;
  if not exists(select 1 from public.seller_offers where id=v_offer
      and negotiation_status='ordered' and accepted_quantity=70 and accepted_unit_price=90) then
    raise exception 'FAIL: accepted Buyer counter terms were not saved on quotation';
  end if;
  perform public.transition_buyer_demand_order(v_order,'ready','Seller dispatches counter order');
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
  perform public.transition_buyer_demand_order(v_order,'complete','Buyer received counter order');

  -- An unrelated Buyer cannot accept another Buyer's quotation.
  insert into public.seller_offers(demand_id,seller_id,offer_price,currency,available_quantity)
  values('20000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000011',20,'BDT','50')
  returning id into v_offer;
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
  v_denied:=false;
  begin
    perform public.respond_to_demand_offer(v_offer,'accept',50,null,null);
  exception when insufficient_privilege then
    v_denied:=true;
  end;
  if not v_denied then raise exception 'FAIL: unrelated Buyer accepted a quotation owned by another Buyer'; end if;

  -- Buyer cancellation is allowed only while the generated order is pending.
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
  v_order:=public.respond_to_demand_offer(v_offer,'accept',50,null,null);
  perform public.transition_buyer_demand_order(v_order,'cancel','Buyer cancelled before dispatch');
  if (select order_status from public.commerce_orders where id=v_order)<>'cancelled' then
    raise exception 'FAIL: Buyer could not cancel own pending Demand order';
  end if;

  -- Seller rejection requires a reason and applies only to a pending order.
  insert into public.seller_offers(demand_id,seller_id,offer_price,currency,available_quantity)
  values('20000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000011',30,'BDT','30')
  returning id into v_offer;
  v_order:=public.respond_to_demand_offer(v_offer,'accept',30,null,null);
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000011',true);
  perform public.transition_buyer_demand_order(v_order,'reject','Out of stock');
  if (select order_status from public.commerce_orders where id=v_order)<>'rejected' then
    raise exception 'FAIL: assigned Seller could not reject pending Demand order';
  end if;

  -- Currency must match the Buyer Demand currency.
  v_denied:=false;
  begin
    insert into public.seller_offers(demand_id,seller_id,offer_price,currency,available_quantity)
    values('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000011',10,'USD','10');
  exception when sqlstate '22023' then v_denied:=true;
  end;
  if not v_denied then raise exception 'FAIL: mismatched quotation currency was accepted'; end if;

  -- Invalid Buyer quantity is rejected before a Seller quote can be created.
  v_denied:=false;
  begin
    insert into public.seller_offers(demand_id,seller_id,offer_price,currency,available_quantity)
    values('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000011',10,'BDT','10');
  exception when sqlstate '22023' then v_denied:=true;
  end;
  if not v_denied then raise exception 'FAIL: invalid Buyer Demand quantity accepted a Seller quote'; end if;

  -- Seller approval is rechecked at the point of negotiation/order creation.
  insert into public.seller_offers(demand_id,seller_id,offer_price,currency,available_quantity)
  values('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000012',10,'BDT','10')
  returning id into v_offer;
  delete from public.public_businesses where seller_id='10000000-0000-4000-8000-000000000012';
  v_denied:=false;
  begin
    perform public.respond_to_demand_offer(v_offer,'accept',10,null,null);
  exception when insufficient_privilege then v_denied:=true;
  end;
  if not v_denied then raise exception 'FAIL: Buyer accepted a quote from a Seller without approved Business Profile'; end if;

  -- Table-level UPDATE is gone; only lifecycle status remains writable.
  if has_table_privilege('authenticated','public.buyer_demands','UPDATE')
     or has_column_privilege('authenticated','public.buyer_demands','required_quantity','UPDATE')
     or has_column_privilege('authenticated','public.buyer_demands','currency','UPDATE')
     or not has_column_privilege('authenticated','public.buyer_demands','demand_status','UPDATE') then
    raise exception 'FAIL: Buyer Demand column update privileges are not restricted as intended';
  end if;

  raise notice 'PASS: Buyer Demand quote spoofing, quantity parser/cap, currency, Seller approval, order conversion, transitions and update grants';
end
$test$;

-- Participant-only negotiation history: Buyer owner can read; unrelated Buyer cannot.
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
do $rls_buyer_owner$
begin
  if (select count(*) from public.seller_offer_negotiations
      where offer_id='30000000-0000-4000-8000-000000000001')<>2 then
    raise exception 'FAIL: Buyer owner cannot read its negotiation history';
  end if;
  if has_table_privilege('authenticated','public.seller_offer_negotiations','INSERT')
     or has_function_privilege('anon','public.respond_to_demand_offer(uuid,text,numeric,numeric,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.respond_to_demand_offer(uuid,text,numeric,numeric,text)','EXECUTE') then
    raise exception 'FAIL: negotiation table/RPC grants are not least-privilege';
  end if;
end
$rls_buyer_owner$;

do $buyer_demand_update_rights$
declare
  v_denied boolean:=false;
begin
  update public.buyer_demands set demand_status='closed'
  where id='20000000-0000-4000-8000-000000000004';
  if not found then raise exception 'FAIL: Buyer could not update own Demand lifecycle status'; end if;

  begin
    execute 'update public.buyer_demands set currency=''USD'' where id=''20000000-0000-4000-8000-000000000004''';
  exception when insufficient_privilege then
    v_denied:=true;
  end;
  if not v_denied then raise exception 'FAIL: Buyer changed protected Demand currency'; end if;
end
$buyer_demand_update_rights$;

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000012',false);
do $rls_seller_owner$
begin
  if (select count(*) from public.buyer_demands)<>0 then
    raise exception 'FAIL: Seller can read a closed Buyer Demand outside its routed inbox';
  end if;
  if (select count(*) from public.seller_offer_negotiations
      where offer_id='30000000-0000-4000-8000-000000000002')<>3 then
    raise exception 'FAIL: Seller lost access to own negotiation history after Demand closure';
  end if;
end
$rls_seller_owner$;

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
do $rls_other_buyer$
begin
  if (select count(*) from public.seller_offer_negotiations)<>0 then
    raise exception 'FAIL: unrelated Buyer can read another Buyer negotiation history';
  end if;
end
$rls_other_buyer$;
reset role;
