-- Prevent duplicate Delivery Jobs for the same Commerce Product Order.
-- Development staging only; no hosted Supabase or Production changes.
begin;

do $duplicates$
begin
  if exists (
    select 1 from public.delivery_jobs
    where commerce_order_id is not null
    group by commerce_order_id
    having count(*) > 1
  ) then
    raise exception 'Cannot enforce one Delivery Job per Commerce Order: duplicate links already exist. Review and reconcile them before applying this migration.';
  end if;
end
$duplicates$;

create unique index if not exists delivery_jobs_commerce_order_unique_idx
  on public.delivery_jobs(commerce_order_id)
  where commerce_order_id is not null;

create or replace function private.prevent_duplicate_order_delivery_job()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.commerce_order_id is not null and exists (
    select 1 from public.delivery_jobs j
    where j.commerce_order_id=new.commerce_order_id
      and j.id is distinct from new.id
  ) then
    raise exception 'This Commerce Order already has a linked Delivery Job'
      using errcode='23505';
  end if;
  return new;
end;
$$;

revoke all on function private.prevent_duplicate_order_delivery_job() from public,anon,authenticated;

drop trigger if exists delivery_jobs_prevent_duplicate_order_link on public.delivery_jobs;
create trigger delivery_jobs_prevent_duplicate_order_link
before insert or update of commerce_order_id on public.delivery_jobs
for each row execute function private.prevent_duplicate_order_delivery_job();

comment on index public.delivery_jobs_commerce_order_unique_idx is
  'Enforces at most one linked Delivery Job per Commerce Order; partial deliveries are recorded within that job.';

commit;
