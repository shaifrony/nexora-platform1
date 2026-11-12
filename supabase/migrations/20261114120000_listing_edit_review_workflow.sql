-- NEXORA: Admin-reviewed changes to already-approved Product and Service listings.
-- Staged on nexora-development only. Do not apply to the hosted database without explicit approval.
begin;

insert into public.admin_permission_catalog(
  permission_key,department_key,permission_name,description,is_sensitive
) values (
  'services.edit','product_business','সেবা সম্পাদনা',
  'অনুমোদিত Service Listing-এর পরিবর্তন পর্যালোচনা ও অনুমোদন/প্রত্যাখ্যান',true
) on conflict (permission_key) do nothing;

create table if not exists public.listing_edit_requests (
  id uuid primary key default gen_random_uuid(),
  listing_type text not null check (listing_type in ('product','service')),
  product_id uuid references public.products(id) on delete cascade,
  service_listing_id uuid references public.service_listings(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  proposed_changes jsonb not null check (jsonb_typeof(proposed_changes)='object'),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_reason text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint listing_edit_request_target_check check (
    (listing_type='product' and product_id is not null and service_listing_id is null)
    or (listing_type='service' and service_listing_id is not null and product_id is null)
  ),
  constraint listing_edit_request_review_metadata check (
    (status='pending' and reviewed_by is null and reviewed_at is null)
    or (status<>'pending' and reviewed_by is not null and reviewed_at is not null)
  )
);

create index if not exists listing_edit_requests_seller_created_idx
  on public.listing_edit_requests(seller_id,created_at desc);
create index if not exists listing_edit_requests_pending_created_idx
  on public.listing_edit_requests(status,created_at asc);
create unique index if not exists listing_edit_requests_one_pending_product
  on public.listing_edit_requests(product_id) where status='pending' and product_id is not null;
create unique index if not exists listing_edit_requests_one_pending_service
  on public.listing_edit_requests(service_listing_id) where status='pending' and service_listing_id is not null;

alter table public.listing_edit_requests enable row level security;
revoke all on public.listing_edit_requests from anon,authenticated;
grant select on public.listing_edit_requests to authenticated;

create policy listing_edit_requests_owner_or_reviewer_read
on public.listing_edit_requests for select to authenticated
using (
  seller_id=(select auth.uid())
  or (listing_type='product' and private.has_nexora_permission('products.edit'))
  or (listing_type='service' and private.has_nexora_permission('services.edit'))
);

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
        'product_name','category','market_category','image_urls','description',
        'origin','specifications_quality','price','currency'
      ]::text[])
    ) or not (p_proposed_changes ?& array[
      'product_name','category','market_category','image_urls','description',
      'origin','specifications_quality','price','currency'
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
        market_category=v_request.proposed_changes->>'market_category',
        image_urls=v_new_urls,
        description=v_request.proposed_changes->>'description',
        origin=v_request.proposed_changes->>'origin',
        specifications_quality=nullif(v_request.proposed_changes->>'specifications_quality',''),
        price=(v_request.proposed_changes->>'price')::numeric,
        currency=v_request.proposed_changes->>'currency',
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

revoke all on function private.submit_listing_edit_request(text,uuid,jsonb) from public,anon;
revoke all on function private.review_listing_edit_request(uuid,text,text) from public,anon;
grant execute on function private.submit_listing_edit_request(text,uuid,jsonb) to authenticated;
grant execute on function private.review_listing_edit_request(uuid,text,text) to authenticated;

create or replace function public.submit_listing_edit_request(
  p_listing_type text,p_listing_id uuid,p_proposed_changes jsonb
)
returns jsonb
language sql
security invoker
set search_path=''
as $rpc$
  select private.submit_listing_edit_request(p_listing_type,p_listing_id,p_proposed_changes);
$rpc$;

create or replace function public.review_listing_edit_request(
  p_request_id uuid,p_action text,p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $rpc$
  select private.review_listing_edit_request(p_request_id,p_action,p_reason);
$rpc$;

revoke all on function public.submit_listing_edit_request(text,uuid,jsonb) from public,anon;
revoke all on function public.review_listing_edit_request(uuid,text,text) from public,anon;
grant execute on function public.submit_listing_edit_request(text,uuid,jsonb) to authenticated;
grant execute on function public.review_listing_edit_request(uuid,text,text) to authenticated;

drop policy if exists nexora_listing_images_admin_delete on storage.objects;
create policy nexora_listing_images_admin_delete
on storage.objects for delete to authenticated
using (
  bucket_id='nexora-listing-images'
  and (
    ((storage.foldername(name))[2]='products' and private.has_nexora_permission('products.edit'))
    or
    ((storage.foldername(name))[2]='services' and private.has_nexora_permission('services.edit'))
  )
);

comment on table public.listing_edit_requests is
  'Seller-submitted proposed changes to already-approved Product and Service listings. Live listing data changes only after an authorized Admin approval.';

commit;

       or coalesce(p_proposed_changes->>'price','') !~ '^[0-9]+([.][0-9]{1,2})?$'
       or (p_proposed_changes->>'price')::numeric<=0
       or jsonb_typeof(p_proposed_changes->'image_urls')<>'array'
       or jsonb_array_length(p_proposed_changes->'image_urls')>5
       or exists(select 1 from jsonb_array_elements_text(p_proposed_changes->'image_urls') u where u !~* '^https://')
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
       or p_proposed_changes->>'service_category' not in (
         'household','tutoring','plumbing','electrical','mechanic',
         'appliance_repair','it_support','beauty_laundry','other'
       )
       or length(btrim(coalesce(p_proposed_changes->>'description',''))) not between 20 and 3000
       or length(btrim(coalesce(p_proposed_changes->>'country',''))) not between 2 and 100
       or length(btrim(coalesce(p_proposed_changes->>'city',''))) not between 2 and 100
       or length(btrim(coalesce(p_proposed_changes->>'service_area',''))) not between 2 and 300
       or p_proposed_changes->>'price_basis' not in ('negotiable','per_hour','per_day','per_visit','per_job','per_month')
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
    select image_urls into v_old_urls from public.products
    where id=v_request.product_id and seller_id=v_request.seller_id and listing_status='approved'
    for update;
    if not found then raise exception 'Product is no longer approved or available' using errcode='23514'; end if;
    select array(select jsonb_array_elements_text(v_request.proposed_changes->'image_urls')) into v_new_urls;
    if p_action='approve' then
      update public.products set
        product_name=v_request.proposed_changes->>'product_name',
        category=v_request.proposed_changes->>'category',
        market_category=v_request.proposed_changes->>'market_category',
        image_urls=v_new_urls,
        description=v_request.proposed_changes->>'description',
        origin=v_request.proposed_changes->>'origin',
        specifications_quality=nullif(v_request.proposed_changes->>'specifications_quality',''),
        price=(v_request.proposed_changes->>'price')::numeric,
        currency=v_request.proposed_changes->>'currency',
        updated_at=now()
      where id=v_request.product_id;
    end if;
  else
    v_listing_id:=v_request.service_listing_id;
    select image_urls into v_old_urls from public.service_listings
    where id=v_request.service_listing_id and seller_id=v_request.seller_id and listing_status='approved'
    for update;
    if not found then raise exception 'Service is no longer approved or available' using errcode='23514'; end if;
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

revoke all on function private.submit_listing_edit_request(text,uuid,jsonb) from public,anon;
revoke all on function private.review_listing_edit_request(uuid,text,text) from public,anon;
grant execute on function private.submit_listing_edit_request(text,uuid,jsonb) to authenticated;
grant execute on function private.review_listing_edit_request(uuid,text,text) to authenticated;

create or replace function public.submit_listing_edit_request(
  p_listing_type text,p_listing_id uuid,p_proposed_changes jsonb
)
returns jsonb
language sql
security invoker
set search_path=''
as $rpc$
  select private.submit_listing_edit_request(p_listing_type,p_listing_id,p_proposed_changes);
$rpc$;

create or replace function public.review_listing_edit_request(
  p_request_id uuid,p_action text,p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $rpc$
  select private.review_listing_edit_request(p_request_id,p_action,p_reason);
$rpc$;

revoke all on function public.submit_listing_edit_request(text,uuid,jsonb) from public,anon;
revoke all on function public.review_listing_edit_request(uuid,text,text) from public,anon;
grant execute on function public.submit_listing_edit_request(text,uuid,jsonb) to authenticated;
grant execute on function public.review_listing_edit_request(uuid,text,text) to authenticated;

drop policy if exists nexora_listing_images_admin_delete on storage.objects;
create policy nexora_listing_images_admin_delete
on storage.objects for delete to authenticated
using (
  bucket_id='nexora-listing-images'
  and (
    ((storage.foldername(name))[2]='products' and private.has_nexora_permission('products.edit'))
    or
    ((storage.foldername(name))[2]='services' and private.has_nexora_permission('services.edit'))
  )
);

comment on table public.listing_edit_requests is
  'Seller-submitted proposed changes to already-approved Product and Service listings. Live listing data changes only after an authorized Admin approval.';

commit;
