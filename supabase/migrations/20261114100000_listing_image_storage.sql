-- NEXORA public listing image uploads (development staging only).
-- Product and service images are public marketplace media. Upload/delete remain seller-owned.
begin;

alter table public.service_listings
  add column if not exists image_urls text[] not null default '{}';

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values (
  'nexora-listing-images',
  'nexora-listing-images',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp','image/avif']
)
on conflict (id) do update
set public=true,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists nexora_listing_images_seller_insert on storage.objects;
create policy nexora_listing_images_seller_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='nexora-listing-images'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and exists (
    select 1
    from public.profiles p
    join public.business_profiles b on b.seller_id=p.id
    where p.id=(select auth.uid())
      and p.role='seller'
      and p.account_status='active'
      and b.approval_status='approved'
  )
);

drop policy if exists nexora_listing_images_owner_delete on storage.objects;
create policy nexora_listing_images_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id='nexora-listing-images'
  and (storage.foldername(name))[1]=(select auth.uid())::text
);

comment on column public.service_listings.image_urls is
  'Public marketplace service image URLs. Uploads are limited to the owning active Seller with an approved Business Profile.';

commit;
