-- Enforce active Buyer/Seller identities at every commerce-order and negotiation boundary.
-- Development staging only; no hosted Supabase or Production changes.
begin;

create or replace function private.enforce_active_commerce_order_participants()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id=new.buyer_id and p.role='buyer' and p.account_status='active'
  ) then
    raise exception 'An active Buyer account is required to create a Commerce Order'
      using errcode='42501';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id=new.seller_id and p.role='seller' and p.account_status='active'
  ) then
    raise exception 'An active Seller account is required to create a Commerce Order'
      using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_active_commerce_order_participants() from public,anon,authenticated;
drop trigger if exists commerce_orders_require_active_participants on public.commerce_orders;
create trigger commerce_orders_require_active_participants
before insert on public.commerce_orders
for each row execute function private.enforce_active_commerce_order_participants();

create or replace function private.enforce_active_product_negotiation_participants()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.negotiation_status<>'rejected' then
    if not exists (
      select 1 from public.profiles p
      where p.id=new.buyer_id and p.role='buyer' and p.account_status='active'
    ) or not exists (
      select 1 from public.profiles p
      where p.id=new.seller_id and p.role='seller' and p.account_status='active'
    ) then
      raise exception 'Both Buyer and Seller accounts must remain active during a Product Price Negotiation'
        using errcode='42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_active_product_negotiation_participants() from public,anon,authenticated;
drop trigger if exists product_price_negotiations_require_active_participants on public.product_price_negotiations;
create trigger product_price_negotiations_require_active_participants
before insert or update of negotiation_status,buyer_id,seller_id
on public.product_price_negotiations
for each row execute function private.enforce_active_product_negotiation_participants();

create or replace function private.enforce_active_demand_offer_participants()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_buyer_id uuid;
  v_seller_id uuid;
begin
  if new.action<>'rejected' then
    select d.buyer_id,o.seller_id into v_buyer_id,v_seller_id
    from public.seller_offers o
    join public.buyer_demands d on d.id=o.demand_id
    where o.id=new.offer_id;
    if v_buyer_id is null or v_seller_id is null
       or not exists(select 1 from public.profiles p where p.id=v_buyer_id and p.role='buyer' and p.account_status='active')
       or not exists(select 1 from public.profiles p where p.id=v_seller_id and p.role='seller' and p.account_status='active') then
      raise exception 'Both Buyer and Seller accounts must remain active during a Demand quotation'
        using errcode='42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_active_demand_offer_participants() from public,anon,authenticated;
drop trigger if exists seller_offer_negotiations_require_active_participants on public.seller_offer_negotiations;
create trigger seller_offer_negotiations_require_active_participants
before insert on public.seller_offer_negotiations
for each row execute function private.enforce_active_demand_offer_participants();

commit;
