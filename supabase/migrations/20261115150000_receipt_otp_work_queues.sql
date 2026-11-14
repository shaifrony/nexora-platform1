-- Buyer-safe receipt job discovery and assigned independent Provider work queue.
-- Development branch staging only; no hosted database mutation.
begin;

create or replace function public.get_my_order_receipt_jobs(p_order_ids uuid[])
returns table(order_id uuid,job_id uuid,job_reference text,job_status text)
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if not exists(select 1 from public.profiles p where p.id=v_actor and p.role='buyer' and p.account_status='active') then
   raise exception 'Active Buyer account required' using errcode='42501';
 end if;
 if p_order_ids is null or cardinality(p_order_ids)>50 then
   raise exception 'Provide up to 50 Order IDs' using errcode='22023';
 end if;
 return query
 select o.id,j.id,j.job_reference,j.job_status
 from public.commerce_orders o
 join public.delivery_jobs j on j.commerce_order_id=o.id
 where o.buyer_id=v_actor and o.id=any(p_order_ids)
;
end;
$$;
revoke all on function public.get_my_order_receipt_jobs(uuid[]) from public,anon;
grant execute on function public.get_my_order_receipt_jobs(uuid[]) to authenticated;

create or replace function public.get_my_assigned_receipt_jobs()
returns table(job_id uuid,job_reference text,job_status text)
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 return query
 select j.id,j.job_reference,j.job_status
 from public.delivery_jobs j
 join public.transport_providers tp on tp.id=j.assigned_provider_id
 where tp.owner_user_id=v_actor and tp.application_status='approved'
   and j.job_status in ('out_for_delivery','partially_delivered')
 order by j.updated_at desc
 limit 100;
end;
$$;
revoke all on function public.get_my_assigned_receipt_jobs() from public,anon;
grant execute on function public.get_my_assigned_receipt_jobs() to authenticated;

comment on function public.get_my_order_receipt_jobs(uuid[]) is
 'Returns only job identifiers and statuses for the authenticated active Buyer own Orders; no addresses or provider details.';
comment on function public.get_my_assigned_receipt_jobs() is
 'Returns receipt-eligible jobs assigned to an approved independent Provider owned by the authenticated user.';

commit;
