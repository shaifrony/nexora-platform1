-- Separate marketplace sale channel from the product's own taxonomy.
-- Staged on nexora-development only; do not apply to the hosted database without approval.
begin;

alter table public.products
  add column if not exists market_category text not null default 'wholesale';

alter table public.products
  drop constraint if exists products_market_category_check;
alter table public.products
  add constraint products_market_category_check
  check (market_category in ('wholesale','retail'));

create index if not exists products_market_category_status_created_idx
  on public.products (market_category, listing_status, created_at desc);

drop policy if exists products_owner_approved_or_admin_read on public.products;
create policy products_owner_approved_or_admin_read
on public.products for select to authenticated
using (
  seller_id = (select auth.uid())
  or public.is_nexora_admin()
  or (
    listing_status = 'approved'
    and exists (
      select 1 from public.public_businesses b
      where b.business_id = products.business_id
    )
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.account_status = 'active'
        and (
          (p.role = 'buyer' and p.buyer_category = products.market_category)
          or
          (p.role = 'seller' and products.market_category = any(p.seller_categories))
        )
    )
  )
);

drop policy if exists products_approved_seller_insert on public.products;
create policy products_approved_seller_insert
on public.products for insert to authenticated
with check (
  seller_id = (select auth.uid())
  and listing_status = 'pending'
  and reviewed_by is null and reviewed_at is null and admin_note is null
  and exists (
    select 1 from public.public_businesses b
    join public.profiles p on p.id = b.seller_id
    where b.business_id = products.business_id
      and b.seller_id = (select auth.uid())
      and p.role = 'seller'
      and p.account_status = 'active'
      and products.market_category = any(p.seller_categories)
  )
);

revoke update on public.products from authenticated;
grant update (product_name,category,market_category,image_urls,description,origin,specifications_quality,price,currency) on public.products to authenticated;
grant update (listing_status,admin_note,reviewed_by,reviewed_at,updated_at) on public.products to authenticated;

comment on column public.products.market_category is
  'Sale channel selected per listing: wholesale or retail. Separate from product taxonomy category.';

commit;
