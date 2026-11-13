-- NEXORA order and completion workflow for Product purchases and Service bookings.
-- Development branch staging only. Not applied to the hosted database.
begin;

create table if not exists public.commerce_orders (
  id uuid primary key default gen_random_uuid(),
  order_code text not null unique default ('NXO-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  listing_type text not null check (listing_type in ('product','service')),
  listing_id uuid not null,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_price numeric(18,2) not null check (unit_price > 0),
  total_price numeric(18,2) generated always as (round(quantity * unit_price,2)) stored,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  fulfilment_location text not null check (length(btrim(fulfilment_location)) between 5 and 500),
  buyer_note text check (buyer_note is null or length(buyer_note) <= 1500),
  seller_note text check (seller_note is null or length(seller_note) <= 1500),
  order_status text not null default 'pending'
    check (order_status in ('pending','accepted','ready_for_confirmation','completed','cancelled','rejected')),
  accepted_at timestamptz,
  ready_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((order_status='completed') = (completed_at is not null)),
  check ((order_status='cancelled') = (cancelled_at is not null)),
  check (listing_type <> 'service' or quantity=1)
);
create index if not exists commerce_orders_buyer_created_idx
  on public.commerce_orders(buyer_id,created_at desc);
create index if not exists commerce_orders_seller_created_idx
  on public.commerce_orders(seller_id,created_at desc);
create index if not exists commerce_orders_status_created_idx
  on public.commerce_orders(order_status,created_at desc);

create table if not exists public.commerce_order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.commerce_orders(id) on delete restrict,
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  event_type text not null check(event_type in ('created','accepted','ready_for_confirmation','completed','cancelled','rejected')),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists commerce_order_events_order_idx
  on public.commerce_order_events(order_id,created_at);

alter table public.commerce_orders enable row level security;
alter table public.commerce_order_events enable row level security;
revoke all on public.commerce_orders,public.commerce_order_events from public,anon,authenticated;
grant select on public.commerce_orders,public.commerce_order_events to authenticated;
create policy commerce_orders_buyer_seller_read on public.commerce_orders
 for select to authenticated using (buyer_id=(select auth.uid()) or seller_id=(select auth.uid()));
create policy commerce_order_events_participant_read on public.commerce_order_events
 for select to authenticated using (exists(
   select 1 from public.commerce_orders o where o.id=order_id
   and (o.buyer_id=(select auth.uid()) or o.seller_id=(select auth.uid()))
 ));

create or replace function private.create_commerce_order(
  p_listing_type text,p_listing_id uuid,p_quantity numeric,
  p_fulfilment_location text,p_buyer_note text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  v_buyer uuid:=auth.uid();
  v_seller uuid;
  v_price numeric(18,2);
  v_currency text;
  v_order_id uuid;
  v_market_category text;
begin
  if v_buyer is null then raise exception 'Login required' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_buyer and p.role='buyer' and p.account_status='active') then
    raise exception 'Active Buyer account required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_fulfilment_location,''))) not between 5 and 500
     or length(coalesce(p_buyer_note,''))>1500 then
    raise exception 'Fulfilment location or note is invalid' using errcode='22023';
  end if;
  if p_listing_type='product' then
    if p_quantity is null or p_quantity<=0 or p_quantity>100000000 then raise exception 'Invalid product quantity' using errcode='22023'; end if;
    select pr.seller_id,pr.price,pr.currency,pr.market_category
      into v_seller,v_price,v_currency,v_market_category
    from public.products pr join public.public_businesses b on b.business_id=pr.business_id
    where pr.id=p_listing_id and pr.listing_status='approved';
    if not found then raise exception 'Approved product not found'; end if;
    if not exists(select 1 from public.profiles p where p.id=v_buyer and p.buyer_category=v_market_category) then
      raise exception 'Switch to the matching Buyer category before ordering' using errcode='42501';
    end if;
  elsif p_listing_type='service' then
    if p_quantity is distinct from 1 then raise exception 'Service booking quantity must be one'; end if;
    select s.seller_id,s.price_amount,s.currency into v_seller,v_price,v_currency
    from public.service_listings s join public.public_businesses b on b.business_id=s.business_id
    where s.id=p_listing_id and s.listing_status='approved';
    if not found then raise exception 'Approved service not found'; end if;
    if v_price is null or v_price<=0 then raise exception 'This service requires a negotiated price before online booking'; end if;
  else
    raise exception 'Unsupported order type';
  end if;
  if v_seller=v_buyer then raise exception 'You cannot order your own listing'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_seller and p.role='seller' and p.account_status='active') then
    raise exception 'Seller is not active';
  end if;
  insert into public.commerce_orders(listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency,fulfilment_location,buyer_note)
  values(p_listing_type,p_listing_id,v_buyer,v_seller,p_quantity,v_price,v_currency,btrim(p_fulfilment_location),nullif(btrim(p_buyer_note),''))
  returning id into v_order_id;
  insert into public.commerce_order_events(order_id,actor_user_id,event_type) values(v_order_id,v_buyer,'created');
  return v_order_id;
end;
$$;

create or replace function private.transition_commerce_order(
  p_order_id uuid,p_action text,p_note text
) returns void
language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_order public.commerce_orders%rowtype;
  v_next text;
  v_event text;
begin
  if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
  select * into v_order from public.commerce_orders where id=p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if length(coalesce(p_note,''))>1500 then raise exception 'Note is too long'; end if;

  if p_action='accept' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'pending' then raise exception 'Only the assigned Seller can accept a pending order' using errcode='42501'; end if;
    v_next:='accepted';v_event:='accepted';
  elsif p_action='ready' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'accepted' then raise exception 'Only the assigned Seller can mark an accepted order ready' using errcode='42501'; end if;
    v_next:='ready_for_confirmation';v_event:='ready_for_confirmation';
  elsif p_action='complete' then
    if v_actor<>v_order.buyer_id or v_order.order_status<>'ready_for_confirmation' then raise exception 'Only the purchasing Buyer can confirm completion' using errcode='42501'; end if;
    v_next:='completed';v_event:='completed';
  elsif p_action='cancel' then
    if v_actor<>v_order.buyer_id or v_order.order_status<>'pending' then raise exception 'Buyer may cancel only a pending order' using errcode='42501'; end if;
    v_next:='cancelled';v_event:='cancelled';
  elsif p_action='reject' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'pending' then raise exception 'Only the assigned Seller can reject a pending order' using errcode='42501'; end if;
    if length(btrim(coalesce(p_note,'')))<5 then raise exception 'Rejection reason is required'; end if;
    v_next:='rejected';v_event:='rejected';
  else raise exception 'Unsupported order action';
  end if;

  update public.commerce_orders set
    order_status=v_next,
    accepted_at=case when v_next='accepted' then now() else accepted_at end,
    ready_at=case when v_next='ready_for_confirmation' then now() else ready_at end,
    completed_at=case when v_next='completed' then now() else completed_at end,
    cancelled_at=case when v_next='cancelled' then now() else cancelled_at end,
    seller_note=case when v_actor=v_order.seller_id and p_note is not null then nullif(btrim(p_note),'') else seller_note end,
    updated_at=now()
  where id=p_order_id;

  insert into public.commerce_order_events(order_id,actor_user_id,event_type,note)
  values(p_order_id,v_actor,v_event,nullif(btrim(p_note),''));

  if v_next='completed' then
    insert into private.review_purchase_eligibility(
      listing_type,listing_id,buyer_id,purchase_reference,purchased_quantity,completed_at
    ) values (
      v_order.listing_type,v_order.listing_id,v_order.buyer_id,v_order.order_code,v_order.quantity,now()
    ) on conflict(listing_type,listing_id,buyer_id,purchase_reference) do nothing;
  end if;
end;
$$;

revoke all on function private.create_commerce_order(text,uuid,numeric,text,text) from public,anon,authenticated;
revoke all on function private.transition_commerce_order(uuid,text,text) from public,anon,authenticated;

create or replace function public.create_commerce_order(
  p_listing_type text,p_listing_id uuid,p_quantity numeric,
  p_fulfilment_location text,p_buyer_note text default null
) returns uuid language sql security invoker set search_path=''
as $$ select private.create_commerce_order($1,$2,$3,$4,$5); $$;
create or replace function public.transition_commerce_order(
  p_order_id uuid,p_action text,p_note text default null
) returns void language sql security invoker set search_path=''
as $$ select private.transition_commerce_order($1,$2,$3); $$;
revoke all on function public.create_commerce_order(text,uuid,numeric,text,text) from public,anon;
revoke all on function public.transition_commerce_order(uuid,text,text) from public,anon;
grant execute on function public.create_commerce_order(text,uuid,numeric,text,text) to authenticated;
grant execute on function public.transition_commerce_order(uuid,text,text) to authenticated;

commit;
