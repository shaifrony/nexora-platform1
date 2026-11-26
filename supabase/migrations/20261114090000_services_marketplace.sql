-- NEXORA Services Marketplace MVP.
-- Development branch staging only; not applied to hosted database.
begin;

create table if not exists public.service_listings (
  id uuid primary key default gen_random_uuid(),
  service_code text not null unique default ('NXS-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  business_id uuid not null references public.business_profiles(id) on delete cascade,
  service_name text not null check (length(btrim(service_name)) between 2 and 160),
  service_category text not null check (service_category in ('household','tutoring','plumbing','electrical','mechanic','appliance_repair','it_support','beauty_laundry','other')),
  description text not null check (length(btrim(description)) between 20 and 3000),
  country text not null check (length(btrim(country)) between 2 and 100),
  city text not null check (length(btrim(city)) between 2 and 100),
  service_area text not null check (length(btrim(service_area)) between 2 and 300),
  price_basis text not null check (price_basis in ('negotiable','per_hour','per_day','per_visit','per_job','per_month')),
  price_amount numeric(18,2) check (price_amount is null or price_amount >= 0),
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  availability text check (availability is null or length(availability) <= 300),
  listing_status text not null default 'pending' check (listing_status in ('pending','approved','rejected','suspended')),
  admin_note text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_listing_business_seller_match foreign key (business_id,seller_id)
    references public.business_profiles(id,seller_id) on delete cascade,
  constraint service_listing_review_metadata check (
    (listing_status='pending' and reviewed_by is null and reviewed_at is null and admin_note is null)
    or listing_status<>'pending'
  )
);

create index if not exists service_listings_public_search_idx
  on public.service_listings(listing_status,service_category,country,city,created_at desc);
create index if not exists service_listings_seller_created_idx
  on public.service_listings(seller_id,created_at desc);

alter table public.service_listings enable row level security;
revoke all on public.service_listings from anon,authenticated;
grant select,insert,delete on public.service_listings to authenticated;
grant update (service_name,service_category,description,country,city,service_area,price_basis,price_amount,currency,availability) on public.service_listings to authenticated;
grant update (listing_status,admin_note,reviewed_by,reviewed_at,updated_at) on public.service_listings to authenticated;

create policy service_listings_owner_or_public_read
on public.service_listings for select to authenticated
using (
  seller_id=(select auth.uid())
  or public.is_nexora_admin()
  or (
    listing_status='approved'
    and exists(select 1 from public.public_businesses b where b.business_id=service_listings.business_id)
  )
);

create policy service_listings_approved_business_insert
on public.service_listings for insert to authenticated
with check (
  seller_id=(select auth.uid())
  and listing_status='pending'
  and reviewed_by is null and reviewed_at is null and admin_note is null
  and exists(
    select 1 from public.business_profiles b
    join public.profiles p on p.id=b.seller_id
    where b.id=service_listings.business_id
      and b.seller_id=(select auth.uid())
      and b.approval_status='approved'
      and p.role='seller' and p.account_status='active'
  )
);

create policy service_listings_owner_pending_update
on public.service_listings for update to authenticated
using (seller_id=(select auth.uid()) and listing_status='pending')
with check (
  seller_id=(select auth.uid()) and listing_status='pending'
  and reviewed_by is null and reviewed_at is null and admin_note is null
);

create policy service_listings_owner_pending_delete
on public.service_listings for delete to authenticated
using (seller_id=(select auth.uid()) and listing_status='pending');

create policy service_listings_admin_all
on public.service_listings for all to authenticated
using (
  public.is_nexora_admin()
  and (select auth.jwt()->>'aal') = 'aal2'
)
with check (
  public.is_nexora_admin()
  and (select auth.jwt()->>'aal') = 'aal2'
);

comment on table public.service_listings is
  'Service offers. Exact home address and personal phone are intentionally not collected or publicly exposed.';

commit;
