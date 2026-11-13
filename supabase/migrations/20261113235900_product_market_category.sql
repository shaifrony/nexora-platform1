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
drop policy if exists products_public_approved_read on public.products;
-- Public visitors may read only the approved listing projection columns.
-- Sensitive ownership/review columns (seller_id, reviewed_by, admin_note) remain unavailable.
grant select (
  id,product_code,slug,product_name,category,subcategory,market_category,
  image_urls,description,origin,specifications_quality,price,currency,
  listing_status,business_id,minimum_order_quantity,stock_tracking,
  stock_quantity,reserved_quantity,price_tiers,created_at
) on public.products to anon;

-- Public business identity is intentionally limited to display name and location.
grant select (business_id,display_name,country,city)
  on public.public_businesses to anon;
drop policy if exists public_businesses_anon_read on public.public_businesses;
create policy public_businesses_anon_read
on public.public_businesses for select to anon using (true);

create policy products_public_approved_read
on public.products for select to anon
using (
  listing_status = 'approved'
  and exists (
    select 1 from public.public_businesses b
    where b.business_id = products.business_id
  )
);
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
  )
);

-- The inquiry RPC independently verifies the active Buyer, approved listing and
-- approved Business Profile; Buyer visibility does not depend on sale type.
create or replace function private.create_product_inquiry(
  p_product_id uuid,
  p_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_product record;
  v_conversation_id uuid;
  v_title text;
  v_message text := left(btrim(coalesce(p_message, '')), 500);
begin
  if v_user_id is null then
    raise exception 'Login required' using errcode='42501';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id=v_user_id and p.role='buyer' and p.account_status='active'
  ) then
    raise exception 'Active Buyer account required' using errcode='42501';
  end if;

  select p.id,p.seller_id,p.product_code,p.product_name
    into v_product
  from public.products p
  join public.business_profiles b on b.id=p.business_id
  join public.public_businesses pb on pb.business_id=p.business_id
  where p.id=p_product_id
    and p.listing_status='approved'
    and b.approval_status='approved';

  if not found then
    raise exception 'Product unavailable or not approved'
      using errcode='42501';
  end if;

  if v_product.seller_id=v_user_id then
    raise exception 'You cannot send an inquiry to your own product'
      using errcode='42501';
  end if;

  v_title:=left(
    'Product Inquiry • '||v_product.product_code||' • '||
    v_product.product_name||
    case when v_message<>'' then ' • Buyer note: '||v_message else '' end,
    900
  );

  insert into public.conversations(conversation_type,created_by,title,status)
  values('direct',v_user_id,v_title,'active')
  returning id into v_conversation_id;

  insert into public.conversation_participants(
    conversation_id,user_id,invited_by,invitation_status,joined_at
  )
  values
    (v_conversation_id,v_user_id,v_user_id,'accepted',now()),
    (v_conversation_id,v_product.seller_id,v_user_id,'pending',null);

  return v_conversation_id;
end;
$function$;

grant usage on schema private to authenticated;
revoke all on function private.create_product_inquiry(uuid,text)
  from public,anon,authenticated;
grant execute on function private.create_product_inquiry(uuid,text)
  to authenticated;

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
  )
);

revoke update on public.products from authenticated;
grant update (product_name,category,market_category,image_urls,description,origin,specifications_quality,price,currency) on public.products to authenticated;
grant update (listing_status,admin_note,reviewed_by,reviewed_at,updated_at) on public.products to authenticated;

comment on column public.products.market_category is
  'Sale channel selected per listing: wholesale or retail. Separate from product taxonomy category.';

commit;
