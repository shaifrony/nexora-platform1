-- Reject JSON null and non-finite numeric values in Product commercial price tiers.
-- Forward-only guard for private.validate_product_commercial_fields().
begin;

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
  if new.stock_tracking then
    if new.stock_quantity is null or new.stock_quantity < 0 or new.reserved_quantity > new.stock_quantity then
      raise exception 'Stock quantity cannot be lower than reserved quantity';
    end if;
  elsif new.stock_quantity is not null then
    raise exception 'Stock quantity must be null when stock tracking is disabled';
  end if;

  if new.price_tiers is null or jsonb_typeof(new.price_tiers) is distinct from 'array' then
    raise exception 'Price tiers must be a JSON array';
  end if;
  if jsonb_array_length(new.price_tiers) > 20 then
    raise exception 'Price tiers must be an array with at most 20 tiers';
  end if;

  for v_tier in select value from jsonb_array_elements(new.price_tiers)
  loop
    v_count := v_count + 1;
    if jsonb_typeof(v_tier) is distinct from 'object'
       or not (v_tier ? 'min_quantity')
       or not (v_tier ? 'unit_price') then
      raise exception 'Each price tier requires min_quantity and unit_price';
    end if;

    -- JSON null yields SQL NULL through ->>; reject it before attempting a cast.
    if v_tier->>'min_quantity' is null or v_tier->>'unit_price' is null then
      raise exception 'Price tier quantity and unit price cannot be null';
    end if;

    begin
      v_min := (v_tier->>'min_quantity')::numeric;
      v_price := (v_tier->>'unit_price')::numeric;
    exception when others then
      raise exception 'Invalid price tier values';
    end;

    -- PostgreSQL numeric accepts NaN and +/-Infinity; these are not valid prices or quantities.
    if v_min::text in ('NaN','Infinity','-Infinity')
       or v_price::text in ('NaN','Infinity','-Infinity') then
      raise exception 'Price tier quantity and unit price must be finite numbers';
    end if;

    if v_min <= new.minimum_order_quantity or v_min <= v_previous
       or v_price <= 0 or v_min <> trunc(v_min) then
      raise exception 'Price tiers must use increasing whole-number quantities above MOQ and positive prices';
    end if;
    v_previous := v_min;
  end loop;
  return new;
end;
$$;

commit;
