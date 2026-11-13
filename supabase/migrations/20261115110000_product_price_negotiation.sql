-- Direct Marketplace product price negotiation (e.g. Seller asks 100, Buyer offers 90).
-- Development staging only. Do not apply before migration-history reconciliation.
begin;

create table if not exists public.product_price_negotiations (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  conversation_id uuid not null references public.conversations(id) on delete restrict,
  quantity numeric(18,3) not null check(quantity>0),
  current_unit_price numeric(18,2) not null check(current_unit_price>0),
  currency text not null check(currency ~ '^[A-Z]{3}$'),
  fulfilment_location text not null check(length(btrim(fulfilment_location))>=5),
  last_actor_id uuid not null references public.profiles(id) on delete restrict,
  negotiation_status text not null default 'buyer_countered'
    check(negotiation_status in ('buyer_countered','seller_countered','accepted','rejected','ordered')),
  order_id uuid references public.commerce_orders(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists product_price_negotiations_buyer_idx
  on public.product_price_negotiations(buyer_id,created_at desc);
create index if not exists product_price_negotiations_seller_idx
  on public.product_price_negotiations(seller_id,created_at desc);
create index if not exists product_price_negotiations_product_idx
  on public.product_price_negotiations(product_id,created_at desc);

create table if not exists public.product_price_negotiation_events (
  id uuid primary key default gen_random_uuid(),
  negotiation_id uuid not null references public.product_price_negotiations(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check(action in ('buyer_counter','seller_counter','accepted','rejected')),
  quantity numeric(18,3) check(quantity is null or quantity>0),
  unit_price numeric(18,2) check(unit_price is null or unit_price>0),
  note text check(note is null or length(note)<=1000),
  created_at timestamptz not null default now()
);
create index if not exists product_price_negotiation_events_history_idx
  on public.product_price_negotiation_events(negotiation_id,created_at,id);

alter table public.product_price_negotiations enable row level security;
alter table public.product_price_negotiation_events enable row level security;
revoke all on public.product_price_negotiations,public.product_price_negotiation_events from public,anon,authenticated;
grant select on public.product_price_negotiations,public.product_price_negotiation_events to authenticated;
create policy product_price_negotiations_participant_read
on public.product_price_negotiations for select to authenticated
using (buyer_id=(select auth.uid()) or seller_id=(select auth.uid()));
create policy product_price_negotiation_events_participant_read
on public.product_price_negotiation_events for select to authenticated
using(exists(select 1 from public.product_price_negotiations n
 where n.id=negotiation_id and (n.buyer_id=(select auth.uid()) or n.seller_id=(select auth.uid()))));

create or replace function private.append_product_negotiation_chat_event(
  p_conversation_id uuid,p_actor_id uuid,p_event jsonb
) returns void
language plpgsql security definer set search_path=''
as $ 
begin
  if p_conversation_id is null or p_actor_id is null then
    raise exception 'Negotiation conversation context is missing';
  end if;
  insert into public.messages(conversation_id,sender_id,body,message_type)
  values(p_conversation_id,p_actor_id,p_event::text,'system');
end;
$;
revoke all on function private.append_product_negotiation_chat_event(uuid,uuid,jsonb) from public,anon,authenticated;

create or replace function private.respond_to_product_price_negotiation(
 p_negotiation_id uuid,p_action text,p_quantity numeric default null,
 p_unit_price numeric default null,p_note text default null,p_fulfilment_location text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();
 v_n public.product_price_negotiations%rowtype;
 v_p public.products%rowtype;
 v_role text;
 v_order_id uuid;
 v_available numeric;
 v_next_status text;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if p_action not in ('counter','accept','reject') then raise exception 'Invalid negotiation action' using errcode='22023'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long' using errcode='22023'; end if;
 select * into v_n from public.product_price_negotiations where id=p_negotiation_id for update;
 if not found then raise exception 'Price negotiation not found'; end if;
 select * into v_p from public.products where id=v_n.product_id for update;
 if not found or v_p.listing_status<>'approved' then raise exception 'Product is no longer available'; end if;
 select role into v_role from public.profiles
 where id=v_actor and account_status='active' and role in ('buyer','seller');
 if v_role is null or (v_role='buyer' and v_n.buyer_id<>v_actor)
   or (v_role='seller' and v_n.seller_id<>v_actor) then
   raise exception 'Only this Buyer and Seller may negotiate' using errcode='42501';
 end if;
 if v_n.negotiation_status in ('accepted','rejected','ordered') then raise exception 'Negotiation is already closed'; end if;
 v_available:=case when v_p.stock_tracking then greatest(0,coalesce(v_p.stock_quantity,0)-coalesce(v_p.reserved_quantity,0)) else null end;
 if v_n.quantity<coalesce(v_p.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
 if v_available is not null and v_n.quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;

 if p_action='reject' then
   update public.product_price_negotiations set negotiation_status='rejected',last_actor_id=v_actor,updated_at=now() where id=p_negotiation_id;
   insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,note)
   values(p_negotiation_id,v_actor,'rejected',nullif(btrim(p_note),''));
   perform private.append_product_negotiation_chat_event(v_n.conversation_id,v_actor,
     jsonb_build_object('kind','product_negotiation','action','rejected','negotiation_id',p_negotiation_id,'note',nullif(btrim(p_note),'')));
   return null;
 end if;

 if p_action='counter' then
   if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then
     raise exception 'Quantity and unit price must be positive' using errcode='22023';
   end if;
   if p_quantity<coalesce(v_p.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
   if v_available is not null and p_quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;
   if v_actor=v_n.buyer_id then
     if v_n.negotiation_status<>'seller_countered' then raise exception 'Wait for the Seller counter-offer'; end if;
     v_next_status:='buyer_countered';
   else
     if v_n.negotiation_status<>'buyer_countered' then raise exception 'Seller may counter only after Buyer proposal'; end if;
     v_next_status:='seller_countered';
   end if;
   update public.product_price_negotiations set quantity=p_quantity,current_unit_price=p_unit_price,
    last_actor_id=v_actor,negotiation_status=v_next_status,updated_at=now() where id=p_negotiation_id;
   insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
   values(p_negotiation_id,v_actor,case when v_actor=v_n.buyer_id then 'buyer_counter' else 'seller_counter' end,
    p_quantity,p_unit_price,nullif(btrim(p_note),''));
   perform private.append_product_negotiation_chat_event(v_n.conversation_id,v_actor,
     jsonb_build_object('kind','product_negotiation','action',v_next_status,'negotiation_id',p_negotiation_id,
       'quantity',p_quantity,'unit_price',p_unit_price,'currency',v_n.currency,'note',nullif(btrim(p_note),'')));
   return null;
 end if;

 -- The other party can accept the latest proposal; no self-acceptance.
 if v_actor=v_n.last_actor_id then raise exception 'The other party must accept your latest proposal'; end if;
 if v_actor=v_n.buyer_id and length(btrim(coalesce(p_fulfilment_location,'')))>=5 then
   update public.product_price_negotiations set fulfilment_location=btrim(p_fulfilment_location) where id=p_negotiation_id;
   v_n.fulfilment_location:=btrim(p_fulfilment_location);
 end if;
 if length(btrim(coalesce(v_n.fulfilment_location,'')))<5 then
   raise exception 'Buyer delivery address is missing; Buyer must update it before acceptance' using errcode='22023';
 end if;
 if v_p.stock_tracking then
   if v_n.quantity>(v_p.stock_quantity-v_p.reserved_quantity) then raise exception 'Insufficient available stock'; end if;
   update public.products set reserved_quantity=reserved_quantity+v_n.quantity where id=v_p.id;
 end if;
 insert into public.commerce_orders(
  listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency,
  fulfilment_location,buyer_note,order_status
 ) values(
  'product',v_p.id,v_n.buyer_id,v_n.seller_id,v_n.quantity,v_n.current_unit_price,v_n.currency,
  v_n.fulfilment_location,'Order created from mutually accepted product price negotiation','pending'
 ) returning id into v_order_id;
 insert into public.commerce_order_events(order_id,actor_user_id,event_type,note)
 values(v_order_id,v_actor,'created','Accepted product price negotiation');
 update public.product_price_negotiations set negotiation_status='ordered',order_id=v_order_id,last_actor_id=v_actor,updated_at=now()
 where id=p_negotiation_id;
 insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
 values(p_negotiation_id,v_actor,'accepted',v_n.quantity,v_n.current_unit_price,nullif(btrim(p_note),''));
 perform private.append_product_negotiation_chat_event(v_n.conversation_id,v_actor,
   jsonb_build_object('kind','product_negotiation','action','ordered','negotiation_id',p_negotiation_id,
     'quantity',v_n.quantity,'unit_price',v_n.current_unit_price,'currency',v_n.currency,'order_id',v_order_id));
 return v_order_id;
end;
$$;

create or replace function public.start_product_price_negotiation(
 p_product_id uuid,p_quantity numeric,p_unit_price numeric,p_note text default null,p_fulfilment_location text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_product public.products%rowtype;v_seller uuid;v_id uuid;v_available numeric;v_conversation_id uuid;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then raise exception 'Quantity and price must be positive'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long'; end if;
 if length(btrim(coalesce(p_fulfilment_location,'')))<5 then raise exception 'Delivery address is required' using errcode='22023'; end if;
 select * into v_product from public.products where id=p_product_id and listing_status='approved' for update;
 if not found or not exists(select 1 from public.public_businesses b where b.business_id=v_product.business_id) then raise exception 'Approved product or Seller business not found'; end if;
 v_seller:=v_product.seller_id;
 if v_seller=v_actor then raise exception 'Seller cannot negotiate own listing'; end if;
 if not exists(select 1 from public.profiles where id=v_actor and role='buyer' and account_status='active') then
  raise exception 'Active Buyer account required' using errcode='42501';
 end if;
 if p_quantity<coalesce(v_product.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
 v_available:=case when v_product.stock_tracking then greatest(0,coalesce(v_product.stock_quantity,0)-coalesce(v_product.reserved_quantity,0)) else null end;
 if v_available is not null and p_quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;
 v_conversation_id:=private.create_product_inquiry(p_product_id,null);
 insert into public.product_price_negotiations(product_id,buyer_id,seller_id,conversation_id,quantity,current_unit_price,currency,fulfilment_location,last_actor_id)
 values(p_product_id,v_actor,v_seller,v_conversation_id,p_quantity,p_unit_price,upper(v_product.currency),btrim(p_fulfilment_location),v_actor)
 returning id into v_id;
 insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
 values(v_id,v_actor,'buyer_counter',p_quantity,p_unit_price,nullif(btrim(p_note),''));
 perform private.append_product_negotiation_chat_event(v_conversation_id,v_actor,
   jsonb_build_object('kind','product_negotiation','action','buyer_countered','negotiation_id',v_id,
     'quantity',p_quantity,'unit_price',p_unit_price,'currency',upper(v_product.currency),'note',nullif(btrim(p_note),'')));
 return v_id;
end;
$$;

revoke all on function private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) to authenticated;
revoke all on function public.start_product_price_negotiation(uuid,numeric,numeric,text,text) from public,anon,authenticated;
grant execute on function public.start_product_price_negotiation(uuid,numeric,numeric,text,text) to authenticated;

create or replace function public.respond_to_product_price_negotiation(
 p_negotiation_id uuid,p_action text,p_quantity numeric default null,
 p_unit_price numeric default null,p_note text default null,p_fulfilment_location text default null
) returns uuid language sql security invoker set search_path=''
as $$ select private.respond_to_product_price_negotiation($1,$2,$3,$4,$5,$6); $$;
revoke all on function public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) from public,anon;
grant execute on function public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) to authenticated;

commit;
),
  fulfilment_location text not null check(length(btrim(fulfilment_location))>=5),
  last_actor_id uuid not null references public.profiles(id) on delete restrict,
  negotiation_status text not null default 'buyer_countered'
    check(negotiation_status in ('buyer_countered','seller_countered','accepted','rejected','ordered')),
  order_id uuid references public.commerce_orders(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists product_price_negotiations_buyer_idx
  on public.product_price_negotiations(buyer_id,created_at desc);
create index if not exists product_price_negotiations_seller_idx
  on public.product_price_negotiations(seller_id,created_at desc);
create index if not exists product_price_negotiations_product_idx
  on public.product_price_negotiations(product_id,created_at desc);

create table if not exists public.product_price_negotiation_events (
  id uuid primary key default gen_random_uuid(),
  negotiation_id uuid not null references public.product_price_negotiations(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check(action in ('buyer_counter','seller_counter','accepted','rejected')),
  quantity numeric(18,3) check(quantity is null or quantity>0),
  unit_price numeric(18,2) check(unit_price is null or unit_price>0),
  note text check(note is null or length(note)<=1000),
  created_at timestamptz not null default now()
);
create index if not exists product_price_negotiation_events_history_idx
  on public.product_price_negotiation_events(negotiation_id,created_at,id);

alter table public.product_price_negotiations enable row level security;
alter table public.product_price_negotiation_events enable row level security;
revoke all on public.product_price_negotiations,public.product_price_negotiation_events from public,anon,authenticated;
grant select on public.product_price_negotiations,public.product_price_negotiation_events to authenticated;
create policy product_price_negotiations_participant_read
on public.product_price_negotiations for select to authenticated
using (buyer_id=(select auth.uid()) or seller_id=(select auth.uid()));
create policy product_price_negotiation_events_participant_read
on public.product_price_negotiation_events for select to authenticated
using(exists(select 1 from public.product_price_negotiations n
 where n.id=negotiation_id and (n.buyer_id=(select auth.uid()) or n.seller_id=(select auth.uid()))));

create or replace function private.respond_to_product_price_negotiation(
 p_negotiation_id uuid,p_action text,p_quantity numeric default null,
 p_unit_price numeric default null,p_note text default null,p_fulfilment_location text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();
 v_n public.product_price_negotiations%rowtype;
 v_p public.products%rowtype;
 v_role text;
 v_order_id uuid;
 v_available numeric;
 v_next_status text;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if p_action not in ('counter','accept','reject') then raise exception 'Invalid negotiation action' using errcode='22023'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long' using errcode='22023'; end if;
 select * into v_n from public.product_price_negotiations where id=p_negotiation_id for update;
 if not found then raise exception 'Price negotiation not found'; end if;
 select * into v_p from public.products where id=v_n.product_id for update;
 if not found or v_p.listing_status<>'approved' then raise exception 'Product is no longer available'; end if;
 select role into v_role from public.profiles
 where id=v_actor and account_status='active' and role in ('buyer','seller');
 if v_role is null or (v_role='buyer' and v_n.buyer_id<>v_actor)
   or (v_role='seller' and v_n.seller_id<>v_actor) then
   raise exception 'Only this Buyer and Seller may negotiate' using errcode='42501';
 end if;
 if v_n.negotiation_status in ('accepted','rejected','ordered') then raise exception 'Negotiation is already closed'; end if;
 v_available:=case when v_p.stock_tracking then greatest(0,coalesce(v_p.stock_quantity,0)-coalesce(v_p.reserved_quantity,0)) else null end;
 if v_n.quantity<coalesce(v_p.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
 if v_available is not null and v_n.quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;

 if p_action='reject' then
   update public.product_price_negotiations set negotiation_status='rejected',last_actor_id=v_actor,updated_at=now() where id=p_negotiation_id;
   insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,note)
   values(p_negotiation_id,v_actor,'rejected',nullif(btrim(p_note),''));
   return null;
 end if;

 if p_action='counter' then
   if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then
     raise exception 'Quantity and unit price must be positive' using errcode='22023';
   end if;
   if p_quantity<coalesce(v_p.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
   if v_available is not null and p_quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;
   if v_actor=v_n.buyer_id then
     if v_n.negotiation_status<>'seller_countered' then raise exception 'Wait for the Seller counter-offer'; end if;
     v_next_status:='buyer_countered';
   else
     if v_n.negotiation_status<>'buyer_countered' then raise exception 'Seller may counter only after Buyer proposal'; end if;
     v_next_status:='seller_countered';
   end if;
   update public.product_price_negotiations set quantity=p_quantity,current_unit_price=p_unit_price,
    last_actor_id=v_actor,negotiation_status=v_next_status,updated_at=now() where id=p_negotiation_id;
   insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
   values(p_negotiation_id,v_actor,case when v_actor=v_n.buyer_id then 'buyer_counter' else 'seller_counter' end,
    p_quantity,p_unit_price,nullif(btrim(p_note),''));
   return null;
 end if;

 -- The other party can accept the latest proposal; no self-acceptance.
 if v_actor=v_n.last_actor_id then raise exception 'The other party must accept your latest proposal'; end if;
 if length(btrim(coalesce(p_fulfilment_location,'')))<5 then
   raise exception 'Delivery address is required to create an order' using errcode='22023';
 end if;
 insert into public.commerce_orders(
  listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency,
  fulfilment_location,buyer_note,order_status
 ) values(
  'product',v_p.id,v_n.buyer_id,v_n.seller_id,v_n.quantity,v_n.current_unit_price,v_n.currency,
  btrim(p_fulfilment_location),'Order created from mutually accepted product price negotiation','pending'
 ) returning id into v_order_id;
 insert into public.commerce_order_events(order_id,actor_user_id,event_type,note)
 values(v_order_id,v_actor,'created','Accepted product price negotiation');
 update public.product_price_negotiations set negotiation_status='ordered',order_id=v_order_id,last_actor_id=v_actor,updated_at=now()
 where id=p_negotiation_id;
 insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
 values(p_negotiation_id,v_actor,'accepted',v_n.quantity,v_n.current_unit_price,nullif(btrim(p_note),''));
 return v_order_id;
end;
$$;

create or replace function public.start_product_price_negotiation(
 p_product_id uuid,p_quantity numeric,p_unit_price numeric,p_note text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_product public.products%rowtype;v_seller uuid;v_id uuid;v_available numeric;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then raise exception 'Quantity and price must be positive'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long'; end if;
 select * into v_product from public.products where id=p_product_id and listing_status='approved' for update;
 if not found then raise exception 'Approved product not found'; end if;
 select seller_id into v_seller from public.products where id=p_product_id;
 if v_seller=v_actor then raise exception 'Seller cannot negotiate own listing'; end if;
 if not exists(select 1 from public.profiles where id=v_actor and role='buyer' and account_status='active') then
  raise exception 'Active Buyer account required' using errcode='42501';
 end if;
 if p_quantity<coalesce(v_product.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
 v_available:=case when v_product.stock_tracking then greatest(0,coalesce(v_product.stock_quantity,0)-coalesce(v_product.reserved_quantity,0)) else null end;
 if v_available is not null and p_quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;
 insert into public.product_price_negotiations(product_id,buyer_id,seller_id,quantity,current_unit_price,currency,last_actor_id)
 values(p_product_id,v_actor,v_seller,p_quantity,p_unit_price,upper(v_product.currency),v_actor)
 returning id into v_id;
 insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
 values(v_id,v_actor,'buyer_counter',p_quantity,p_unit_price,nullif(btrim(p_note),''));
 return v_id;
end;
$$;

revoke all on function private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) to authenticated;
revoke all on function public.start_product_price_negotiation(uuid,numeric,numeric,text) from public,anon;
grant execute on function public.start_product_price_negotiation(uuid,numeric,numeric,text) to authenticated;

create or replace function public.respond_to_product_price_negotiation(
 p_negotiation_id uuid,p_action text,p_quantity numeric default null,
 p_unit_price numeric default null,p_note text default null,p_fulfilment_location text default null
) returns uuid language sql security invoker set search_path=''
as $$ select private.respond_to_product_price_negotiation($1,$2,$3,$4,$5,$6); $$;
revoke all on function public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) from public,anon;
grant execute on function public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) to authenticated;

commit;
),
  fulfilment_location text not null check(length(btrim(fulfilment_location))>=5),
  last_actor_id uuid not null references public.profiles(id) on delete restrict,
  negotiation_status text not null default 'buyer_countered'
    check(negotiation_status in ('buyer_countered','seller_countered','accepted','rejected','ordered')),
  order_id uuid references public.commerce_orders(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists product_price_negotiations_buyer_idx
  on public.product_price_negotiations(buyer_id,created_at desc);
create index if not exists product_price_negotiations_seller_idx
  on public.product_price_negotiations(seller_id,created_at desc);
create index if not exists product_price_negotiations_product_idx
  on public.product_price_negotiations(product_id,created_at desc);

create table if not exists public.product_price_negotiation_events (
  id uuid primary key default gen_random_uuid(),
  negotiation_id uuid not null references public.product_price_negotiations(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check(action in ('buyer_counter','seller_counter','accepted','rejected')),
  quantity numeric(18,3) check(quantity is null or quantity>0),
  unit_price numeric(18,2) check(unit_price is null or unit_price>0),
  note text check(note is null or length(note)<=1000),
  created_at timestamptz not null default now()
);
create index if not exists product_price_negotiation_events_history_idx
  on public.product_price_negotiation_events(negotiation_id,created_at,id);

alter table public.product_price_negotiations enable row level security;
alter table public.product_price_negotiation_events enable row level security;
revoke all on public.product_price_negotiations,public.product_price_negotiation_events from public,anon,authenticated;
grant select on public.product_price_negotiations,public.product_price_negotiation_events to authenticated;
create policy product_price_negotiations_participant_read
on public.product_price_negotiations for select to authenticated
using (buyer_id=(select auth.uid()) or seller_id=(select auth.uid()));
create policy product_price_negotiation_events_participant_read
on public.product_price_negotiation_events for select to authenticated
using(exists(select 1 from public.product_price_negotiations n
 where n.id=negotiation_id and (n.buyer_id=(select auth.uid()) or n.seller_id=(select auth.uid()))));

create or replace function private.respond_to_product_price_negotiation(
 p_negotiation_id uuid,p_action text,p_quantity numeric default null,
 p_unit_price numeric default null,p_note text default null,p_fulfilment_location text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();
 v_n public.product_price_negotiations%rowtype;
 v_p public.products%rowtype;
 v_role text;
 v_order_id uuid;
 v_available numeric;
 v_next_status text;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if p_action not in ('counter','accept','reject') then raise exception 'Invalid negotiation action' using errcode='22023'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long' using errcode='22023'; end if;
 select * into v_n from public.product_price_negotiations where id=p_negotiation_id for update;
 if not found then raise exception 'Price negotiation not found'; end if;
 select * into v_p from public.products where id=v_n.product_id for update;
 if not found or v_p.listing_status<>'approved' then raise exception 'Product is no longer available'; end if;
 select role into v_role from public.profiles
 where id=v_actor and account_status='active' and role in ('buyer','seller');
 if v_role is null or (v_role='buyer' and v_n.buyer_id<>v_actor)
   or (v_role='seller' and v_n.seller_id<>v_actor) then
   raise exception 'Only this Buyer and Seller may negotiate' using errcode='42501';
 end if;
 if v_n.negotiation_status in ('accepted','rejected','ordered') then raise exception 'Negotiation is already closed'; end if;
 v_available:=case when v_p.stock_tracking then greatest(0,coalesce(v_p.stock_quantity,0)-coalesce(v_p.reserved_quantity,0)) else null end;
 if v_n.quantity<coalesce(v_p.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
 if v_available is not null and v_n.quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;

 if p_action='reject' then
   update public.product_price_negotiations set negotiation_status='rejected',last_actor_id=v_actor,updated_at=now() where id=p_negotiation_id;
   insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,note)
   values(p_negotiation_id,v_actor,'rejected',nullif(btrim(p_note),''));
   return null;
 end if;

 if p_action='counter' then
   if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then
     raise exception 'Quantity and unit price must be positive' using errcode='22023';
   end if;
   if p_quantity<coalesce(v_p.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
   if v_available is not null and p_quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;
   if v_actor=v_n.buyer_id then
     if v_n.negotiation_status<>'seller_countered' then raise exception 'Wait for the Seller counter-offer'; end if;
     v_next_status:='buyer_countered';
   else
     if v_n.negotiation_status<>'buyer_countered' then raise exception 'Seller may counter only after Buyer proposal'; end if;
     v_next_status:='seller_countered';
   end if;
   update public.product_price_negotiations set quantity=p_quantity,current_unit_price=p_unit_price,
    last_actor_id=v_actor,negotiation_status=v_next_status,updated_at=now() where id=p_negotiation_id;
   insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
   values(p_negotiation_id,v_actor,case when v_actor=v_n.buyer_id then 'buyer_counter' else 'seller_counter' end,
    p_quantity,p_unit_price,nullif(btrim(p_note),''));
   return null;
 end if;

 -- The other party can accept the latest proposal; no self-acceptance.
 if v_actor=v_n.last_actor_id then raise exception 'The other party must accept your latest proposal'; end if;
 if v_actor=v_n.buyer_id and length(btrim(coalesce(p_fulfilment_location,'')))>=5 then
   update public.product_price_negotiations set fulfilment_location=btrim(p_fulfilment_location) where id=p_negotiation_id;
   v_n.fulfilment_location:=btrim(p_fulfilment_location);
 end if;
 if length(btrim(coalesce(v_n.fulfilment_location,'')))<5 then
   raise exception 'Buyer delivery address is missing; Buyer must update it before acceptance' using errcode='22023';
 end if;
 insert into public.commerce_orders(
  listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency,
  fulfilment_location,buyer_note,order_status
 ) values(
  'product',v_p.id,v_n.buyer_id,v_n.seller_id,v_n.quantity,v_n.current_unit_price,v_n.currency,
  v_n.fulfilment_location,'Order created from mutually accepted product price negotiation','pending'
 ) returning id into v_order_id;
 insert into public.commerce_order_events(order_id,actor_user_id,event_type,note)
 values(v_order_id,v_actor,'created','Accepted product price negotiation');
 update public.product_price_negotiations set negotiation_status='ordered',order_id=v_order_id,last_actor_id=v_actor,updated_at=now()
 where id=p_negotiation_id;
 insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
 values(p_negotiation_id,v_actor,'accepted',v_n.quantity,v_n.current_unit_price,nullif(btrim(p_note),''));
 return v_order_id;
end;
$$;

create or replace function public.start_product_price_negotiation(
 p_product_id uuid,p_quantity numeric,p_unit_price numeric,p_note text default null,p_fulfilment_location text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_product public.products%rowtype;v_seller uuid;v_id uuid;v_available numeric;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then raise exception 'Quantity and price must be positive'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long'; end if;
 if length(btrim(coalesce(p_fulfilment_location,'')))<5 then raise exception 'Delivery address is required' using errcode='22023'; end if;
 select * into v_product from public.products where id=p_product_id and listing_status='approved' for update;
 if not found then raise exception 'Approved product not found'; end if;
 select seller_id into v_seller from public.products where id=p_product_id;
 if v_seller=v_actor then raise exception 'Seller cannot negotiate own listing'; end if;
 if not exists(select 1 from public.profiles where id=v_actor and role='buyer' and account_status='active') then
  raise exception 'Active Buyer account required' using errcode='42501';
 end if;
 if p_quantity<coalesce(v_product.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
 v_available:=case when v_product.stock_tracking then greatest(0,coalesce(v_product.stock_quantity,0)-coalesce(v_product.reserved_quantity,0)) else null end;
 if v_available is not null and p_quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;
 insert into public.product_price_negotiations(product_id,buyer_id,seller_id,quantity,current_unit_price,currency,fulfilment_location,last_actor_id)
 values(p_product_id,v_actor,v_seller,p_quantity,p_unit_price,upper(v_product.currency),btrim(p_fulfilment_location),v_actor)
 returning id into v_id;
 insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
 values(v_id,v_actor,'buyer_counter',p_quantity,p_unit_price,nullif(btrim(p_note),''));
 return v_id;
end;
$$;

revoke all on function private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) to authenticated;
revoke all on function public.start_product_price_negotiation(uuid,numeric,numeric,text,text) from public,anon;
grant execute on function public.start_product_price_negotiation(uuid,numeric,numeric,text) to authenticated;

create or replace function public.respond_to_product_price_negotiation(
 p_negotiation_id uuid,p_action text,p_quantity numeric default null,
 p_unit_price numeric default null,p_note text default null,p_fulfilment_location text default null
) returns uuid language sql security invoker set search_path=''
as $$ select private.respond_to_product_price_negotiation($1,$2,$3,$4,$5,$6); $$;
revoke all on function public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) from public,anon;
grant execute on function public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) to authenticated;

commit;
),
  fulfilment_location text not null check(length(btrim(fulfilment_location))>=5),
  last_actor_id uuid not null references public.profiles(id) on delete restrict,
  negotiation_status text not null default 'buyer_countered'
    check(negotiation_status in ('buyer_countered','seller_countered','accepted','rejected','ordered')),
  order_id uuid references public.commerce_orders(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists product_price_negotiations_buyer_idx
  on public.product_price_negotiations(buyer_id,created_at desc);
create index if not exists product_price_negotiations_seller_idx
  on public.product_price_negotiations(seller_id,created_at desc);
create index if not exists product_price_negotiations_product_idx
  on public.product_price_negotiations(product_id,created_at desc);

create table if not exists public.product_price_negotiation_events (
  id uuid primary key default gen_random_uuid(),
  negotiation_id uuid not null references public.product_price_negotiations(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check(action in ('buyer_counter','seller_counter','accepted','rejected')),
  quantity numeric(18,3) check(quantity is null or quantity>0),
  unit_price numeric(18,2) check(unit_price is null or unit_price>0),
  note text check(note is null or length(note)<=1000),
  created_at timestamptz not null default now()
);
create index if not exists product_price_negotiation_events_history_idx
  on public.product_price_negotiation_events(negotiation_id,created_at,id);

alter table public.product_price_negotiations enable row level security;
alter table public.product_price_negotiation_events enable row level security;
revoke all on public.product_price_negotiations,public.product_price_negotiation_events from public,anon,authenticated;
grant select on public.product_price_negotiations,public.product_price_negotiation_events to authenticated;
create policy product_price_negotiations_participant_read
on public.product_price_negotiations for select to authenticated
using (buyer_id=(select auth.uid()) or seller_id=(select auth.uid()));
create policy product_price_negotiation_events_participant_read
on public.product_price_negotiation_events for select to authenticated
using(exists(select 1 from public.product_price_negotiations n
 where n.id=negotiation_id and (n.buyer_id=(select auth.uid()) or n.seller_id=(select auth.uid()))));

create or replace function private.respond_to_product_price_negotiation(
 p_negotiation_id uuid,p_action text,p_quantity numeric default null,
 p_unit_price numeric default null,p_note text default null,p_fulfilment_location text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();
 v_n public.product_price_negotiations%rowtype;
 v_p public.products%rowtype;
 v_role text;
 v_order_id uuid;
 v_available numeric;
 v_next_status text;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if p_action not in ('counter','accept','reject') then raise exception 'Invalid negotiation action' using errcode='22023'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long' using errcode='22023'; end if;
 select * into v_n from public.product_price_negotiations where id=p_negotiation_id for update;
 if not found then raise exception 'Price negotiation not found'; end if;
 select * into v_p from public.products where id=v_n.product_id for update;
 if not found or v_p.listing_status<>'approved' then raise exception 'Product is no longer available'; end if;
 select role into v_role from public.profiles
 where id=v_actor and account_status='active' and role in ('buyer','seller');
 if v_role is null or (v_role='buyer' and v_n.buyer_id<>v_actor)
   or (v_role='seller' and v_n.seller_id<>v_actor) then
   raise exception 'Only this Buyer and Seller may negotiate' using errcode='42501';
 end if;
 if v_n.negotiation_status in ('accepted','rejected','ordered') then raise exception 'Negotiation is already closed'; end if;
 v_available:=case when v_p.stock_tracking then greatest(0,coalesce(v_p.stock_quantity,0)-coalesce(v_p.reserved_quantity,0)) else null end;
 if v_n.quantity<coalesce(v_p.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
 if v_available is not null and v_n.quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;

 if p_action='reject' then
   update public.product_price_negotiations set negotiation_status='rejected',last_actor_id=v_actor,updated_at=now() where id=p_negotiation_id;
   insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,note)
   values(p_negotiation_id,v_actor,'rejected',nullif(btrim(p_note),''));
   return null;
 end if;

 if p_action='counter' then
   if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then
     raise exception 'Quantity and unit price must be positive' using errcode='22023';
   end if;
   if p_quantity<coalesce(v_p.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
   if v_available is not null and p_quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;
   if v_actor=v_n.buyer_id then
     if v_n.negotiation_status<>'seller_countered' then raise exception 'Wait for the Seller counter-offer'; end if;
     v_next_status:='buyer_countered';
   else
     if v_n.negotiation_status<>'buyer_countered' then raise exception 'Seller may counter only after Buyer proposal'; end if;
     v_next_status:='seller_countered';
   end if;
   update public.product_price_negotiations set quantity=p_quantity,current_unit_price=p_unit_price,
    last_actor_id=v_actor,negotiation_status=v_next_status,updated_at=now() where id=p_negotiation_id;
   insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
   values(p_negotiation_id,v_actor,case when v_actor=v_n.buyer_id then 'buyer_counter' else 'seller_counter' end,
    p_quantity,p_unit_price,nullif(btrim(p_note),''));
   return null;
 end if;

 -- The other party can accept the latest proposal; no self-acceptance.
 if v_actor=v_n.last_actor_id then raise exception 'The other party must accept your latest proposal'; end if;
 if length(btrim(coalesce(p_fulfilment_location,'')))<5 then
   raise exception 'Delivery address is required to create an order' using errcode='22023';
 end if;
 insert into public.commerce_orders(
  listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency,
  fulfilment_location,buyer_note,order_status
 ) values(
  'product',v_p.id,v_n.buyer_id,v_n.seller_id,v_n.quantity,v_n.current_unit_price,v_n.currency,
  btrim(p_fulfilment_location),'Order created from mutually accepted product price negotiation','pending'
 ) returning id into v_order_id;
 insert into public.commerce_order_events(order_id,actor_user_id,event_type,note)
 values(v_order_id,v_actor,'created','Accepted product price negotiation');
 update public.product_price_negotiations set negotiation_status='ordered',order_id=v_order_id,last_actor_id=v_actor,updated_at=now()
 where id=p_negotiation_id;
 insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
 values(p_negotiation_id,v_actor,'accepted',v_n.quantity,v_n.current_unit_price,nullif(btrim(p_note),''));
 return v_order_id;
end;
$$;

create or replace function public.start_product_price_negotiation(
 p_product_id uuid,p_quantity numeric,p_unit_price numeric,p_note text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_product public.products%rowtype;v_seller uuid;v_id uuid;v_available numeric;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then raise exception 'Quantity and price must be positive'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long'; end if;
 select * into v_product from public.products where id=p_product_id and listing_status='approved' for update;
 if not found then raise exception 'Approved product not found'; end if;
 select seller_id into v_seller from public.products where id=p_product_id;
 if v_seller=v_actor then raise exception 'Seller cannot negotiate own listing'; end if;
 if not exists(select 1 from public.profiles where id=v_actor and role='buyer' and account_status='active') then
  raise exception 'Active Buyer account required' using errcode='42501';
 end if;
 if p_quantity<coalesce(v_product.minimum_order_quantity,1) then raise exception 'Quantity is below product MOQ'; end if;
 v_available:=case when v_product.stock_tracking then greatest(0,coalesce(v_product.stock_quantity,0)-coalesce(v_product.reserved_quantity,0)) else null end;
 if v_available is not null and p_quantity>v_available then raise exception 'Quantity exceeds available stock'; end if;
 insert into public.product_price_negotiations(product_id,buyer_id,seller_id,quantity,current_unit_price,currency,last_actor_id)
 values(p_product_id,v_actor,v_seller,p_quantity,p_unit_price,upper(v_product.currency),v_actor)
 returning id into v_id;
 insert into public.product_price_negotiation_events(negotiation_id,actor_id,action,quantity,unit_price,note)
 values(v_id,v_actor,'buyer_counter',p_quantity,p_unit_price,nullif(btrim(p_note),''));
 return v_id;
end;
$$;

revoke all on function private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) to authenticated;
revoke all on function public.start_product_price_negotiation(uuid,numeric,numeric,text) from public,anon;
grant execute on function public.start_product_price_negotiation(uuid,numeric,numeric,text) to authenticated;

create or replace function public.respond_to_product_price_negotiation(
 p_negotiation_id uuid,p_action text,p_quantity numeric default null,
 p_unit_price numeric default null,p_note text default null,p_fulfilment_location text default null
) returns uuid language sql security invoker set search_path=''
as $$ select private.respond_to_product_price_negotiation($1,$2,$3,$4,$5,$6); $$;
revoke all on function public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) from public,anon;
grant execute on function public.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text) to authenticated;

commit;
