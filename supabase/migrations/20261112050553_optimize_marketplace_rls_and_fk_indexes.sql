-- Performance follow-up: index foreign keys and consolidate permissive RLS policies.

create index if not exists business_profiles_reviewed_by_idx on public.business_profiles(reviewed_by);
create index if not exists products_business_seller_fk_idx on public.products(business_id, seller_id);
create index if not exists products_reviewed_by_idx on public.products(reviewed_by);
create index if not exists profile_change_requests_reviewed_by_idx on public.profile_change_requests(reviewed_by);
create index if not exists public_businesses_seller_id_idx on public.public_businesses(seller_id);

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile" on public.profiles
for select to authenticated using ((select auth.uid()) = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles
for update to authenticated using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists "Users can submit own role requests" on public.role_requests;
create policy "Users can submit own role requests" on public.role_requests
for insert to authenticated with check ((select auth.uid()) = user_id
 and requested_role in ('seller','porter') and status='pending');

drop policy if exists "Users can view own role requests" on public.role_requests;
create policy "Users can view own role requests" on public.role_requests
for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users can submit own profile change requests" on public.profile_change_requests;
create policy "Users can submit own profile change requests" on public.profile_change_requests
for insert to authenticated with check ((select auth.uid()) = user_id and status='pending'
 and length(trim(requested_full_name)) between 1 and 150
 and admin_note is null and reviewed_by is null and reviewed_at is null);

drop policy if exists "Users can view own profile change requests" on public.profile_change_requests;
create policy "Users can view own profile change requests" on public.profile_change_requests
for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists business_owner_admin_select on public.business_profiles;
drop policy if exists business_active_seller_insert on public.business_profiles;
drop policy if exists business_owner_pending_update on public.business_profiles;
drop policy if exists business_admin_all on public.business_profiles;
create policy business_select_owner_or_admin on public.business_profiles for select to authenticated
using (seller_id=(select auth.uid()) or public.is_nexora_admin());
create policy business_insert_seller_or_admin on public.business_profiles for insert to authenticated
with check (public.is_nexora_admin() or (seller_id=(select auth.uid()) and approval_status='pending'
 and reviewed_by is null and reviewed_at is null and admin_note is null
 and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='seller' and p.account_status='active')));
create policy business_update_owner_or_admin on public.business_profiles for update to authenticated
using (public.is_nexora_admin() or (seller_id=(select auth.uid()) and approval_status='pending'))
with check (public.is_nexora_admin() or (seller_id=(select auth.uid()) and approval_status='pending'
 and reviewed_by is null and reviewed_at is null and admin_note is null));

drop policy if exists products_owner_approved_or_admin_read on public.products;
drop policy if exists products_approved_seller_insert on public.products;
drop policy if exists products_owner_pending_update on public.products;
drop policy if exists products_admin_all on public.products;
drop policy if exists products_owner_pending_delete on public.products;
create policy products_select_owner_approved_or_admin on public.products for select to authenticated
using (seller_id=(select auth.uid()) or public.is_nexora_admin()
 or (listing_status='approved' and exists(select 1 from public.public_businesses b where b.business_id=products.business_id)));
create policy products_insert_approved_seller_or_admin on public.products for insert to authenticated
with check (public.is_nexora_admin() or (seller_id=(select auth.uid()) and listing_status='pending'
 and reviewed_by is null and reviewed_at is null and admin_note is null
 and exists(select 1 from public.public_businesses b join public.profiles p on p.id=b.seller_id
 where b.business_id=products.business_id and b.seller_id=(select auth.uid()) and p.role='seller' and p.account_status='active')));
create policy products_update_owner_or_admin on public.products for update to authenticated
using (public.is_nexora_admin() or (seller_id=(select auth.uid()) and listing_status='pending'))
with check (public.is_nexora_admin() or (seller_id=(select auth.uid()) and listing_status='pending'
 and reviewed_by is null and reviewed_at is null and admin_note is null));
create policy products_delete_owner_or_admin on public.products for delete to authenticated
using (public.is_nexora_admin() or (seller_id=(select auth.uid()) and listing_status='pending'));

drop policy if exists demands_owner_seller_admin_read on public.buyer_demands;
drop policy if exists demands_active_buyer_insert on public.buyer_demands;
drop policy if exists demands_owner_open_update on public.buyer_demands;
drop policy if exists demands_admin_all on public.buyer_demands;
create policy demands_select_owner_seller_or_admin on public.buyer_demands for select to authenticated
using (buyer_id=(select auth.uid()) or public.is_nexora_admin()
 or (demand_status='open' and exists(select 1 from public.profiles p join public.public_businesses b on b.seller_id=p.id
 where p.id=(select auth.uid()) and p.role='seller' and p.account_status='active')));
create policy demands_insert_buyer_or_admin on public.buyer_demands for insert to authenticated
with check (public.is_nexora_admin() or (buyer_id=(select auth.uid()) and demand_status='open'
 and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='buyer' and p.account_status='active')));
create policy demands_update_owner_or_admin on public.buyer_demands for update to authenticated
using (public.is_nexora_admin() or (buyer_id=(select auth.uid()) and demand_status='open'))
with check (public.is_nexora_admin() or buyer_id=(select auth.uid()));

drop policy if exists offers_buyer_seller_admin_read on public.seller_offers;
drop policy if exists offers_approved_seller_insert on public.seller_offers;
drop policy if exists offers_admin_all on public.seller_offers;
create policy offers_select_buyer_seller_or_admin on public.seller_offers for select to authenticated
using (seller_id=(select auth.uid()) or public.is_nexora_admin()
 or exists(select 1 from public.buyer_demands d where d.id=seller_offers.demand_id and d.buyer_id=(select auth.uid())));
create policy offers_insert_seller_or_admin on public.seller_offers for insert to authenticated
with check (public.is_nexora_admin() or (seller_id=(select auth.uid()) and offer_status='pending'
 and exists(select 1 from public.profiles p join public.public_businesses b on b.seller_id=p.id
 where p.id=(select auth.uid()) and p.role='seller' and p.account_status='active')
 and exists(select 1 from public.buyer_demands d where d.id=seller_offers.demand_id and d.demand_status='open')));
