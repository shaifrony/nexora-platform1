-- NEXORA marketplace core schema with RLS and approval gates.

create table public.business_profiles (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null unique references public.profiles(id) on delete cascade,
 display_name text not null check (length(trim(display_name)) between 2 and 160),
 description text, country text not null, city text not null, sales_center_address text not null,
 approval_status text not null default 'pending' check (approval_status in ('pending','approved','rejected','suspended')),
 admin_note text, reviewed_by uuid references public.profiles(id), reviewed_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique (id, seller_id)
);

create table public.public_businesses (
 business_id uuid primary key references public.business_profiles(id) on delete cascade,
 seller_id uuid not null references public.profiles(id) on delete cascade,
 display_name text not null, country text not null, city text not null,
 updated_at timestamptz not null default now()
);

create table public.products (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null, seller_id uuid not null,
 product_code text not null unique default ('NXP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
 slug text not null unique default ('product-' || gen_random_uuid()::text),
 product_name text not null check (length(trim(product_name)) between 2 and 180),
 category text not null, image_urls text[] not null default '{}', description text not null,
 origin text not null, specifications_quality text, price numeric(18,2) not null check (price >= 0),
 currency text not null check (currency ~ '^[A-Z]{3}$'),
 listing_status text not null default 'pending' check (listing_status in ('pending','approved','rejected','suspended')),
 admin_note text, reviewed_by uuid references public.profiles(id), reviewed_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint products_business_seller_match foreign key (business_id, seller_id)
   references public.business_profiles(id, seller_id) on delete cascade
);

create table public.buyer_demands (
 id uuid primary key default gen_random_uuid(),
 buyer_id uuid not null references public.profiles(id) on delete cascade,
 demand_code text not null unique default ('NXD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
 product_name text not null check (length(trim(product_name)) between 2 and 180),
 category text not null, description text not null, specifications_quality text,
 required_quantity text not null, budget numeric(18,2) check (budget is null or budget >= 0),
 currency text not null check (currency ~ '^[A-Z]{3}$'),
 destination_country text not null, destination_city text not null, required_date date not null,
 demand_status text not null default 'open' check (demand_status in ('open','closed','cancelled')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint buyer_demands_required_date_not_past check (required_date >= current_date)
);

create table public.seller_offers (
 id uuid primary key default gen_random_uuid(),
 demand_id uuid not null references public.buyer_demands(id) on delete cascade,
 seller_id uuid not null references public.profiles(id) on delete cascade,
 offer_price numeric(18,2) not null check (offer_price >= 0),
 currency text not null check (currency ~ '^[A-Z]{3}$'),
 available_quantity text not null, message text,
 offer_status text not null default 'pending' check (offer_status in ('pending','accepted','rejected','withdrawn')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique (demand_id, seller_id)
);

create index products_business_status_idx on public.products (business_id, listing_status);
create index products_seller_created_idx on public.products (seller_id, created_at desc);
create index demands_buyer_status_idx on public.buyer_demands (buyer_id, demand_status, created_at desc);
create index demands_category_date_idx on public.buyer_demands (category, required_date) where demand_status = 'open';
create index offers_seller_created_idx on public.seller_offers (seller_id, created_at desc);
create index offers_demand_created_idx on public.seller_offers (demand_id, created_at);

alter table public.business_profiles enable row level security;
alter table public.public_businesses enable row level security;
alter table public.products enable row level security;
alter table public.buyer_demands enable row level security;
alter table public.seller_offers enable row level security;

revoke all on public.business_profiles, public.public_businesses, public.products, public.buyer_demands, public.seller_offers from public, anon;
grant select, insert, update on public.business_profiles to authenticated;
grant select on public.public_businesses to authenticated;
grant select, insert, update, delete on public.products to authenticated;
grant select, insert, update on public.buyer_demands to authenticated;
grant select, insert on public.seller_offers to authenticated;

create policy business_owner_admin_select on public.business_profiles for select to authenticated
 using (seller_id=(select auth.uid()) or public.is_nexora_admin());
create policy business_active_seller_insert on public.business_profiles for insert to authenticated
 with check (seller_id=(select auth.uid()) and approval_status='pending' and reviewed_by is null and reviewed_at is null and admin_note is null
 and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='seller' and p.account_status='active'));
create policy business_owner_pending_update on public.business_profiles for update to authenticated
 using (seller_id=(select auth.uid()) and approval_status='pending')
 with check (seller_id=(select auth.uid()) and approval_status='pending' and reviewed_by is null and reviewed_at is null and admin_note is null);
create policy business_admin_all on public.business_profiles for all to authenticated
 using (public.is_nexora_admin()) with check (public.is_nexora_admin());

create policy public_businesses_authenticated_read on public.public_businesses for select to authenticated using (true);

create or replace function public.sync_public_business()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
 if tg_op='DELETE' then
   delete from public.public_businesses where business_id=old.id;
   return old;
 end if;
 if new.approval_status <> 'approved' then
   delete from public.public_businesses where business_id=new.id;
   return new;
 end if;
 insert into public.public_businesses(business_id,seller_id,display_name,country,city,updated_at)
 values(new.id,new.seller_id,new.display_name,new.country,new.city,now())
 on conflict(business_id) do update set seller_id=excluded.seller_id,display_name=excluded.display_name,
 country=excluded.country,city=excluded.city,updated_at=excluded.updated_at;
 return new;
end;
$function$;
revoke all on function public.sync_public_business() from public,anon,authenticated;
create trigger business_profiles_sync_public_business after insert or update or delete on public.business_profiles
for each row execute function public.sync_public_business();

create policy products_owner_approved_or_admin_read on public.products for select to authenticated
 using (seller_id=(select auth.uid()) or public.is_nexora_admin()
 or (listing_status='approved' and exists(select 1 from public.public_businesses b where b.business_id=products.business_id)));
create policy products_approved_seller_insert on public.products for insert to authenticated
 with check (seller_id=(select auth.uid()) and listing_status='pending' and reviewed_by is null and reviewed_at is null and admin_note is null
 and exists(select 1 from public.public_businesses b join public.profiles p on p.id=b.seller_id
 where b.business_id=products.business_id and b.seller_id=(select auth.uid()) and p.role='seller' and p.account_status='active'));
create policy products_owner_pending_update on public.products for update to authenticated
 using (seller_id=(select auth.uid()) and listing_status='pending')
 with check (seller_id=(select auth.uid()) and listing_status='pending' and reviewed_by is null and reviewed_at is null and admin_note is null);
create policy products_owner_pending_delete on public.products for delete to authenticated
 using (seller_id=(select auth.uid()) and listing_status='pending');
create policy products_admin_all on public.products for all to authenticated
 using (public.is_nexora_admin()) with check (public.is_nexora_admin());

create policy demands_owner_seller_admin_read on public.buyer_demands for select to authenticated
 using (buyer_id=(select auth.uid()) or public.is_nexora_admin() or
 (demand_status='open' and exists(select 1 from public.profiles p join public.public_businesses b on b.seller_id=p.id
 where p.id=(select auth.uid()) and p.role='seller' and p.account_status='active')));
create policy demands_active_buyer_insert on public.buyer_demands for insert to authenticated
 with check (buyer_id=(select auth.uid()) and demand_status='open'
 and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='buyer' and p.account_status='active'));
create policy demands_owner_open_update on public.buyer_demands for update to authenticated
 using (buyer_id=(select auth.uid()) and demand_status='open')
 with check (buyer_id=(select auth.uid()));
create policy demands_admin_all on public.buyer_demands for all to authenticated
 using (public.is_nexora_admin()) with check (public.is_nexora_admin());

create policy offers_buyer_seller_admin_read on public.seller_offers for select to authenticated
 using (seller_id=(select auth.uid()) or public.is_nexora_admin() or exists(
 select 1 from public.buyer_demands d where d.id=seller_offers.demand_id and d.buyer_id=(select auth.uid())));
create policy offers_approved_seller_insert on public.seller_offers for insert to authenticated
 with check (seller_id=(select auth.uid()) and offer_status='pending'
 and exists(select 1 from public.profiles p join public.public_businesses b on b.seller_id=p.id
 where p.id=(select auth.uid()) and p.role='seller' and p.account_status='active')
 and exists(select 1 from public.buyer_demands d where d.id=seller_offers.demand_id and d.demand_status='open'));
create policy offers_admin_all on public.seller_offers for all to authenticated
 using (public.is_nexora_admin()) with check (public.is_nexora_admin());

revoke update on public.business_profiles, public.products from authenticated;
grant update (display_name,description,country,city,sales_center_address) on public.business_profiles to authenticated;
grant update (approval_status,admin_note,reviewed_by,reviewed_at,updated_at) on public.business_profiles to authenticated;
grant update (product_name,category,image_urls,description,origin,specifications_quality,price,currency) on public.products to authenticated;
grant update (listing_status,admin_note,reviewed_by,reviewed_at,updated_at) on public.products to authenticated;
