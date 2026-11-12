-- NEXORA Verified Purchase Reviews foundation.
-- Staged on nexora-development only. Do not apply to the hosted database yet.
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

create table if not exists private.review_purchase_eligibility (
  id uuid primary key default gen_random_uuid(),
  listing_type text not null check (listing_type in ('product','service','logistics')),
  listing_id uuid not null,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  purchase_reference text not null,
  purchased_quantity numeric(18,3) check (purchased_quantity is null or purchased_quantity > 0),
  completed_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (listing_type, listing_id, buyer_id, purchase_reference)
);
create index if not exists review_eligibility_buyer_listing_idx
  on private.review_purchase_eligibility(buyer_id, listing_type, listing_id)
  where consumed_at is null;

revoke all on private.review_purchase_eligibility from public, anon, authenticated;
grant select, insert, update on private.review_purchase_eligibility to service_role;

create table if not exists public.listing_reviews (
  id uuid primary key default gen_random_uuid(),
  listing_type text not null check (listing_type in ('product','service','logistics')),
  listing_id uuid not null,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  review_title text check (review_title is null or length(btrim(review_title)) between 2 and 100),
  review_body text not null check (length(btrim(review_body)) between 10 and 2000),
  reviewer_label text not null default 'Verified Buyer',
  purchased_quantity numeric(18,3) check (purchased_quantity is null or purchased_quantity > 0),
  review_status text not null default 'published' check (review_status in ('published','hidden','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  moderation_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists listing_reviews_public_summary_idx
  on public.listing_reviews(listing_type, listing_id, review_status, created_at desc);
create index if not exists listing_reviews_buyer_idx
  on public.listing_reviews(buyer_id, created_at desc);
create unique index if not exists listing_reviews_one_per_buyer_listing_idx
  on public.listing_reviews(listing_type, listing_id, buyer_id);

alter table public.listing_reviews enable row level security;
revoke all on public.listing_reviews from public, anon, authenticated;
grant select on public.listing_reviews to authenticated;

create policy listing_reviews_public_or_owner_read
on public.listing_reviews for select to authenticated
using (
  review_status = 'published'
  or buyer_id = (select auth.uid())
  or (
    public.is_nexora_admin()
    and (select auth.jwt()->>'aal') = 'aal2'
  )
);

create or replace function public.get_my_review_eligibility(
  p_listing_type text,
  p_listing_id uuid
)
returns table (can_review boolean, already_reviewed boolean, purchased_quantity numeric)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_buyer uuid := auth.uid();
begin
  if v_buyer is null then raise exception 'Authentication required'; end if;
  if p_listing_type not in ('product','service','logistics') then
    raise exception 'Invalid listing type';
  end if;
  return query
  select
    exists (
      select 1 from private.review_purchase_eligibility e
      where e.listing_type=p_listing_type and e.listing_id=p_listing_id
        and e.buyer_id=v_buyer and e.consumed_at is null
    ) and not exists (
      select 1 from public.listing_reviews r
      where r.listing_type=p_listing_type and r.listing_id=p_listing_id
        and r.buyer_id=v_buyer
    ),
    exists (
      select 1 from public.listing_reviews r
      where r.listing_type=p_listing_type and r.listing_id=p_listing_id
        and r.buyer_id=v_buyer
    ),
    (
      select e.purchased_quantity from private.review_purchase_eligibility e
      where e.listing_type=p_listing_type and e.listing_id=p_listing_id
        and e.buyer_id=v_buyer and e.consumed_at is null
      order by e.completed_at desc limit 1
    );
end;
$$;
revoke all on function public.get_my_review_eligibility(text,uuid) from public, anon;
grant execute on function public.get_my_review_eligibility(text,uuid) to authenticated;

create or replace function public.submit_verified_listing_review(
  p_listing_type text,
  p_listing_id uuid,
  p_rating smallint,
  p_review_title text,
  p_review_body text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_buyer uuid := auth.uid();
  v_eligibility private.review_purchase_eligibility%rowtype;
  v_review_id uuid;
  v_seller uuid;
begin
  if v_buyer is null then raise exception 'Authentication required'; end if;
  if p_listing_type not in ('product','service','logistics') then raise exception 'Invalid listing type'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'Rating must be between 1 and 5'; end if;
  if p_review_body is null or length(btrim(p_review_body)) < 10 or length(btrim(p_review_body)) > 2000 then
    raise exception 'Review must contain 10 to 2000 characters';
  end if;
  if p_review_title is not null and length(btrim(p_review_title)) not between 2 and 100 then
    raise exception 'Review title must contain 2 to 100 characters';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id=v_buyer and p.role='buyer' and p.account_status='active'
  ) then raise exception 'An active Buyer account is required'; end if;

  if p_listing_type='product' then
    select seller_id into v_seller from public.products
    where id=p_listing_id and listing_status='approved';
  elsif p_listing_type='service' then
    select seller_id into v_seller from public.service_listings
    where id=p_listing_id and listing_status='approved';
  else
    raise exception 'Logistics reviews will be enabled when completed logistics jobs are implemented';
  end if;
  if v_seller is null then raise exception 'Approved listing not found'; end if;
  if v_seller=v_buyer then raise exception 'Sellers cannot review their own listings'; end if;

  select * into v_eligibility
  from private.review_purchase_eligibility e
  where e.listing_type=p_listing_type and e.listing_id=p_listing_id
    and e.buyer_id=v_buyer and e.consumed_at is null
  order by e.completed_at desc
  limit 1
  for update;
  if not found then raise exception 'A completed verified purchase is required before reviewing'; end if;

  if exists (
    select 1 from public.listing_reviews r
    where r.listing_type=p_listing_type and r.listing_id=p_listing_id and r.buyer_id=v_buyer
  ) then raise exception 'You have already reviewed this listing'; end if;

  insert into public.listing_reviews(
    listing_type,listing_id,buyer_id,rating,review_title,review_body,
    purchased_quantity,review_status
  ) values (
    p_listing_type,p_listing_id,v_buyer,p_rating,nullif(btrim(p_review_title),''),
    btrim(p_review_body),v_eligibility.purchased_quantity,'published'
  ) returning id into v_review_id;

  update private.review_purchase_eligibility
  set consumed_at=now()
  where id=v_eligibility.id;
  return v_review_id;
end;
$$;
revoke all on function public.submit_verified_listing_review(text,uuid,smallint,text,text) from public, anon;
grant execute on function public.submit_verified_listing_review(text,uuid,smallint,text,text) to authenticated;

comment on table public.listing_reviews is
  'Buyer reviews tied to a private completed-purchase eligibility record; one review per Buyer per listing.';
comment on table private.review_purchase_eligibility is
  'Private trusted order-completion grants. Only trusted backend/service_role may insert eligibility after a completed order or service job.';

commit;
