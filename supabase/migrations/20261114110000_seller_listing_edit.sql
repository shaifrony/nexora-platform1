-- Permit Sellers to update service image URLs only while a listing is pending.
-- Existing owner-pending UPDATE RLS policy continues to enforce row ownership/status.
begin;
grant update (image_urls) on public.service_listings to authenticated;
commit;
