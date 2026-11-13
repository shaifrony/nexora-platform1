-- NEXORA: Targeted Buyer Demand Inbox, structured Seller Quotations and Product Subcategories.
-- Staged on nexora-development only. No hosted database changes are made by this file.
begin;

alter table public.products add column if not exists subcategory text;
alter table public.buyer_demands add column if not exists subcategory text;
alter table public.seller_offers
  add column if not exists product_brand text,
  add column if not exists product_model text,
  add column if not exists product_condition text,
  add column if not exists price_basis text not null default 'per_unit',
  add column if not exists estimated_delivery_date date,
  add column if not exists warranty text,
  add column if not exists offer_valid_until date,
  add column if not exists delivery_charge numeric(18,2);

alter table public.products
  drop constraint if exists products_subcategory_length_check,
  add constraint products_subcategory_length_check
    check (subcategory is null or length(btrim(subcategory)) between 2 and 120);
alter table public.buyer_demands
  drop constraint if exists buyer_demands_subcategory_length_check,
  add constraint buyer_demands_subcategory_length_check
    check (subcategory is null or length(btrim(subcategory)) between 2 and 120);
alter table public.seller_offers
  drop constraint if exists seller_offers_product_condition_check,
  add constraint seller_offers_product_condition_check
    check (product_condition is null or product_condition in ('new','refurbished','used','any')),
  drop constraint if exists seller_offers_price_basis_check,
  add constraint seller_offers_price_basis_check
    check (price_basis in ('per_unit','total')),
  drop constraint if exists seller_offers_delivery_charge_check,
  add constraint seller_offers_delivery_charge_check
    check (delivery_charge is null or delivery_charge >= 0),
  drop constraint if exists seller_offers_brand_length_check,
  add constraint seller_offers_brand_length_check
    check (product_brand is null or length(product_brand)<=100),
  drop constraint if exists seller_offers_model_length_check,
  add constraint seller_offers_model_length_check
    check (product_model is null or length(product_model)<=120),
  drop constraint if exists seller_offers_warranty_length_check,
  add constraint seller_offers_warranty_length_check
    check (warranty is null or length(warranty)<=300);

create index if not exists products_category_subcategory_market_status_idx
  on public.products(category,subcategory,market_category,listing_status);
create index if not exists buyer_demands_category_subcategory_status_idx
  on public.buyer_demands(category,subcategory,demand_status,created_at desc);

create table if not exists public.buyer_demand_inbox (
  id uuid primary key default gen_random_uuid(),
  demand_id uuid not null references public.buyer_demands(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  match_reason text not null default 'approved_product_category',
  created_at timestamptz not null default now(),
  viewed_at timestamptz,
  unique(demand_id,seller_id)
);
create index if not exists buyer_demand_inbox_seller_created_idx
  on public.buyer_demand_inbox(seller_id,created_at desc);
alter table public.buyer_demand_inbox enable row level security;
revoke all on public.buyer_demand_inbox from public,anon,authenticated;
grant select on public.buyer_demand_inbox to authenticated;
drop policy if exists buyer_demand_inbox_seller_read on public.buyer_demand_inbox;
create policy buyer_demand_inbox_seller_read
on public.buyer_demand_inbox for select to authenticated
using (seller_id=(select auth.uid()) or public.is_nexora_admin());

create or replace function private.route_new_buyer_demand_to_sellers()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_buyer_category text;
begin
  if new.demand_status<>'open' then return new; end if;
  select p.buyer_category into v_buyer_category
  from public.profiles p
  where p.id=new.buyer_id and p.role='buyer' and p.account_status='active';
  if v_buyer_category is null then return new; end if;
  insert into public.buyer_demand_inbox(demand_id,seller_id,match_reason)
  select distinct new.id,pr.seller_id,'approved_product_category'
  from public.products pr
  join public.profiles sp on sp.id=pr.seller_id
  join public.public_businesses pb on pb.business_id=pr.business_id and pb.seller_id=pr.seller_id
  where pr.listing_status='approved'
    and pr.market_category=v_buyer_category
    and new.category=pr.category
    and (nullif(btrim(new.subcategory),'') is null
      or lower(btrim(coalesce(pr.subcategory,'')))=lower(btrim(new.subcategory)))
    and sp.role='seller' and sp.account_status='active'
    and v_buyer_category=any(sp.seller_categories)
  on conflict(demand_id,seller_id) do nothing;
  return new;
end;
$$;
revoke all on function private.route_new_buyer_demand_to_sellers() from public,anon,authenticated;
drop trigger if exists buyer_demand_route_to_sellers on public.buyer_demands;
create trigger buyer_demand_route_to_sellers
after insert on public.buyer_demands
for each row execute function private.route_new_buyer_demand_to_sellers();

create or replace function private.route_new_approved_product_to_open_demands()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.listing_status<>'approved' then return new; end if;
  insert into public.buyer_demand_inbox(demand_id,seller_id,match_reason)
  select distinct d.id,new.seller_id,'approved_product_category'
  from public.buyer_demands d
  join public.profiles bp on bp.id=d.buyer_id and bp.role='buyer' and bp.account_status='active'
  join public.profiles sp on sp.id=new.seller_id and sp.role='seller' and sp.account_status='active'
  join public.public_businesses pb on pb.business_id=new.business_id and pb.seller_id=new.seller_id
  where d.demand_status='open'
    and d.category=new.category
    and d.category is not null
    and (nullif(btrim(d.subcategory),'') is null
      or lower(btrim(coalesce(new.subcategory,'')))=lower(btrim(d.subcategory)))
    and bp.buyer_category=new.market_category
    and new.market_category=any(sp.seller_categories)
  on conflict(demand_id,seller_id) do nothing;
  delete from public.buyer_demand_inbox i
  using public.buyer_demands d
  where i.demand_id=d.id and i.seller_id=new.seller_id and d.demand_status='open'
    and not exists(select 1 from public.seller_offers o where o.demand_id=d.id and o.seller_id=new.seller_id)
    and not exists(
      select 1 from public.products pr
      join public.profiles sp on sp.id=pr.seller_id and sp.role='seller' and sp.account_status='active'
      join public.profiles bp on bp.id=d.buyer_id and bp.role='buyer' and bp.account_status='active'
      join public.public_businesses pb on pb.business_id=pr.business_id and pb.seller_id=pr.seller_id
      where pr.seller_id=new.seller_id and pr.listing_status='approved'
        and pr.category=d.category and pr.market_category=bp.buyer_category
        and pr.market_category=any(sp.seller_categories)
        and (nullif(btrim(d.subcategory),'') is null
          or lower(btrim(coalesce(pr.subcategory,'')))=lower(btrim(d.subcategory)))
    );
  return new;
end;
$;
revoke all on function private.route_new_approved_product_to_open_demands() from public,anon,authenticated;
drop trigger if exists approved_product_route_open_demands on public.products;
create trigger approved_product_route_open_demands
after insert or update of listing_status,category,subcategory,market_category,business_id
on public.products for each row
execute function private.route_new_approved_product_to_open_demands();

-- Backfill open demands to every currently eligible Seller whose approved product matches.
insert into public.buyer_demand_inbox(demand_id,seller_id,match_reason)
select distinct d.id,pr.seller_id,'approved_product_category'
from public.buyer_demands d
join public.profiles bp on bp.id=d.buyer_id and bp.role='buyer' and bp.account_status='active'
join public.products pr on pr.category=d.category and pr.listing_status='approved'
join public.profiles sp on sp.id=pr.seller_id and sp.role='seller' and sp.account_status='active'
join public.public_businesses pb on pb.business_id=pr.business_id and pb.seller_id=pr.seller_id
where d.demand_status='open'
  and bp.buyer_category=pr.market_category
  and pr.market_category=any(sp.seller_categories)
  and (nullif(btrim(d.subcategory),'') is null
    or lower(btrim(coalesce(pr.subcategory,'')))=lower(btrim(d.subcategory)))
on conflict(demand_id,seller_id) do nothing;

-- Sellers can read a Demand only when it was routed to their own inbox.
drop policy if exists demands_owner_seller_admin_read on public.buyer_demands;
drop policy if exists demands_select_owner_seller_or_admin on public.buyer_demands;
create policy demands_owner_inbox_admin_read
on public.buyer_demands for select to authenticated
using (
  buyer_id=(select auth.uid())
  or public.is_nexora_admin()
  or (demand_status='open' and exists(
    select 1 from public.buyer_demand_inbox i
    where i.demand_id=buyer_demands.id and i.seller_id=(select auth.uid())
  ))
);

-- Seller quotation creation is allowed only for a demand routed to that Seller.
drop policy if exists offers_approved_seller_insert on public.seller_offers;
drop policy if exists offers_insert_seller_or_admin on public.seller_offers;
create policy offers_approved_seller_inbox_insert
on public.seller_offers for insert to authenticated
with check (
  seller_id=(select auth.uid())
  and offer_status='pending'
  and exists(select 1 from public.profiles p
    where p.id=(select auth.uid()) and p.role='seller' and p.account_status='active')
  and exists(select 1 from public.public_businesses b where b.seller_id=(select auth.uid()))
  and exists(select 1 from public.buyer_demand_inbox i
    join public.buyer_demands d on d.id=i.demand_id
    where i.demand_id=seller_offers.demand_id
      and i.seller_id=(select auth.uid()) and d.demand_status='open')
);

grant update (subcategory) on public.products to authenticated;
grant update (subcategory) on public.buyer_demands to authenticated;

-- Public Demand Board exposes only safe demand fields; security_invoker keeps underlying RLS active.
create or replace view public.public_buyer_demands
with (security_invoker=true)
as
select id,demand_code,product_name,category,subcategory,description,specifications_quality,
       required_quantity,budget,currency,destination_country,destination_city,
       required_date,demand_status,created_at
from public.buyer_demands
where demand_status='open';
revoke all on public.public_buyer_demands from public;
grant select on public.public_buyer_demands to anon,authenticated;
grant select (subcategory) on public.buyer_demands to anon;


create or replace function private.submit_listing_edit_request(
  p_listing_type text,
  p_listing_id uuid,
  p_proposed_changes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid := auth.uid();
  v_seller_id uuid;
  v_business_id uuid;
  v_listing_status text;
  v_seller_categories text[];
  v_request_id uuid;
begin
  if v_actor is null then
    raise exception 'Sign in is required' using errcode='42501';
  end if;
  if p_listing_type is null or p_listing_type not in ('product','service') then
    raise exception 'Unsupported listing type' using errcode='22023';
  end if;
  if p_proposed_changes is null or jsonb_typeof(p_proposed_changes)<>'object'
     or p_proposed_changes='{}'::jsonb then
    raise exception 'Proposed listing changes are required' using errcode='22023';
  end if;

  select seller_categories into v_seller_categories
  from public.profiles
  where id=v_actor and role='seller' and account_status='active';
  if not found then
    raise exception 'An active Seller account is required' using errcode='42501';
  end if;

  if p_listing_type='product' then
    if exists(
      select 1 from jsonb_object_keys(p_proposed_changes) as keys(key)
      where key <> all(array[
        'product_name','category','subcategory','market_category','image_urls','description',
        'origin','specifications_quality','price','currency','minimum_order_quantity','price_tiers'
      ]::text[])
    ) or not (p_proposed_changes ?& array[
      'product_name','category','subcategory','market_category','image_urls','description',
      'origin','specifications_quality','price','currency','minimum_order_quantity','price_tiers'
    ]) then
      raise exception 'Product change fields are invalid or incomplete' using errcode='22023';
    end if;
    select seller_id,business_id,listing_status
      into v_seller_id,v_business_id,v_listing_status
    from public.products where id=p_listing_id for update;
    if not found or v_seller_id<>v_actor or v_listing_status<>'approved' then
      raise exception 'Only your approved Product listing can be submitted for re-review' using errcode='42501';
    end if;
    if not (coalesce(p_proposed_changes->>'market_category','')=any(coalesce(v_seller_categories,'{}'::text[]))) then
      raise exception 'Seller is not registered for this sales category' using errcode='23514';
    end if;
    if length(btrim(coalesce(p_proposed_changes->>'product_name',''))) not between 2 and 180
       or length(btrim(coalesce(p_proposed_changes->>'category',''))) not between 2 and 120
       or length(btrim(coalesce(p_proposed_changes->>'description',''))) not between 1 and 10000
       or length(btrim(coalesce(p_proposed_changes->>'origin',''))) not between 2 and 160
       or coalesce(p_proposed_changes->>'market_category','') not in ('wholesale','retail')
       or length(btrim(coalesce(p_proposed_changes->>'subcategory',''))) not between 2 and 120
       or coalesce(p_proposed_changes->>'minimum_order_quantity','') !~ '^[0-9]+([.][0-9]{1,3})?       or coalesce(p_proposed_changes->>'currency','') !~ '^[A-Z]{3}
       or coalesce(p_proposed_changes->>'price','') !~ '^[0-9]+([.][0-9]{1,2})?$'
       or (p_proposed_changes->>'price')::numeric<=0
       or jsonb_typeof(p_proposed_changes->'image_urls')<>'array'
       or jsonb_array_length(p_proposed_changes->'image_urls')>5
       or exists(select 1 from jsonb_array_elements_text(p_proposed_changes->'image_urls') u where u is null or u !~* '^https://')
       or (p_proposed_changes->'specifications_quality'<>'null'::jsonb
           and jsonb_typeof(p_proposed_changes->'specifications_quality')<>'string') then
      raise exception 'Product details or image URLs are invalid' using errcode='22023';
    end if;
  else
    if exists(
      select 1 from jsonb_object_keys(p_proposed_changes) k
      where k <> all(array[
        'service_name','service_category','description','country','city','service_area',
        'price_basis','price_amount','currency','availability','image_urls'
      ]::text[])
    ) or not (p_proposed_changes ?& array[
      'service_name','service_category','description','country','city','service_area',
      'price_basis','price_amount','currency','availability','image_urls'
    ]) then
      raise exception 'Service change fields are invalid or incomplete' using errcode='22023';
    end if;
    select seller_id,business_id,listing_status
      into v_seller_id,v_business_id,v_listing_status
    from public.service_listings where id=p_listing_id for update;
    if not found or v_seller_id<>v_actor or v_listing_status<>'approved' then
      raise exception 'Only your approved Service listing can be submitted for re-review' using errcode='42501';
    end if;
    if length(btrim(coalesce(p_proposed_changes->>'service_name',''))) not between 2 and 160
       or coalesce(p_proposed_changes->>'service_category','') not in (
         'household','tutoring','plumbing','electrical','mechanic',
         'appliance_repair','it_support','beauty_laundry','other'
       )
       or length(btrim(coalesce(p_proposed_changes->>'description',''))) not between 20 and 3000
       or length(btrim(coalesce(p_proposed_changes->>'country',''))) not between 2 and 100
       or length(btrim(coalesce(p_proposed_changes->>'city',''))) not between 2 and 100
       or length(btrim(coalesce(p_proposed_changes->>'service_area',''))) not between 2 and 300
       or coalesce(p_proposed_changes->>'price_basis','') not in ('negotiable','per_hour','per_day','per_visit','per_job','per_month')
       or p_proposed_changes->>'currency' !~ '^[A-Z]{3}$'
       or (p_proposed_changes->'price_amount'<>'null'::jsonb
           and coalesce(p_proposed_changes->>'price_amount','') !~ '^[0-9]+([.][0-9]{1,2})?$')
       or (p_proposed_changes->'price_amount'<>'null'::jsonb
           and (p_proposed_changes->>'price_amount')::numeric<0)
       or jsonb_typeof(p_proposed_changes->'image_urls')<>'array'
       or jsonb_array_length(p_proposed_changes->'image_urls')>3
       or exists(select 1 from jsonb_array_elements_text(p_proposed_changes->'image_urls') u where u !~* '^https://')
       or (p_proposed_changes->'availability'<>'null'::jsonb
           and (jsonb_typeof(p_proposed_changes->'availability')<>'string'
                or length(p_proposed_changes->>'availability')>300)) then
      raise exception 'Service details or image URLs are invalid' using errcode='22023';
    end if;
  end if;

  if not exists(
    select 1 from public.business_profiles b
    where b.id=v_business_id and b.seller_id=v_actor and b.approval_status='approved'
  ) then
    raise exception 'An approved Business Profile is required' using errcode='42501';
  end if;

  insert into public.listing_edit_requests(
    listing_type,product_id,service_listing_id,seller_id,proposed_changes
  ) values (
    p_listing_type,
    case when p_listing_type='product' then p_listing_id end,
    case when p_listing_type='service' then p_listing_id end,
    v_actor,p_proposed_changes
  ) returning id into v_request_id;

  return jsonb_build_object('request_id',v_request_id,'status','pending');
exception
  when unique_violation then
    raise exception 'There is already a pending change request for this listing' using errcode='23505';
end;
$$;
       or (p_proposed_changes->>'minimum_order_quantity')::numeric <= 0
       or (p_proposed_changes->>'market_category'='retail' and (p_proposed_changes->>'minimum_order_quantity')::numeric <> 1)
       or jsonb_typeof(p_proposed_changes->'price_tiers')<>'array'
       or jsonb_array_length(p_proposed_changes->'price_tiers')>20
       or coalesce(p_proposed_changes->>'currency','') !~ '^[A-Z]{3}
       or coalesce(p_proposed_changes->>'price','') !~ '^[0-9]+([.][0-9]{1,2})?$'
       or (p_proposed_changes->>'price')::numeric<=0
       or jsonb_typeof(p_proposed_changes->'image_urls')<>'array'
       or jsonb_array_length(p_proposed_changes->'image_urls')>5
       or exists(select 1 from jsonb_array_elements_text(p_proposed_changes->'image_urls') u where u is null or u !~* '^https://')
       or (p_proposed_changes->'specifications_quality'<>'null'::jsonb
           and jsonb_typeof(p_proposed_changes->'specifications_quality')<>'string') then
      raise exception 'Product details or image URLs are invalid' using errcode='22023';
    end if;
  else
    if exists(
      select 1 from jsonb_object_keys(p_proposed_changes) k
      where k <> all(array[
        'service_name','service_category','description','country','city','service_area',
        'price_basis','price_amount','currency','availability','image_urls'
      ]::text[])
    ) or not (p_proposed_changes ?& array[
      'service_name','service_category','description','country','city','service_area',
      'price_basis','price_amount','currency','availability','image_urls'
    ]) then
      raise exception 'Service change fields are invalid or incomplete' using errcode='22023';
    end if;
    select seller_id,business_id,listing_status
      into v_seller_id,v_business_id,v_listing_status
    from public.service_listings where id=p_listing_id for update;
    if not found or v_seller_id<>v_actor or v_listing_status<>'approved' then
      raise exception 'Only your approved Service listing can be submitted for re-review' using errcode='42501';
    end if;
    if length(btrim(coalesce(p_proposed_changes->>'service_name',''))) not between 2 and 160
       or coalesce(p_proposed_changes->>'service_category','') not in (
         'household','tutoring','plumbing','electrical','mechanic',
         'appliance_repair','it_support','beauty_laundry','other'
       )
       or length(btrim(coalesce(p_proposed_changes->>'description',''))) not between 20 and 3000
       or length(btrim(coalesce(p_proposed_changes->>'country',''))) not between 2 and 100
       or length(btrim(coalesce(p_proposed_changes->>'city',''))) not between 2 and 100
       or length(btrim(coalesce(p_proposed_changes->>'service_area',''))) not between 2 and 300
       or coalesce(p_proposed_changes->>'price_basis','') not in ('negotiable','per_hour','per_day','per_visit','per_job','per_month')
       or p_proposed_changes->>'currency' !~ '^[A-Z]{3}$'
       or (p_proposed_changes->'price_amount'<>'null'::jsonb
           and coalesce(p_proposed_changes->>'price_amount','') !~ '^[0-9]+([.][0-9]{1,2})?$')
       or (p_proposed_changes->'price_amount'<>'null'::jsonb
           and (p_proposed_changes->>'price_amount')::numeric<0)
       or jsonb_typeof(p_proposed_changes->'image_urls')<>'array'
       or jsonb_array_length(p_proposed_changes->'image_urls')>3
       or exists(select 1 from jsonb_array_elements_text(p_proposed_changes->'image_urls') u where u !~* '^https://')
       or (p_proposed_changes->'availability'<>'null'::jsonb
           and (jsonb_typeof(p_proposed_changes->'availability')<>'string'
                or length(p_proposed_changes->>'availability')>300)) then
      raise exception 'Service details or image URLs are invalid' using errcode='22023';
    end if;
  end if;

  if not exists(
    select 1 from public.business_profiles b
    where b.id=v_business_id and b.seller_id=v_actor and b.approval_status='approved'
  ) then
    raise exception 'An approved Business Profile is required' using errcode='42501';
  end if;

  insert into public.listing_edit_requests(
    listing_type,product_id,service_listing_id,seller_id,proposed_changes
  ) values (
    p_listing_type,
    case when p_listing_type='product' then p_listing_id end,
    case when p_listing_type='service' then p_listing_id end,
    v_actor,p_proposed_changes
  ) returning id into v_request_id;

  return jsonb_build_object('request_id',v_request_id,'status','pending');
exception
  when unique_violation then
    raise exception 'There is already a pending change request for this listing' using errcode='23505';
end;
$$;

create or replace function private.review_listing_edit_request(
  p_request_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid := auth.uid();
  v_admin_code text;
  v_request public.listing_edit_requests%rowtype;
  v_old_urls text[] := '{}'::text[];
  v_new_urls text[] := '{}'::text[];
  v_cleanup_urls text[] := '{}'::text[];
  v_permission text;
  v_listing_id uuid;
  v_business_id uuid;
  v_seller_categories text[];
begin
  if v_actor is null or p_action is null or p_action not in ('approve','reject') then
    raise exception 'Invalid review request' using errcode='22023';
  end if;
  select * into v_request
  from public.listing_edit_requests where id=p_request_id for update;
  if not found then
    raise exception 'Listing change request not found' using errcode='P0002';
  end if;
  v_permission := case when v_request.listing_type='product' then 'products.edit' else 'services.edit' end;
  if not private.has_nexora_permission(v_permission) then
    raise exception 'Active Admin MFA and the matching edit permission are required' using errcode='42501';
  end if;
  if v_request.status<>'pending' then
    raise exception 'This change request has already been reviewed' using errcode='22023';
  end if;
  if p_action='reject' and length(btrim(coalesce(p_reason,'')))<5 then
    raise exception 'A rejection reason of at least 5 characters is required' using errcode='22023';
  end if;
  if length(coalesce(p_reason,''))>1000 then
    raise exception 'Review reason is too long' using errcode='22023';
  end if;

  select s.admin_code into v_admin_code
  from public.admin_staff s
  join public.profiles p on p.id=s.user_id
  where s.user_id=v_actor and s.is_active=true
    and p.role='admin' and p.account_status='active';
  if v_admin_code is null then
    raise exception 'Active Admin membership required' using errcode='42501';
  end if;

  if v_request.listing_type='product' then
    v_listing_id:=v_request.product_id;
    select image_urls,business_id into v_old_urls,v_business_id from public.products
    where id=v_request.product_id and seller_id=v_request.seller_id and listing_status='approved'
    for update;
    if not found then raise exception 'Product is no longer approved or available' using errcode='23514'; end if;
    select p.seller_categories into v_seller_categories
    from public.profiles p join public.business_profiles b on b.seller_id=p.id
    where p.id=v_request.seller_id and p.role='seller' and p.account_status='active'
      and b.id=v_business_id and b.approval_status='approved';
    if not found or not (coalesce(v_request.proposed_changes->>'market_category','')=any(coalesce(v_seller_categories,'{}'::text[]))) then
      raise exception 'Seller or Business eligibility changed; re-verify before approval' using errcode='23514';
    end if;
    select array(select jsonb_array_elements_text(v_request.proposed_changes->'image_urls')) into v_new_urls;
    if p_action='approve' then
      update public.products set
        product_name=v_request.proposed_changes->>'product_name',
        category=v_request.proposed_changes->>'category',
        subcategory=v_request.proposed_changes->>'subcategory',
        market_category=v_request.proposed_changes->>'market_category',
        image_urls=v_new_urls,
        description=v_request.proposed_changes->>'description',
        origin=v_request.proposed_changes->>'origin',
        specifications_quality=nullif(v_request.proposed_changes->>'specifications_quality',''),
        price=(v_request.proposed_changes->>'price')::numeric,
        currency=v_request.proposed_changes->>'currency',
        minimum_order_quantity=(v_request.proposed_changes->>'minimum_order_quantity')::numeric,
        price_tiers=v_request.proposed_changes->'price_tiers',
        updated_at=now()
      where id=v_request.product_id;
    end if;
  else
    v_listing_id:=v_request.service_listing_id;
    select image_urls,business_id into v_old_urls,v_business_id from public.service_listings
    where id=v_request.service_listing_id and seller_id=v_request.seller_id and listing_status='approved'
    for update;
    if not found then raise exception 'Service is no longer approved or available' using errcode='23514'; end if;
    perform 1 from public.profiles p join public.business_profiles b on b.seller_id=p.id
    where p.id=v_request.seller_id and p.role='seller' and p.account_status='active'
      and b.id=v_business_id and b.approval_status='approved';
    if not found then
      raise exception 'Seller or Business eligibility changed; re-verify before approval' using errcode='23514';
    end if;
    select array(select jsonb_array_elements_text(v_request.proposed_changes->'image_urls')) into v_new_urls;
    if p_action='approve' then
      update public.service_listings set
        service_name=v_request.proposed_changes->>'service_name',
        service_category=v_request.proposed_changes->>'service_category',
        description=v_request.proposed_changes->>'description',
        country=v_request.proposed_changes->>'country',
        city=v_request.proposed_changes->>'city',
        service_area=v_request.proposed_changes->>'service_area',
        price_basis=v_request.proposed_changes->>'price_basis',
        price_amount=nullif(v_request.proposed_changes->>'price_amount','')::numeric,
        currency=v_request.proposed_changes->>'currency',
        availability=nullif(v_request.proposed_changes->>'availability',''),
        image_urls=v_new_urls,
        updated_at=now()
      where id=v_request.service_listing_id;
    end if;
  end if;

  if p_action='approve' then
    select coalesce(array_agg(u), '{}'::text[]) into v_cleanup_urls
    from unnest(v_old_urls) u where not (u=any(v_new_urls));
  else
    select coalesce(array_agg(u), '{}'::text[]) into v_cleanup_urls
    from unnest(v_new_urls) u where not (u=any(v_old_urls));
  end if;

  update public.listing_edit_requests
  set status=case when p_action='approve' then 'approved' else 'rejected' end,
      review_reason=nullif(btrim(coalesce(p_reason,'')),''),
      reviewed_by=v_actor,reviewed_at=now(),updated_at=now()
  where id=p_request_id;

  insert into public.admin_audit_logs(
    actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details
  ) values (
    v_actor,v_admin_code,'listing_edit_request.'||p_action,
    'listing_edit_request',p_request_id::text,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'listing_type',v_request.listing_type,'listing_id',v_listing_id,
      'seller_id',v_request.seller_id,'previous_image_urls',v_old_urls,
      'proposed_changes',v_request.proposed_changes
    )
  );

  return jsonb_build_object(
    'request_id',p_request_id,'status',case when p_action='approve' then 'approved' else 'rejected' end,
    'cleanup_urls',v_cleanup_urls
  );
end;
$$;

create or replace function private.snapshot_listing_before_edit_request()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_old jsonb;
begin
  if new.listing_type='product' then
    select jsonb_build_object(
      'product_name',p.product_name,'category',p.category,'subcategory',p.subcategory,
      'market_category',p.market_category,'image_urls',coalesce(to_jsonb(p.image_urls),'[]'::jsonb),
      'description',p.description,'origin',p.origin,
      'specifications_quality',p.specifications_quality,'price',p.price,'currency',p.currency,
      'minimum_order_quantity',p.minimum_order_quantity,'price_tiers',p.price_tiers
    ) into v_old
    from public.products p
    where p.id=new.product_id and p.seller_id=new.seller_id and p.listing_status='approved';
  else
    select jsonb_build_object(
      'service_name',s.service_name,'service_category',s.service_category,
      'description',s.description,'country',s.country,'city',s.city,
      'service_area',s.service_area,'price_basis',s.price_basis,
      'price_amount',s.price_amount,'currency',s.currency,
      'availability',s.availability,'image_urls',coalesce(to_jsonb(s.image_urls),'[]'::jsonb)
    ) into v_old
    from public.service_listings s
    where s.id=new.service_listing_id and s.seller_id=new.seller_id and s.listing_status='approved';
  end if;
  if v_old is null then
    raise exception 'Approved listing snapshot could not be captured' using errcode='23514';
  end if;
  new.original_data:=v_old;
  return new;
end;
$$;

commit;
