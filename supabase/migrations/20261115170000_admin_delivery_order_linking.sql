-- Admin-only link between a ready Commerce Product Order and its Delivery Job.
-- Development branch staging only. No hosted migration or production deployment.
begin;

create or replace function private.get_admin_delivery_order_candidates()
returns table(
  order_id uuid,
  order_code text,
  listing_name text,
  quantity numeric,
  currency text,
  buyer_name text,
  fulfilment_location text,
  seller_business_name text,
  pickup_address text,
  pickup_city text,
  pickup_country text,
  existing_delivery_jobs bigint,
  ready_at timestamptz
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_admin_code text;
begin
  if v_actor is null then
    raise exception 'Login required' using errcode='42501';
  end if;
  if not private.has_nexora_permission('logistics.assign')
     or (select auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  select s.admin_code into v_admin_code
  from public.admin_staff s
  join public.profiles p on p.id=s.user_id
  where s.user_id=v_actor and s.is_active=true
    and p.role='admin' and p.account_status='active';
  if v_admin_code is null then
    raise exception 'Active Admin membership required' using errcode='42501';
  end if;

  return query
  select o.id,o.order_code,coalesce(pr.product_name,o.order_code),o.quantity,o.currency,
    buyer.full_name,o.fulfilment_location,bp.display_name,bp.sales_center_address,bp.city,bp.country,
    (select count(*) from public.delivery_jobs j where j.commerce_order_id=o.id),
    o.ready_at
  from public.commerce_orders o
  join public.profiles buyer on buyer.id=o.buyer_id
  join public.business_profiles bp on bp.seller_id=o.seller_id
  left join public.products pr on pr.id=o.listing_id and pr.seller_id=o.seller_id
  where o.order_status='ready_for_confirmation'
    and o.listing_type='product'
  order by o.ready_at desc nulls last,o.created_at desc
  limit 100;
end;
$$;

create or replace function private.create_delivery_network_job_from_order(
 p_commerce_order_id uuid,
 p_external_reference text,p_package_description text,p_package_count integer,
 p_pickup_contact_name text,p_pickup_contact_phone text,p_pickup_address text,p_pickup_city text,p_pickup_country text,
 p_recipient_contact_name text,p_recipient_contact_phone text,p_delivery_address text,p_delivery_city text,p_delivery_country text,
 p_requested_pickup_at timestamptz,p_delivery_deadline timestamptz,p_special_instructions text,
 p_delivery_mode text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_admin_code text;
  v_order_status text;
  v_listing_type text;
begin
  if v_actor is null then
    raise exception 'Login required' using errcode='42501';
  end if;
  if not private.has_nexora_permission('logistics.assign')
     or (select auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
  end if;
  select s.admin_code into v_admin_code
  from public.admin_staff s
  join public.profiles p on p.id=s.user_id
  where s.user_id=v_actor and s.is_active=true
    and p.role='admin' and p.account_status='active';
  if v_admin_code is null then
    raise exception 'Active Admin membership required' using errcode='42501';
  end if;

  select o.order_status,o.listing_type into v_order_status,v_listing_type
  from public.commerce_orders o
  where o.id=p_commerce_order_id
  for update;
  if not found then
    raise exception 'Commerce Order not found' using errcode='P0002';
  end if;
  if v_order_status<>'ready_for_confirmation' or v_listing_type<>'product' then
    raise exception 'Only a ready Product Order can be linked to a Delivery Job' using errcode='22023';
  end if;

  return private.create_delivery_network_job(
    p_external_reference,p_package_description,p_package_count,
    p_pickup_contact_name,p_pickup_contact_phone,p_pickup_address,p_pickup_city,p_pickup_country,
    p_recipient_contact_name,p_recipient_contact_phone,p_delivery_address,p_delivery_city,p_delivery_country,
    p_requested_pickup_at,p_delivery_deadline,p_special_instructions,p_delivery_mode,p_commerce_order_id
  );
end;
$$;

create or replace function public.get_admin_delivery_order_candidates()
returns table(
  order_id uuid,
  order_code text,
  listing_name text,
  quantity numeric,
  currency text,
  buyer_name text,
  fulfilment_location text,
  seller_business_name text,
  pickup_address text,
  pickup_city text,
  pickup_country text,
  existing_delivery_jobs bigint,
  ready_at timestamptz
)
language sql
security invoker
set search_path=''
as $$ select * from private.get_admin_delivery_order_candidates(); $$;

create or replace function public.create_delivery_network_job_from_order(
 p_commerce_order_id uuid,
 p_external_reference text,p_package_description text,p_package_count integer,
 p_pickup_contact_name text,p_pickup_contact_phone text,p_pickup_address text,p_pickup_city text,p_pickup_country text,
 p_recipient_contact_name text,p_recipient_contact_phone text,p_delivery_address text,p_delivery_city text,p_delivery_country text,
 p_requested_pickup_at timestamptz,p_delivery_deadline timestamptz,p_special_instructions text,
 p_delivery_mode text
) returns jsonb
language sql
security invoker
set search_path=''
as $$
 select private.create_delivery_network_job_from_order(
   $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18
 );
$$;

revoke all on function private.get_admin_delivery_order_candidates() from public,anon;
revoke all on function private.create_delivery_network_job_from_order(uuid,text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.get_admin_delivery_order_candidates() to authenticated;
grant execute on function private.create_delivery_network_job_from_order(uuid,text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text) to authenticated;

revoke all on function public.get_admin_delivery_order_candidates() from public,anon;
revoke all on function public.create_delivery_network_job_from_order(uuid,text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text) from public,anon;
grant execute on function public.get_admin_delivery_order_candidates() to authenticated;
grant execute on function public.create_delivery_network_job_from_order(uuid,text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text) to authenticated;

comment on function public.get_admin_delivery_order_candidates() is
 'AAL2 Admin-only list of ready Product Orders with minimum pickup/destination data for creating linked delivery jobs.';
comment on function public.create_delivery_network_job_from_order(uuid,text,text,integer,text,text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,text) is
 'Creates a Delivery Job linked to a locked, ready Product Commerce Order. The Buyer-facing tracking projection then follows the linked Order.';

commit;
