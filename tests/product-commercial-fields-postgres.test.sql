\set ON_ERROR_STOP on
\pset pager off

-- Focused disposable PostgreSQL regression suite for the Product commercial-field trigger.
-- The migration under test is the exact forward-only file generated with the official Supabase CLI.

create schema if not exists private;
create table public.products (
  id bigint generated always as identity primary key,
  minimum_order_quantity numeric not null default 1,
  stock_tracking boolean not null default false,
  stock_quantity numeric,
  reserved_quantity numeric not null default 0,
  price_tiers jsonb not null default '[]'::jsonb
);

\ir ../supabase/migrations/20261119035305_nexora_product_commercial_json_numeric_guard.sql

create trigger products_validate_commercial_fields
before insert or update of minimum_order_quantity,stock_tracking,stock_quantity,reserved_quantity,price_tiers
on public.products
for each row execute function private.validate_product_commercial_fields();

create or replace function private.expect_product_tiers_rejected(p_tiers jsonb, p_label text)
returns void
language plpgsql
set search_path=''
as $$
declare
  v_id bigint;
begin
  begin
    insert into public.products(minimum_order_quantity,price_tiers)
    values (5,p_tiers)
    returning id into v_id;
  exception when others then
    return;
  end;
  delete from public.products where id=v_id;
  raise exception 'FAIL: invalid price tiers accepted: %',p_label;
end;
$$;

do $test$
declare
  v_id bigint;
  v_many jsonb;
begin
  -- Valid empty and ordered finite tiers remain accepted.
  insert into public.products(minimum_order_quantity,price_tiers)
  values (5,'[]'::jsonb) returning id into v_id;
  insert into public.products(minimum_order_quantity,price_tiers)
  values (5,'[{"min_quantity":10,"unit_price":12.50},{"min_quantity":25,"unit_price":11}]'::jsonb);

  -- JSON null at either required property must be rejected.
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":null,"unit_price":12}]'::jsonb,'null minimum quantity'
  );
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":10,"unit_price":null}]'::jsonb,'null unit price'
  );

  -- PostgreSQL numeric special values are accepted by casts but must not pass validation.
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":"NaN","unit_price":12}]'::jsonb,'NaN minimum quantity'
  );
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":"Infinity","unit_price":12}]'::jsonb,'positive infinity minimum quantity'
  );
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":"-Infinity","unit_price":12}]'::jsonb,'negative infinity minimum quantity'
  );
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":10,"unit_price":"NaN"}]'::jsonb,'NaN unit price'
  );
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":10,"unit_price":"Infinity"}]'::jsonb,'positive infinity unit price'
  );
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":10,"unit_price":"-Infinity"}]'::jsonb,'negative infinity unit price'
  );

  -- Invalid shapes, casts and ordinary commercial constraints remain rejected.
  perform private.expect_product_tiers_rejected(null,'SQL NULL price tiers');
  perform private.expect_product_tiers_rejected('null'::jsonb,'JSON null price tiers');
  perform private.expect_product_tiers_rejected('{"min_quantity":10,"unit_price":12}'::jsonb,'object instead of array');
  perform private.expect_product_tiers_rejected('[{"min_quantity":"not-a-number","unit_price":12}]'::jsonb,'nonnumeric quantity');
  perform private.expect_product_tiers_rejected('[{"min_quantity":10,"unit_price":"not-a-number"}]'::jsonb,'nonnumeric unit price');
  perform private.expect_product_tiers_rejected('[{"min_quantity":10,"unit_price":0}]'::jsonb,'zero unit price');
  perform private.expect_product_tiers_rejected('[{"min_quantity":10,"unit_price":-1}]'::jsonb,'negative unit price');
  perform private.expect_product_tiers_rejected('[{"min_quantity":10.5,"unit_price":12}]'::jsonb,'fractional minimum quantity');
  perform private.expect_product_tiers_rejected('[{"min_quantity":5,"unit_price":12}]'::jsonb,'minimum quantity equal to MOQ');
  perform private.expect_product_tiers_rejected(
    '[{"min_quantity":10,"unit_price":12},{"min_quantity":9,"unit_price":11}]'::jsonb,
    'non-increasing tier quantities'
  );
  perform private.expect_product_tiers_rejected('[null]'::jsonb,'null tier element');
  perform private.expect_product_tiers_rejected('[{"min_quantity":10}]'::jsonb,'missing unit price');

  select jsonb_agg(jsonb_build_object('min_quantity',n*5+5,'unit_price',10))
    into v_many from generate_series(1,21) n;
  perform private.expect_product_tiers_rejected(v_many,'more than 20 tiers');

  -- The trigger must also validate updates, not just inserts.
  begin
    update public.products set price_tiers='[{"min_quantity":10,"unit_price":"Infinity"}]'::jsonb
    where id=v_id;
    raise exception 'FAIL: invalid update accepted';
  exception when raise_exception then
    if sqlerrm='FAIL: invalid update accepted' then raise; end if;
  end;

  raise notice 'PASS: Product commercial validator accepts valid tiers and rejects JSON null, SQL NULL, NaN, +/-Infinity, malformed values, invalid ordering, fractional quantities, invalid prices, excess tiers and invalid updates';
end
$test$;
