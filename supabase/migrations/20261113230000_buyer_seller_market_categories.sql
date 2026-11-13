-- NEXORA Buyer/Seller market-category registration model.
-- Development branch staging only. Do not apply to the hosted database without explicit approval.
begin;

-- Unified product discovery: do not create Buyer/Seller sale-category fields.
alter table public.profiles drop constraint if exists profiles_market_categories_check;
alter table public.profiles drop column if exists buyer_category;
alter table public.profiles drop column if exists seller_categories;

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
begin
  v_provider := lower(coalesce(new.raw_app_meta_data ->> 'provider', ''));
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
  insert into public.profiles (id,full_name,role,account_status)
  values (new.id,v_full_name,v_role,'active')
  on conflict (id) do nothing;
  return new;
end;
$function$;

drop trigger if exists profiles_guard_market_categories on public.profiles;
drop function if exists private.guard_profile_market_categories();

drop policy if exists profiles_owner_update_buyer_category on public.profiles;

commit;
