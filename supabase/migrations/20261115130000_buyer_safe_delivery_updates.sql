-- NEXORA customer-safe delivery updates for Buyer Order Tracking.
-- Development branch staging only. Raw operational tracking/address data stays private.
begin;

create table if not exists private.delivery_customer_updates (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.delivery_jobs(id) on delete restrict,
  commerce_order_id uuid not null references public.commerce_orders(id) on delete restrict,
  customer_status text not null check (customer_status in (
    'preparing','picked_up','in_transit','out_for_delivery',
    'partially_delivered','delivered','delivery_issue','returned','cancelled'
  )),
  customer_message text not null check (length(btrim(customer_message)) between 3 and 300),
  customer_location_label text check (
    customer_location_label is null or length(customer_location_label)<=120
  ),
  created_at timestamptz not null default now()
);
create index if not exists delivery_customer_updates_order_idx
  on private.delivery_customer_updates(commerce_order_id,created_at,id);
create index if not exists delivery_customer_updates_job_idx
  on private.delivery_customer_updates(job_id,created_at,id);

revoke all on private.delivery_customer_updates from public,anon,authenticated;

create or replace function private.prevent_delivery_customer_update_mutation()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Customer delivery updates are append-only' using errcode='42501';
end;
$$;
revoke all on function private.prevent_delivery_customer_update_mutation() from public,anon,authenticated;

drop trigger if exists delivery_customer_updates_append_only on private.delivery_customer_updates;
create trigger delivery_customer_updates_append_only
before update or delete on private.delivery_customer_updates
for each row execute function private.prevent_delivery_customer_update_mutation();

create or replace function private.publish_delivery_customer_update()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_customer_status text;
  v_message text;
begin
  if new.commerce_order_id is null or new.job_status is not distinct from old.job_status then
    return new;
  end if;

  v_customer_status := case new.job_status
    when 'assigned' then 'preparing'
    when 'accepted' then 'preparing'
    when 'picked_up' then 'picked_up'
    when 'in_transit' then 'in_transit'
    when 'out_for_delivery' then 'out_for_delivery'
    when 'partially_delivered' then 'partially_delivered'
    when 'delivered' then 'delivered'
    when 'delivery_failed' then 'delivery_issue'
    when 'disputed' then 'delivery_issue'
    when 'returned' then 'returned'
    when 'cancelled' then 'cancelled'
    else null
  end;

  if v_customer_status is null then
    return new;
  end if;

  v_message := case v_customer_status
    when 'preparing' then 'ডেলিভারি ব্যবস্থা গ্রহণ করা হয়েছে।'
    when 'picked_up' then 'আপনার চালান বিক্রেতার কাছ থেকে সংগ্রহ করা হয়েছে।'
    when 'in_transit' then 'আপনার চালান গন্তব্যের পথে রয়েছে।'
    when 'out_for_delivery' then 'আপনার চালান পৌঁছে দেওয়ার জন্য বের হয়েছে।'
    when 'partially_delivered' then 'এই চালানের আংশিক পণ্য পৌঁছে দেওয়া হয়েছে।'
    when 'delivered' then 'ডেলিভারি কর্মী চালান পৌঁছে দেওয়ার তথ্য দিয়েছেন। অনুগ্রহ করে পণ্য হাতে পেয়ে যাচাই করুন।'
    when 'delivery_issue' then 'ডেলিভারিতে একটি সমস্যা হয়েছে। NEXORA সহায়তার সঙ্গে যোগাযোগ করুন।'
    when 'returned' then 'চালানটি ফেরত পাঠানোর প্রক্রিয়ায় রয়েছে।'
    when 'cancelled' then 'চালানের ডেলিভারি বাতিল করা হয়েছে।'
    else null
  end;

  insert into private.delivery_customer_updates(
    job_id,commerce_order_id,customer_status,customer_message
  ) values (
    new.id,new.commerce_order_id,v_customer_status,v_message
  );
  return new;
end;
$$;
revoke all on function private.publish_delivery_customer_update() from public,anon,authenticated;

drop trigger if exists delivery_jobs_publish_customer_update on public.delivery_jobs;
create trigger delivery_jobs_publish_customer_update
after update of job_status on public.delivery_jobs
for each row
when (old.job_status is distinct from new.job_status)
execute function private.publish_delivery_customer_update();

create or replace function private.get_my_order_delivery_updates(p_order_ids uuid[])
returns table (
  order_id uuid,
  job_reference text,
  customer_status text,
  customer_message text,
  customer_location_label text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
begin
  if v_actor is null then
    raise exception 'Login required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.profiles p
    where p.id=v_actor and p.role='buyer' and p.account_status='active'
  ) then
    raise exception 'Active Buyer account required' using errcode='42501';
  end if;
  if p_order_ids is null or cardinality(p_order_ids)>50 then
    raise exception 'Provide up to 50 Order IDs' using errcode='22023';
  end if;

  return query
  select u.commerce_order_id,j.job_reference,u.customer_status,
         u.customer_message,u.customer_location_label,u.created_at
  from (
    select distinct requested.order_id
    from unnest(p_order_ids) as requested(order_id)
    where requested.order_id is not null
  ) requested
  join public.commerce_orders o
    on o.id=requested.order_id and o.buyer_id=v_actor
  join private.delivery_customer_updates u
    on u.commerce_order_id=o.id
  join public.delivery_jobs j
    on j.id=u.job_id and j.commerce_order_id=o.id
  order by u.created_at asc,u.id asc;
end;
$$;
revoke all on function private.get_my_order_delivery_updates(uuid[]) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.get_my_order_delivery_updates(uuid[]) to authenticated;

create or replace function public.get_my_order_delivery_updates(p_order_ids uuid[])
returns table (
  order_id uuid,
  job_reference text,
  customer_status text,
  customer_message text,
  customer_location_label text,
  created_at timestamptz
)
language sql
security invoker
set search_path=''
as $$
  select * from private.get_my_order_delivery_updates($1);
$$;
revoke all on function public.get_my_order_delivery_updates(uuid[]) from public,anon;
grant execute on function public.get_my_order_delivery_updates(uuid[]) to authenticated;

comment on table private.delivery_customer_updates is
  'Append-only Buyer-safe delivery projection. Contains no private contacts, exact addresses, internal notes, GPS or provider identity.';
comment on function public.get_my_order_delivery_updates(uuid[]) is
  'Returns customer-safe delivery updates only for the authenticated active Buyer own Orders; raw operational tracking remains private.';

commit;
