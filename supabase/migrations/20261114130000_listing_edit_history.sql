-- NEXORA: Immutable timeline and before/after snapshots for Listing Change Requests.
begin;

alter table public.listing_edit_requests
  add column if not exists original_data jsonb;

create table if not exists public.listing_edit_request_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.listing_edit_requests(id) on delete cascade,
  event_type text not null check (event_type in ('submitted','approved','rejected')),
  actor_user_id uuid references public.profiles(id) on delete set null,
  actor_role text not null check (actor_role in ('seller','admin','system')),
  old_data jsonb not null default '{}'::jsonb check (jsonb_typeof(old_data)='object'),
  new_data jsonb not null default '{}'::jsonb check (jsonb_typeof(new_data)='object'),
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists listing_edit_request_events_request_created_idx
  on public.listing_edit_request_events(request_id,created_at asc);

alter table public.listing_edit_request_events enable row level security;
revoke all on public.listing_edit_request_events from anon,authenticated;
grant select on public.listing_edit_request_events to authenticated;

drop policy if exists listing_edit_request_events_owner_or_reviewer_read
  on public.listing_edit_request_events;
create policy listing_edit_request_events_owner_or_reviewer_read
on public.listing_edit_request_events for select to authenticated
using (
  exists(
    select 1 from public.listing_edit_requests r
    where r.id=request_id and (
      r.seller_id=(select auth.uid())
      or (r.listing_type='product' and private.has_nexora_permission('products.edit'))
      or (r.listing_type='service' and private.has_nexora_permission('services.edit'))
    )
  )
);

create or replace function private.snapshot_listing_before_edit_request()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_old jsonb;
begin
  if new.listing_type='product' then
    select jsonb_build_object(
      'product_name',p.product_name,'category',p.category,
      'market_category',p.market_category,'image_urls',coalesce(to_jsonb(p.image_urls),'[]'::jsonb),
      'description',p.description,'origin',p.origin,
      'specifications_quality',p.specifications_quality,'price',p.price,'currency',p.currency
    ) into v_old
    from public.products p
    where p.id=new.product_id and p.seller_id=new.seller_id and p.listing_status='approved';
  else
    select jsonb_build_object(
      'service_name',s.service_name,'service_category',s.service_category,
      'description',s.description,'country',s.country,'city',s.city,
      'service_area',s.service_area,'price_basis',s.price_basis,
      'price_amount',s.price_amount,'currency',s.currency,
      'availability',s.availability,'image_urls',coalesce(to_jsonb(s.image_urls),'[]'::jsonb)
    ) into v_old
    from public.service_listings s
    where s.id=new.service_listing_id and s.seller_id=new.seller_id and s.listing_status='approved';
  end if;
  if v_old is null then
    raise exception 'Approved listing snapshot could not be captured' using errcode='23514';
  end if;
  new.original_data:=v_old;
  return new;
end;
$$;

create or replace function private.log_listing_edit_request_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_event text;
  v_actor_role text;
  v_old jsonb;
begin
  if tg_op='INSERT' then
    v_event:='submitted';
    v_actor_role:='seller';
    v_old:=coalesce(new.original_data,'{}'::jsonb);
  elsif tg_op='UPDATE' and old.status='pending' and new.status in ('approved','rejected') then
    v_event:=new.status;
    v_actor_role:='admin';
    v_old:=coalesce(old.original_data,'{}'::jsonb);
  else
    return new;
  end if;
  insert into public.listing_edit_request_events(
    request_id,event_type,actor_user_id,actor_role,old_data,new_data,reason
  ) values (
    new.id,v_event,auth.uid(),v_actor_role,v_old,
    coalesce(new.proposed_changes,'{}'::jsonb),
    case when v_event='rejected' then new.review_reason else null end
  );
  return new;
end;
$$;

drop trigger if exists listing_edit_request_history_capture
  on public.listing_edit_requests;
drop trigger if exists listing_edit_request_snapshot
  on public.listing_edit_requests;
drop trigger if exists listing_edit_request_event_log
  on public.listing_edit_requests;
create trigger listing_edit_request_snapshot
before insert on public.listing_edit_requests
for each row execute function private.snapshot_listing_before_edit_request();

create trigger listing_edit_request_event_log
after insert or update of status on public.listing_edit_requests
for each row execute function private.log_listing_edit_request_event();

revoke all on function private.snapshot_listing_before_edit_request() from public,anon,authenticated;\nrevoke all on function private.log_listing_edit_request_event() from public,anon,authenticated;

comment on table public.listing_edit_request_events is
  'Append-only audit timeline of Seller listing change submissions and Admin decisions, including before/after JSON snapshots.';

commit;
