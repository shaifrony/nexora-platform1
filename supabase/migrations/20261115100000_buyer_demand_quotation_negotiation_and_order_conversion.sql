-- NEXORA Buyer Demand quotation negotiation and conversion to commerce orders.
-- Development branch staging only. DO NOT apply until migration history is reconciled.
begin;

alter table public.commerce_orders
  drop constraint if exists commerce_orders_listing_type_check;
alter table public.commerce_orders
  add constraint commerce_orders_listing_type_check
  check (listing_type in ('product','service','buyer_demand'));

alter table public.commerce_orders
  add column if not exists source_demand_id uuid references public.buyer_demands(id) on delete restrict,
  add column if not exists source_offer_id uuid references public.seller_offers(id) on delete restrict,
  add column if not exists delivery_charge numeric(18,2) not null default 0 check (delivery_charge>=0),
  add column if not exists grand_total numeric(18,2) generated always as (round(quantity*unit_price+delivery_charge,2)) stored;

alter table public.commerce_orders
  drop constraint if exists commerce_orders_demand_source_check;
alter table public.commerce_orders
  add constraint commerce_orders_demand_source_check
  check (
    (listing_type='buyer_demand' and source_demand_id is not null and source_offer_id is not null
      and listing_id=source_demand_id)
    or (listing_type in ('product','service') and source_demand_id is null and source_offer_id is null)
  );

alter table public.seller_offers
  add column if not exists negotiation_status text not null default 'open',
  add column if not exists current_quantity numeric(18,3),
  add column if not exists current_unit_price numeric(18,2),
  add column if not exists last_negotiator_id uuid references public.profiles(id) on delete restrict,
  add column if not exists accepted_quantity numeric(18,3),
  add column if not exists accepted_unit_price numeric(18,2),
  add column if not exists demand_order_id uuid references public.commerce_orders(id) on delete restrict;

alter table public.seller_offers
  drop constraint if exists seller_offers_negotiation_status_check,
  add constraint seller_offers_negotiation_status_check
    check (negotiation_status in ('open','buyer_countered','seller_countered','agreed','declined','ordered')),
  drop constraint if exists seller_offers_current_terms_check,
  add constraint seller_offers_current_terms_check
    check ((current_quantity is null or current_quantity>0)
       and (current_unit_price is null or current_unit_price>0)
       and (accepted_quantity is null or accepted_quantity>0)
       and (accepted_unit_price is null or accepted_unit_price>0));

create table if not exists public.seller_offer_negotiations (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.seller_offers(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  actor_role text not null check (actor_role in ('buyer','seller')),
  action text not null check (action in ('initial_quote','counter','accepted','rejected')),
  proposed_quantity numeric(18,3) check (proposed_quantity is null or proposed_quantity>0),
  proposed_unit_price numeric(18,2) check (proposed_unit_price is null or proposed_unit_price>0),
  note text check (note is null or length(note)<=1000),
  created_at timestamptz not null default now()
);
create index if not exists seller_offer_negotiations_offer_created_idx
  on public.seller_offer_negotiations(offer_id,created_at,id);
alter table public.seller_offer_negotiations enable row level security;
revoke all on public.seller_offer_negotiations from public,anon,authenticated;
grant select on public.seller_offer_negotiations to authenticated;
create policy seller_offer_negotiations_participant_read
on public.seller_offer_negotiations for select to authenticated
using (exists(
  select 1 from public.seller_offers o
  join public.buyer_demands d on d.id=o.demand_id
  where o.id=offer_id and (o.seller_id=(select auth.uid()) or d.buyer_id=(select auth.uid()))
));

-- Initialise the current terms from the Seller's original quotation, including total-price offers.
update public.seller_offers o
set current_quantity=coalesce(o.current_quantity,nullif(o.available_quantity,'')::numeric),
    current_unit_price=coalesce(o.current_unit_price,
      case when o.price_basis='total'
        then round(o.offer_price/nullif(nullif(o.available_quantity,'')::numeric,0),2)
        else o.offer_price end)
where o.current_quantity is null or o.current_unit_price is null;

insert into public.seller_offer_negotiations(offer_id,actor_id,actor_role,action,proposed_quantity,proposed_unit_price,note)
select o.id,o.seller_id,'seller','initial_quote',o.current_quantity,o.current_unit_price,o.message
from public.seller_offers o
where not exists(select 1 from public.seller_offer_negotiations n where n.offer_id=o.id);

create unique index if not exists commerce_orders_source_offer_unique_idx
  on public.commerce_orders(source_offer_id) where source_offer_id is not null;

create or replace function private.initialise_seller_offer_negotiation()
returns trigger language plpgsql security definer set search_path=''
as $
declare v_qty numeric(18,3); v_unit numeric(18,2);
begin
  v_qty:=nullif(new.available_quantity,'')::numeric;
  if v_qty is null or v_qty<=0 then
    raise exception 'Seller quotation availability must be a positive number' using errcode='22023';
  end if;
  v_unit:=case when new.price_basis='total' then round(new.offer_price/v_qty,2) else new.offer_price end;
  if v_unit<=0 then raise exception 'Seller quotation unit price must be positive' using errcode='22023'; end if;
  new.current_quantity:=coalesce(new.current_quantity,v_qty);
  new.current_unit_price:=coalesce(new.current_unit_price,v_unit);
  return new;
end;
$;
revoke all on function private.initialise_seller_offer_negotiation() from public,anon,authenticated;
drop trigger if exists seller_offer_initialise_negotiation on public.seller_offers;
create trigger seller_offer_initialise_negotiation
before insert on public.seller_offers
for each row execute function private.initialise_seller_offer_negotiation();

create or replace function private.log_initial_seller_offer_negotiation()
returns trigger language plpgsql security definer set search_path=''
as $
begin
  insert into public.seller_offer_negotiations(
    offer_id,actor_id,actor_role,action,proposed_quantity,proposed_unit_price,note
  ) values(new.id,new.seller_id,'seller','initial_quote',new.current_quantity,new.current_unit_price,new.message);
  return new;
end;
$;
revoke all on function private.log_initial_seller_offer_negotiation() from public,anon,authenticated;
drop trigger if exists seller_offer_log_initial_negotiation on public.seller_offers;
create trigger seller_offer_log_initial_negotiation
after insert on public.seller_offers
for each row execute function private.log_initial_seller_offer_negotiation();

create or replace function private.respond_to_demand_offer(
  p_offer_id uuid,
  p_action text,
  p_quantity numeric default null,
  p_unit_price numeric default null,
  p_note text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_offer public.seller_offers%rowtype;
  v_demand public.buyer_demands%rowtype;
  v_latest public.seller_offer_negotiations%rowtype;
  v_qty numeric(18,3);
  v_price numeric(18,2);
  v_order_id uuid;
  v_location text;
  v_currency text;
  v_max_qty numeric(18,3);
begin
  if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
  if p_action not in ('accept','counter','reject') then raise exception 'Invalid negotiation action' using errcode='22023'; end if;
  if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long' using errcode='22023'; end if;

  select * into v_offer from public.seller_offers where id=p_offer_id for update;
  if not found then raise exception 'Quotation not found'; end if;
  select * into v_demand from public.buyer_demands where id=v_offer.demand_id for update;
  if not found then raise exception 'Buyer Demand not found'; end if;
  if v_demand.demand_status<>'open' then raise exception 'This Buyer Demand is no longer open'; end if;
  if v_offer.offer_status not in ('pending','accepted') or v_offer.negotiation_status in ('declined','ordered','agreed') then
    raise exception 'This quotation is no longer available for negotiation';
  end if;
  if v_offer.offer_valid_until is not null and v_offer.offer_valid_until<current_date then
    raise exception 'This quotation has expired';
  end if;

  select role into v_role from public.profiles
  where id=v_actor and account_status='active' and role in ('buyer','seller');
  if v_role is null or (v_role='buyer' and v_demand.buyer_id<>v_actor)
     or (v_role='seller' and v_offer.seller_id<>v_actor) then
    raise exception 'Only the Buyer who posted this Demand or the quoted Seller may negotiate' using errcode='42501';
  end if;

  select * into v_latest from public.seller_offer_negotiations
  where offer_id=p_offer_id order by created_at desc,id desc limit 1;

  if p_action='reject' then
    if v_role='buyer' and v_demand.buyer_id<>v_actor then raise exception 'Only the Demand owner may reject'; end if;
    update public.seller_offers set offer_status='rejected',negotiation_status='declined',updated_at=now() where id=p_offer_id;
    insert into public.seller_offer_negotiations(offer_id,actor_id,actor_role,action,note)
    values(p_offer_id,v_actor,v_role,'rejected',nullif(btrim(p_note),''));
    return null;
  end if;

  if p_action='counter' then
    if p_quantity is null or p_quantity<=0 or p_quantity>coalesce(nullif(v_offer.available_quantity,'')::numeric,0)
       or p_unit_price is null or p_unit_price<=0 then
      raise exception 'Counter quantity must be positive and no greater than Seller availability; unit price must be positive' using errcode='22023';
    end if;
    if v_role='buyer' then
      if v_latest.actor_role<>'seller' then raise exception 'Wait for the Seller to respond before sending another counter-offer'; end if;
      update public.seller_offers set negotiation_status='buyer_countered',last_negotiator_id=v_actor,
        current_quantity=p_quantity,current_unit_price=p_unit_price,updated_at=now() where id=p_offer_id;
    else
      if v_latest.actor_role<>'buyer' then raise exception 'A Seller counter-offer is allowed only after the Buyer responds'; end if;
      update public.seller_offers set negotiation_status='seller_countered',last_negotiator_id=v_actor,
        current_quantity=p_quantity,current_unit_price=p_unit_price,updated_at=now() where id=p_offer_id;
    end if;
    insert into public.seller_offer_negotiations(offer_id,actor_id,actor_role,action,proposed_quantity,proposed_unit_price,note)
    values(p_offer_id,v_actor,v_role,'counter',p_quantity,p_unit_price,nullif(btrim(p_note),''));
    return null;
  end if;

  -- Acceptance is permitted only by the party receiving the latest proposal.
  if v_role='buyer' then
    if v_latest.actor_role<>'seller' then raise exception 'The Seller must make the latest proposal before Buyer acceptance'; end if;
    v_max_qty:=case when v_latest.action='counter' then v_latest.proposed_quantity else nullif(v_offer.available_quantity,'')::numeric end;
    v_qty:=coalesce(p_quantity,v_offer.current_quantity);
    if v_qty is null or v_qty<=0 or v_qty>coalesce(v_max_qty,0) then
      raise exception 'Choose a quantity greater than zero and no greater than Seller availability' using errcode='22023';
    end if;
    v_price:=coalesce(v_offer.current_unit_price,
      case when v_offer.price_basis='total' then round(v_offer.offer_price/nullif(v_offer.available_quantity::numeric,0),2) else v_offer.offer_price end);
  else
    if v_latest.actor_role<>'buyer' then raise exception 'Seller can accept only the Buyer latest counter-offer'; end if;
    v_qty:=v_offer.current_quantity;
    v_price:=v_offer.current_unit_price;
  end if;
  if v_qty is null or v_price is null or v_price<=0 then raise exception 'Negotiated terms are incomplete'; end if;

  v_currency:=upper(v_offer.currency);
  v_location:=concat_ws(', ',nullif(v_demand.destination_city,''),nullif(v_demand.destination_country,''));
  if length(coalesce(v_location,''))<5 then raise exception 'Demand destination is incomplete'; end if;

  insert into public.commerce_orders(
    listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency,
    fulfilment_location,buyer_note,order_status,source_demand_id,source_offer_id,delivery_charge
  ) values (
    'buyer_demand',v_demand.id,v_demand.buyer_id,v_offer.seller_id,v_qty,v_price,v_currency,
    v_location,'Created from accepted Buyer Demand quotation','pending',v_demand.id,v_offer.id,coalesce(v_offer.delivery_charge,0)
  ) returning id into v_order_id;

  insert into public.commerce_order_events(order_id,actor_user_id,event_type,note)
  values(v_order_id,v_actor,'created','Accepted Buyer Demand quotation');

  update public.seller_offers set offer_status='accepted',negotiation_status='ordered',
    accepted_quantity=v_qty,accepted_unit_price=v_price,demand_order_id=v_order_id,updated_at=now()
  where id=p_offer_id;
  insert into public.seller_offer_negotiations(offer_id,actor_id,actor_role,action,proposed_quantity,proposed_unit_price,note)
  values(p_offer_id,v_actor,v_role,'accepted',v_qty,v_price,nullif(btrim(p_note),''));
  return v_order_id;
end;
$$;

create or replace function private.transition_buyer_demand_order(
  p_order_id uuid,p_action text,p_note text default null
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
  select * into v_order from public.commerce_orders
  where id=p_order_id and listing_type='buyer_demand' for update;
  if not found then raise exception 'Buyer Demand order not found'; end if;
  if length(coalesce(p_note,''))>1500 then raise exception 'Note is too long'; end if;

  if p_action='accept' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'pending' then raise exception 'Only the assigned Seller may accept a pending order' using errcode='42501'; end if;
    v_next:='accepted';v_event:='accepted';
  elsif p_action='ready' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'accepted' then raise exception 'Only the assigned Seller may mark an accepted order ready' using errcode='42501'; end if;
    v_next:='ready_for_confirmation';v_event:='ready_for_confirmation';
  elsif p_action='complete' then
    if v_actor<>v_order.buyer_id or v_order.order_status<>'ready_for_confirmation' then raise exception 'Only the Buyer may confirm receipt' using errcode='42501'; end if;
    v_next:='completed';v_event:='completed';
  elsif p_action='cancel' then
    if v_actor<>v_order.buyer_id or v_order.order_status<>'pending' then raise exception 'Buyer may cancel only a pending order' using errcode='42501'; end if;
    v_next:='cancelled';v_event:='cancelled';
  elsif p_action='reject' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'pending' or length(btrim(coalesce(p_note,'')))<5 then
      raise exception 'Only the assigned Seller may reject a pending order with a reason' using errcode='42501';
    end if;
    v_next:='rejected';v_event:='rejected';
  else raise exception 'Unsupported order action' using errcode='22023';
  end if;

  update public.commerce_orders set order_status=v_next,
    accepted_at=case when v_next='accepted' then now() else accepted_at end,
    ready_at=case when v_next='ready_for_confirmation' then now() else ready_at end,
    completed_at=case when v_next='completed' then now() else completed_at end,
    cancelled_at=case when v_next='cancelled' then now() else cancelled_at end,
    seller_note=case when v_actor=v_order.seller_id and p_note is not null then nullif(btrim(p_note),'') else seller_note end,
    updated_at=now()
  where id=p_order_id;
  insert into public.commerce_order_events(order_id,actor_user_id,event_type,note)
  values(p_order_id,v_actor,v_event,nullif(btrim(p_note),''));
end;
$$;

revoke all on function private.respond_to_demand_offer(uuid,text,numeric,numeric,text) from public,anon,authenticated;
revoke all on function private.transition_buyer_demand_order(uuid,text,text) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.respond_to_demand_offer(uuid,text,numeric,numeric,text) to authenticated;
grant execute on function private.transition_buyer_demand_order(uuid,text,text) to authenticated;

create or replace function public.respond_to_demand_offer(
  p_offer_id uuid,p_action text,p_quantity numeric default null,
  p_unit_price numeric default null,p_note text default null
) returns uuid language sql security invoker set search_path=''
as $$ select private.respond_to_demand_offer($1,$2,$3,$4,$5); $$;
create or replace function public.transition_buyer_demand_order(
  p_order_id uuid,p_action text,p_note text default null
) returns void language sql security invoker set search_path=''
as $$ select private.transition_buyer_demand_order($1,$2,$3); $$;
revoke all on function public.respond_to_demand_offer(uuid,text,numeric,numeric,text) from public,anon;
revoke all on function public.transition_buyer_demand_order(uuid,text,text) from public,anon;
grant execute on function public.respond_to_demand_offer(uuid,text,numeric,numeric,text) to authenticated;
grant execute on function public.transition_buyer_demand_order(uuid,text,text) to authenticated;

commit;
