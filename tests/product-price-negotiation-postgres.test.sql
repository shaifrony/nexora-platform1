\set ON_ERROR_STOP on
\pset pager off

-- Disposable PostgreSQL fixture for the staged Product Price Negotiation migration.
-- This validates the exact migration against minimal compatible tables, not a full Supabase stack.

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

create extension if not exists pgcrypto;
create schema if not exists auth;
create schema if not exists private;

create or replace function auth.uid()
returns uuid language sql stable set search_path=''
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;

create table public.profiles(
 id uuid primary key, role text not null, account_status text not null
);
create table public.public_businesses(business_id uuid primary key);
create table public.products(
 id uuid primary key, seller_id uuid not null references public.profiles(id),
 business_id uuid not null, listing_status text not null, product_name text not null,
 currency text not null, price numeric(18,2) not null,
 minimum_order_quantity numeric(18,3) not null default 1,
 stock_tracking boolean not null default false,
 stock_quantity numeric(18,3), reserved_quantity numeric(18,3) not null default 0
);
create table public.conversations(id uuid primary key default gen_random_uuid());
create table public.messages(
 id uuid primary key default gen_random_uuid(), conversation_id uuid not null references public.conversations(id),
 sender_id uuid not null references public.profiles(id), body text not null, message_type text not null
);
create table public.commerce_orders(
 id uuid primary key default gen_random_uuid(),
 listing_type text not null, listing_id uuid not null,
 buyer_id uuid not null references public.profiles(id),
 seller_id uuid not null references public.profiles(id),
 quantity numeric(18,3) not null, unit_price numeric(18,2) not null,
 currency text not null, fulfilment_location text not null, buyer_note text,
 order_status text not null default 'pending',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.commerce_order_events(
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.commerce_orders(id),
 actor_user_id uuid not null references public.profiles(id), event_type text not null,
 note text, created_at timestamptz not null default now()
);

create or replace function private.create_product_inquiry(p_product_id uuid,p_existing_conversation_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 insert into public.conversations default values returning id into v_id;
 return v_id;
end;
$$;

\ir ../supabase/migrations/20261115110000_product_price_negotiation.sql
\ir ../supabase/migrations/20261115210000_active_commerce_participant_guard.sql

insert into public.profiles(id,role,account_status) values
 ('51000000-0000-4000-8000-000000000001','buyer','active'),
 ('51000000-0000-4000-8000-000000000011','seller','active'),
 ('51000000-0000-4000-8000-000000000099','buyer','active');
insert into public.public_businesses(business_id) values
 ('52000000-0000-4000-8000-000000000001');
insert into public.products(
 id,seller_id,business_id,listing_status,product_name,currency,price,
 minimum_order_quantity,stock_tracking,stock_quantity,reserved_quantity
) values (
 '53000000-0000-4000-8000-000000000001',
 '51000000-0000-4000-8000-000000000011',
 '52000000-0000-4000-8000-000000000001',
 'approved','Wholesale Rice','BDT',100,5,true,100,0
);

do $test$
declare
 v_id uuid;
 v_order uuid;
 v_status text;
 v_qty numeric;
 v_price numeric;
 v_denied boolean;
begin
 -- Buyer starts a negotiation with a valid MOQ, stock and fulfilment location.
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
 v_id:=public.start_product_price_negotiation(
  '53000000-0000-4000-8000-000000000001',10,90,'Initial Buyer offer','Mirpur, Dhaka'
 );
 if not exists(select 1 from public.product_price_negotiations
  where id=v_id and negotiation_status='buyer_countered'
   and buyer_id=auth.uid() and quantity=10 and current_unit_price=90) then
  raise exception 'FAIL: Buyer negotiation was not created with correct initial terms';
 end if;
 if (select count(*) from public.product_price_negotiation_events where negotiation_id=v_id)<>1 then
  raise exception 'FAIL: initial negotiation event was not recorded';
 end if;

 -- The proposer cannot accept their own latest offer.
 v_denied:=false;
 begin
  perform public.respond_to_product_price_negotiation(v_id,'accept',null,null,null,null);
 exception when raise_exception then v_denied:=true;
 end;
 if not v_denied then raise exception 'FAIL: Buyer accepted own latest proposal'; end if;

 -- Null actions must be rejected, not fall through into the acceptance path.
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000011',true);
 v_denied:=false;
 begin
  perform public.respond_to_product_price_negotiation(v_id,null,null,null,null,null);
 exception when sqlstate '22023' then v_denied:=true;
 end;
 if not v_denied then raise exception 'FAIL: NULL action was not rejected'; end if;

 -- Seller counters; the next rejection attempt is checked against this Seller proposal.
 perform public.respond_to_product_price_negotiation(v_id,'counter',10,85,'Seller counter',null);
 v_denied:=false;
 begin
  perform public.respond_to_product_price_negotiation(v_id,'reject',null,null,'Self reject',null);
 exception when sqlstate '22023' then v_denied:=true;
 end;
 if not v_denied then raise exception 'FAIL: Seller rejected its own latest proposal'; end if;

 -- Buyer counters; Buyer cannot reject its own latest proposal.
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
 perform public.respond_to_product_price_negotiation(v_id,'counter',10,82,'Buyer counter',null);
 v_denied:=false;
 begin
  perform public.respond_to_product_price_negotiation(v_id,'reject',null,null,'Self reject',null);
 exception when sqlstate '22023' then v_denied:=true;
 end;
 if not v_denied then raise exception 'FAIL: Buyer rejected its own latest proposal'; end if;

 -- Only the other party accepts; agreed terms are snapshotted into the Order.
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000011',true);
 v_order:=public.respond_to_product_price_negotiation(v_id,'accept',null,null,'Accepted',null);
 select order_status,quantity,unit_price into v_status,v_qty,v_price
 from public.commerce_orders where id=v_order;
 if v_status<>'pending' or v_qty<>10 or v_price<>82 then
  raise exception 'FAIL: accepted negotiation did not create a pending Order with agreed terms';
 end if;
 if (select reserved_quantity from public.products where id='53000000-0000-4000-8000-000000000001')<>10 then
  raise exception 'FAIL: accepted negotiation did not reserve stock';
 end if;
 if not exists(select 1 from public.product_price_negotiations
  where id=v_id and negotiation_status='ordered' and order_id=v_order) then
  raise exception 'FAIL: negotiation was not linked to the generated Order';
 end if;

 -- A Buyer may reject the Seller's latest proposal even after stock becomes unavailable.
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
 v_id:=public.start_product_price_negotiation(
  '53000000-0000-4000-8000-000000000001',10,80,null,'Mirpur, Dhaka'
 );
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000011',true);
 perform public.respond_to_product_price_negotiation(v_id,'counter',10,78,null,null);
 update public.products set stock_quantity=10,reserved_quantity=10
  where id='53000000-0000-4000-8000-000000000001';
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
 perform public.respond_to_product_price_negotiation(v_id,'reject',null,null,'No agreement',null);
 if (select negotiation_status from public.product_price_negotiations where id=v_id)<>'rejected' then
  raise exception 'FAIL: Buyer could not reject Seller proposal after stock changed';
 end if;

 -- An unrelated Buyer cannot respond to another Buyer's negotiation.
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000099',true);
 v_denied:=false;
 begin
  perform public.respond_to_product_price_negotiation(v_id,'accept',null,null,null,null);
 exception when insufficient_privilege then v_denied:=true;
 end;
 if not v_denied then raise exception 'FAIL: unrelated Buyer accessed another negotiation'; end if;

 -- Buyer cannot accept a Seller proposal after the Seller account is suspended.
 update public.products set stock_quantity=100
  where id='53000000-0000-4000-8000-000000000001';
 v_id:=public.start_product_price_negotiation(
  '53000000-0000-4000-8000-000000000001',10,80,'Status guard test','Mirpur, Dhaka'
 );
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000011',true);
 perform public.respond_to_product_price_negotiation(v_id,'counter',10,78,'Seller proposal',null);
 update public.profiles set account_status='suspended'
  where id='51000000-0000-4000-8000-000000000011';
 perform set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
 v_denied:=false;
 begin
  perform public.respond_to_product_price_negotiation(v_id,'accept',null,null,'Accept suspended Seller',null);
 exception when insufficient_privilege then v_denied:=true;
 end;
 if not v_denied then raise exception 'FAIL: Buyer accepted a Product Price proposal from a suspended Seller'; end if;
 v_denied:=false;
 begin
  update public.product_price_negotiations set negotiation_status='ordered' where id=v_id;
 exception when insufficient_privilege then v_denied:=true;
 end;
 if not v_denied then raise exception 'FAIL: Product negotiation remained active after Seller suspension'; end if;
 update public.profiles set account_status='active'
  where id='51000000-0000-4000-8000-000000000011';
 if exists(select 1 from public.commerce_orders where id=(select order_id from public.product_price_negotiations where id=v_id)) then
  raise exception 'FAIL: Order was created for a suspended Seller';
 end if;

 raise notice 'PASS: product price negotiation start, turn-taking, NULL action, rejection, order snapshot, stock reservation and participant authorization';
end
$test$;

set role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',false);
do $buyer_rls$
begin
 if (select count(*) from public.product_price_negotiations)<>2 then
  raise exception 'FAIL: Buyer cannot read own negotiation rows';
 end if;
 if has_table_privilege('authenticated','public.product_price_negotiations','INSERT')
  or has_table_privilege('authenticated','public.product_price_negotiation_events','INSERT')
  or has_function_privilege('anon','public.start_product_price_negotiation(uuid,numeric,numeric,text,text)','EXECUTE')
  or has_function_privilege('anon','public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text)','EXECUTE') then
  raise exception 'FAIL: negotiation direct-write or anonymous RPC grants are too broad';
 end if;
end
$buyer_rls$;
reset role;
