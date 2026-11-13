-- NEXORA product inventory, wholesale MOQ and quantity-based pricing.
-- Staged on nexora-development only. Do not apply to hosted DB without explicit approval.
begin;

alter table public.products
  add column if not exists minimum_order_quantity numeric(18,3) not null default 1,
  add column if not exists stock_tracking boolean not null default false,
  add column if not exists stock_quantity numeric(18,3),
  add column if not exists reserved_quantity numeric(18,3) not null default 0,
  add column if not exists price_tiers jsonb not null default '[]'::jsonb;

grant select (minimum_order_quantity,stock_tracking,stock_quantity,reserved_quantity,price_tiers)
  on public.products to anon;

alter table public.products
  drop constraint if exists products_minimum_order_quantity_check,
  add constraint products_minimum_order_quantity_check check (minimum_order_quantity > 0),
  drop constraint if exists products_stock_values_check,
  add constraint products_stock_values_check check (
    reserved_quantity >= 0
    and (stock_tracking = false or (stock_quantity is not null and stock_quantity >= 0 and reserved_quantity <= stock_quantity))
    and (stock_tracking = true or stock_quantity is null)
  ),
  drop constraint if exists products_price_tiers_array_check,
  add constraint products_price_tiers_array_check check (jsonb_typeof(price_tiers) = 'array');

create index if not exists products_stock_tracking_idx
  on public.products (stock_tracking, listing_status);

create or replace function private.validate_product_commercial_fields()
returns trigger
language plpgsql
set search_path=''
as $$
declare
  v_tier jsonb;
  v_min numeric;
  v_price numeric;
  v_previous numeric := 0;
  v_count integer := 0;
begin
  if new.minimum_order_quantity is null or new.minimum_order_quantity <= 0 then
    raise exception 'Minimum order quantity must be greater than zero';
  end if;
  if new.market_category = 'retail' and new.minimum_order_quantity <> 1 then
    raise exception 'Retail products must have minimum order quantity 1';
  end if;
  if new.stock_tracking then
    if new.stock_quantity is null or new.stock_quantity < 0 or new.reserved_quantity > new.stock_quantity then
      raise exception 'Stock quantity cannot be lower than reserved quantity';
    end if;
  elsif new.stock_quantity is not null then
    raise exception 'Stock quantity must be null when stock tracking is disabled';
  end if;
  if jsonb_typeof(new.price_tiers) <> 'array' or jsonb_array_length(new.price_tiers) > 20 then
    raise exception 'Price tiers must be an array with at most 20 tiers';
  end if;
  for v_tier in select value from jsonb_array_elements(new.price_tiers)
  loop
    v_count := v_count + 1;
    if jsonb_typeof(v_tier) <> 'object'
       or not (v_tier ? 'min_quantity')
       or not (v_tier ? 'unit_price') then
      raise exception 'Each price tier requires min_quantity and unit_price';
    end if;
    begin
      v_min := (v_tier->>'min_quantity')::numeric;
      v_price := (v_tier->>'unit_price')::numeric;
    exception when others then
      raise exception 'Invalid price tier values';
    end;
    if v_min <= new.minimum_order_quantity or v_min <= v_previous
       or v_price <= 0 or v_min <> trunc(v_min) then
      raise exception 'Price tiers must use increasing whole-number quantities above MOQ and positive prices';
    end if;
    v_previous := v_min;
  end loop;
  return new;
end;
$$;

drop trigger if exists products_validate_commercial_fields on public.products;
create trigger products_validate_commercial_fields
before insert or update of market_category,minimum_order_quantity,stock_tracking,stock_quantity,reserved_quantity,price_tiers
on public.products
for each row execute function private.validate_product_commercial_fields();

-- Stock values are changed through a guarded RPC, never by a browser table update.
create or replace function private.set_product_inventory(
  p_product_id uuid,
  p_stock_tracking boolean,
  p_stock_quantity numeric
) returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid := auth.uid();
  v_product public.products%rowtype;
begin
  if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found or v_product.seller_id <> v_actor then
    raise exception 'Product not found or not owned by this Seller' using errcode='42501';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.role='seller' and p.account_status='active') then
    raise exception 'Active Seller account required' using errcode='42501';
  end if;
  if v_product.listing_status not in ('pending','approved') then
    raise exception 'Only pending or approved products can update stock';
  end if;
  if p_stock_tracking then
    if p_stock_quantity is null then raise exception 'Stock quantity is required'; end if;
    if v_product.stock_tracking then
      if p_stock_quantity < v_product.reserved_quantity then raise exception 'Stock must be at least the currently reserved quantity'; end if;
      update public.products set stock_tracking=true,stock_quantity=p_stock_quantity where id=p_product_id;
    else
      select coalesce(sum(o.quantity),0) into v_product.reserved_quantity
      from public.commerce_orders o where o.listing_type='product' and o.listing_id=p_product_id
        and o.order_status in ('pending','accepted','ready_for_confirmation');
      if p_stock_quantity < v_product.reserved_quantity then raise exception 'Stock must cover all outstanding orders'; end if;
      update public.products set stock_tracking=true,stock_quantity=p_stock_quantity,reserved_quantity=v_product.reserved_quantity where id=p_product_id;
    end if;
  else
    if v_product.reserved_quantity > 0 then
      raise exception 'Stock tracking cannot be disabled while orders have reserved stock';
    end if;
    update public.products set stock_tracking=false,stock_quantity=null where id=p_product_id;
  end if;
end;
$$;

revoke all on function private.set_product_inventory(uuid,boolean,numeric) from public,anon,authenticated;
-- Pending listing edits may change MOQ and tier prices; stock itself remains RPC-only.
grant update (minimum_order_quantity,price_tiers) on public.products to authenticated;
grant usage on schema private to authenticated;
grant execute on function private.set_product_inventory(uuid,boolean,numeric) to authenticated;

create or replace function public.set_product_inventory(
  p_product_id uuid,
  p_stock_tracking boolean,
  p_stock_quantity numeric
) returns void
language sql
security invoker
set search_path=''
as $$ select private.set_product_inventory($1,$2,$3); $$;
revoke all on function public.set_product_inventory(uuid,boolean,numeric) from public,anon;
grant execute on function public.set_product_inventory(uuid,boolean,numeric) to authenticated;

-- Replace order creation so stock is reserved atomically and quantity-tier price is snapshotted.
create or replace function private.create_commerce_order(
  p_listing_type text,p_listing_id uuid,p_quantity numeric,
  p_fulfilment_location text,p_buyer_note text
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_buyer uuid := auth.uid();
  v_seller uuid;
  v_price numeric(18,2);
  v_currency text;
  v_order_id uuid;
  v_market_category text;
  v_product public.products%rowtype;
  v_tier jsonb;
  v_tier_min numeric;
begin
  if v_buyer is null then raise exception 'Login required' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_buyer and p.role='buyer' and p.account_status='active') then
    raise exception 'Active Buyer account required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_fulfilment_location,''))) not between 5 and 500
     or length(coalesce(p_buyer_note,'')) > 1500 then
    raise exception 'Fulfilment location or note is invalid' using errcode='22023';
  end if;

  if p_listing_type='product' then
    if p_quantity is null or p_quantity <= 0 or p_quantity > 100000000 then
      raise exception 'Invalid product quantity' using errcode='22023';
    end if;
    select * into v_product from public.products pr
      where pr.id=p_listing_id and pr.listing_status='approved'
      for update;
    if not found then raise exception 'Approved product not found'; end if;
    if not exists(select 1 from public.public_businesses b where b.business_id=v_product.business_id) then
      raise exception 'Approved Seller business is not available';
    end if;
    v_seller := v_product.seller_id;
    v_price := v_product.price;
    v_currency := v_product.currency;
    v_market_category := v_product.market_category;
    if not exists(select 1 from public.profiles p where p.id=v_buyer and p.buyer_category=v_market_category) then
      raise exception 'Switch to the matching Buyer category before ordering' using errcode='42501';
    end if;
    if p_quantity < v_product.minimum_order_quantity then
      raise exception 'Order quantity is below the Seller minimum order quantity';
    end if;
    if v_product.stock_tracking then
      if p_quantity > (v_product.stock_quantity - v_product.reserved_quantity) then
        raise exception 'Insufficient available stock';
      end if;
      update public.products set reserved_quantity=reserved_quantity+p_quantity where id=p_listing_id;
    end if;
    for v_tier in select value from jsonb_array_elements(v_product.price_tiers)
    loop
      v_tier_min := (v_tier->>'min_quantity')::numeric;
      if p_quantity >= v_tier_min and v_tier_min >= coalesce(
        (select max((x->>'min_quantity')::numeric)
         from jsonb_array_elements(v_product.price_tiers) x
         where (x->>'min_quantity')::numeric <= p_quantity), 0
      ) then
        v_price := (v_tier->>'unit_price')::numeric;
      end if;
    end loop;
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
  insert into public.commerce_order_events(order_id,actor_user_id,event_type)
  values(v_order_id,v_buyer,'created');
  return v_order_id;
exception when others then
  raise;
end;
$$;

-- Replace transition logic to release reservations on cancellation/rejection and deduct stock on completion.
create or replace function private.transition_commerce_order(
  p_order_id uuid,p_action text,p_note text
) returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid := auth.uid();
  v_order public.commerce_orders%rowtype;
  v_next text;
  v_event text;
  v_product public.products%rowtype;
begin
  if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
  select * into v_order from public.commerce_orders where id=p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if length(coalesce(p_note,'')) > 1500 then raise exception 'Note is too long'; end if;

  if p_action='accept' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'pending' then raise exception 'Only the assigned Seller can accept a pending order' using errcode='42501'; end if;
    v_next:='accepted'; v_event:='accepted';
  elsif p_action='ready' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'accepted' then raise exception 'Only the assigned Seller can mark an accepted order ready' using errcode='42501'; end if;
    v_next:='ready_for_confirmation'; v_event:='ready_for_confirmation';
  elsif p_action='complete' then
    if v_actor<>v_order.buyer_id or v_order.order_status<>'ready_for_confirmation' then raise exception 'Only the purchasing Buyer can confirm completion' using errcode='42501'; end if;
    v_next:='completed'; v_event:='completed';
  elsif p_action='cancel' then
    if v_actor<>v_order.buyer_id or v_order.order_status<>'pending' then raise exception 'Buyer may cancel only a pending order' using errcode='42501'; end if;
    v_next:='cancelled'; v_event:='cancelled';
  elsif p_action='reject' then
    if v_actor<>v_order.seller_id or v_order.order_status<>'pending' then raise exception 'Only the assigned Seller can reject a pending order' using errcode='42501'; end if;
    if length(btrim(coalesce(p_note,''))) < 5 then raise exception 'Rejection reason is required'; end if;
    v_next:='rejected'; v_event:='rejected';
  else
    raise exception 'Unsupported order action';
  end if;

  if v_order.listing_type='product' then
    select * into v_product from public.products where id=v_order.listing_id for update;
    if found and v_product.stock_tracking then
      if v_next='completed' then
        if v_product.stock_quantity < v_order.quantity or v_product.reserved_quantity < v_order.quantity then
          raise exception 'Inventory reservation is inconsistent; contact Admin';
        end if;
        update public.products
          set stock_quantity=stock_quantity-v_order.quantity,
              reserved_quantity=reserved_quantity-v_order.quantity
          where id=v_product.id;
      elsif v_next in ('cancelled','rejected') then
        if v_product.reserved_quantity < v_order.quantity then
          raise exception 'Inventory reservation is inconsistent; contact Admin';
        end if;
        update public.products set reserved_quantity=reserved_quantity-v_order.quantity where id=v_product.id;
      end if;
    end if;
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

comment on column public.products.minimum_order_quantity is 'Minimum purchasable quantity; Retail products are fixed to MOQ 1.';
comment on column public.products.stock_tracking is 'When true, stock_quantity is enforced and pending orders reserve stock.';
comment on column public.products.reserved_quantity is 'Quantity reserved by pending/in-progress orders; changed only by order RPCs.';
comment on column public.products.price_tiers is 'JSON array of {min_quantity, unit_price}; highest qualifying minimum quantity is used.';

commit;