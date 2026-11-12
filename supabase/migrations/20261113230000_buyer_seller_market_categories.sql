-- NEXORA Buyer/Seller market-category registration model.
-- Development branch staging only. Do not apply to the hosted database without explicit approval.
begin;

alter table public.profiles
  add column if not exists buyer_category text,
  add column if not exists seller_categories text[] not null default '{}'::text[];

-- Backfill legacy rows as part of the trusted migration transaction.
-- Temporarily disable only the client-update guard; it is re-enabled before commit.
alter table public.profiles disable trigger protect_profile_updates;

update public.profiles
set buyer_category = 'wholesale'
where role = 'buyer' and buyer_category is null;

update public.profiles
set seller_categories = array['wholesale']::text[]
where role = 'seller' and coalesce(cardinality(seller_categories), 0) = 0;

alter table public.profiles enable trigger protect_profile_updates;

alter table public.profiles drop constraint if exists profiles_market_categories_check;
alter table public.profiles add constraint profiles_market_categories_check check (
  (role = 'buyer' and buyer_category is not null and buyer_category in ('wholesale','retail') and seller_categories = '{}'::text[])
  or
  (role = 'seller' and buyer_category is null and cardinality(seller_categories) between 1 and 2
    and seller_categories <@ array['wholesale','retail']::text[])
  or
  (role = 'admin' and buyer_category is null and seller_categories = '{}'::text[])
);

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role = any (array['buyer'::text,'seller'::text,'admin'::text]));

alter table public.role_requests drop constraint if exists role_requests_requested_role_check;
alter table public.role_requests add constraint role_requests_requested_role_check
  check (requested_role = 'seller'::text);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role text;
  v_full_name text;
  v_provider text;
  v_buyer_category text;
  v_seller_categories text[];
begin
  v_provider := lower(coalesce(new.app_metadata ->> 'provider', ''));

  -- Social OAuth registrations start as Buyer; user-editable metadata never grants a privileged role.
  if v_provider in ('google','facebook') then
    v_role := 'buyer';
  else
    v_role := lower(trim(coalesce(new.raw_user_meta_data ->> 'role','buyer')));
  end if;

  if v_role not in ('buyer','seller') then
    raise exception 'Invalid registration role';
  end if;

  v_full_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')), '');
  if v_full_name is not null and length(v_full_name) > 150 then
    raise exception 'Full name is too long';
  end if;

  if v_role = 'buyer' then
    v_buyer_category := lower(trim(coalesce(new.raw_user_meta_data ->> 'buyer_category','wholesale')));
    if v_buyer_category not in ('wholesale','retail') then
      raise exception 'Invalid Buyer market category';
    end if;
    v_seller_categories := '{}'::text[];
  else
    v_buyer_category := null;
    if jsonb_typeof(new.raw_user_meta_data -> 'seller_categories') = 'array' then
      select coalesce(array_agg(category order by category), array[]::text[])
      into v_seller_categories
      from (
        select distinct jsonb_array_elements_text(new.raw_user_meta_data -> 'seller_categories') as category
      ) selected
      where category in ('wholesale','retail');
    else
      v_seller_categories := array['wholesale']::text[];
    end if;
    if coalesce(cardinality(v_seller_categories),0) = 0 then
      raise exception 'Select at least one Seller market category';
    end if;
  end if;

  insert into public.profiles (id,full_name,role,account_status,buyer_category,seller_categories)
  values (new.id,v_full_name,v_role,'active',v_buyer_category,v_seller_categories)
  on conflict (id) do nothing;

  return new;
end;
$function$;

create or replace function private.guard_profile_market_categories()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if (select auth.uid()) = old.id and not public.is_nexora_admin() then
    if new.role is distinct from old.role
      or new.account_status is distinct from old.account_status
      or new.seller_categories is distinct from old.seller_categories then
      raise exception 'Account role, status and Seller category entitlements cannot be changed by the account owner';
    end if;
    if old.role = 'buyer' then
      if new.buyer_category is null or new.buyer_category not in ('wholesale','retail') then
        raise exception 'Invalid Buyer market category';
      end if;
    elsif new.buyer_category is distinct from old.buyer_category then
      raise exception 'Only Buyer accounts may change Buyer category';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_profile_market_categories() from public, anon, authenticated;
drop trigger if exists profiles_guard_market_categories on public.profiles;
create trigger profiles_guard_market_categories
before update on public.profiles
for each row execute function private.guard_profile_market_categories();

grant update (buyer_category) on public.profiles to authenticated;

comment on column public.profiles.buyer_category is 'Active marketplace category for Buyer accounts: wholesale or retail.';
comment on column public.profiles.seller_categories is 'Allowed marketplace categories for Seller accounts: wholesale, retail, or both.';

commit;
