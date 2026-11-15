-- NEXORA delivery staff operations: guarded status updates, private proof of delivery,
-- cumulative partial delivery records, and audited Buyer/Seller/worker dispute workflow.
-- Development branch only. Do not apply to hosted Supabase without explicit release approval.
begin;

-- Staff receipt verification already records actor_type='delivery_staff'; make the
-- tracking-history constraint consistent with that existing staged behaviour.
alter table public.delivery_tracking_events
  drop constraint if exists delivery_tracking_events_actor_type_check;
alter table public.delivery_tracking_events
  add constraint delivery_tracking_events_actor_type_check
  check (actor_type in ('admin','independent_provider','delivery_staff'));

create table if not exists private.delivery_proof_records (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.delivery_jobs(id) on delete restrict,
  commerce_order_id uuid references public.commerce_orders(id) on delete restrict,
  delivered_quantity numeric(14,3) not null default 0 check(delivered_quantity>=0),
  delivered_package_count integer not null default 0 check(delivered_package_count between 0 and 10000),
  recipient_name text check(recipient_name is null or length(btrim(recipient_name)) between 2 and 160),
  recipient_acknowledged boolean not null default false,
  photo_paths text[] not null default '{}',
  signature_path text,
  note text check(note is null or length(note)<=1000),
  created_by uuid not null references public.profiles(id) on delete restrict,
  actor_type text not null check(actor_type in ('admin','delivery_staff')),
  created_at timestamptz not null default now(),
  check(cardinality(photo_paths)<=5),
  check(delivered_quantity>0 or delivered_package_count>0)
);
create index if not exists delivery_proof_records_job_idx
  on private.delivery_proof_records(job_id,created_at,id);
create index if not exists delivery_proof_records_order_idx
  on private.delivery_proof_records(commerce_order_id,created_at,id);

create table if not exists private.delivery_disputes (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.delivery_jobs(id) on delete restrict,
  commerce_order_id uuid references public.commerce_orders(id) on delete restrict,
  raised_by uuid not null references public.profiles(id) on delete restrict,
  raiser_role text not null check(raiser_role in ('buyer','seller','delivery_staff','admin')),
  reason_code text not null check(reason_code in (
    'missing_items','damaged_items','wrong_items','quantity_mismatch',
    'recipient_denies_receipt','late_delivery','proof_concern','other'
  )),
  description text not null check(length(btrim(description)) between 10 and 2000),
  dispute_status text not null default 'open'
    check(dispute_status in ('open','under_review','resolved','rejected')),
  resolution text check(resolution is null or length(resolution)<=2000),
  reviewed_by uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists delivery_disputes_job_idx
  on private.delivery_disputes(job_id,created_at desc);
create index if not exists delivery_disputes_status_idx
  on private.delivery_disputes(dispute_status,created_at desc);

revoke all on private.delivery_proof_records,private.delivery_disputes from public,anon,authenticated;

create or replace function private.is_assigned_delivery_staff(p_job_id uuid)
returns boolean
language sql stable security definer set search_path=''
as $$
  select exists(
    select 1
    from public.delivery_jobs j
    join public.delivery_network_staff s on s.id=j.assigned_staff_id
    join public.delivery_network_partners dp on dp.id=s.partner_id
    join public.profiles worker on worker.id=s.auth_user_id
    where j.id=p_job_id and s.auth_user_id=auth.uid()
      and s.staff_status='active' and dp.partner_status='approved'
      and worker.account_status='active' and worker.role in ('buyer','seller','porter')
      and j.assignment_source in ('nexora_team','courier_partner')
  );
$$$;
revoke all on function private.is_assigned_delivery_staff(uuid) from public,anon,authenticated;
grant execute on function private.is_assigned_delivery_staff(uuid) to authenticated;

create or replace function private.can_read_delivery_job_evidence(p_job_id uuid)
returns boolean
language sql stable security definer set search_path=''
as $$
  select private.is_assigned_delivery_staff(p_job_id)
    or exists(
      select 1 from public.delivery_jobs j
      join public.commerce_orders o on o.id=j.commerce_order_id
      where j.id=p_job_id and (o.buyer_id=auth.uid() or o.seller_id=auth.uid())
    )
    or (
      (select auth.jwt()->>'aal')='aal2'
      and private.has_nexora_permission('logistics.view')
      and exists(select 1 from public.admin_staff s join public.profiles p on p.id=s.user_id
        where s.user_id=auth.uid() and s.is_active=true and p.role='admin' and p.account_status='active')
    );
$$$;
revoke all on function private.can_read_delivery_job_evidence(uuid) from public,anon,authenticated;
grant execute on function private.can_read_delivery_job_evidence(uuid) to authenticated;

create or replace function private.can_manage_delivery_job_evidence(p_job_id uuid)
returns boolean
language sql stable security definer set search_path=''
as $$
  select private.is_assigned_delivery_staff(p_job_id)
    or (
      (select auth.jwt()->>'aal')='aal2'
      and private.has_nexora_permission('logistics.assign')
      and exists(select 1 from public.admin_staff s join public.profiles p on p.id=s.user_id
        where s.user_id=auth.uid() and s.is_active=true and p.role='admin' and p.account_status='active')
    );
$$$;
revoke all on function private.can_manage_delivery_job_evidence(uuid) from public,anon,authenticated;
grant execute on function private.can_manage_delivery_job_evidence(uuid) to authenticated;

-- A private bucket: workers/Admin may upload to their authorized job folder;
-- Buyer/Seller can read evidence for their own order. No update/delete policy exists.
insert into storage.buckets(id,name,public)
values('nexora-delivery-evidence','nexora-delivery-evidence',false)
on conflict(id) do update set public=false, file_size_limit=10485760,
  allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists nexora_delivery_evidence_upload on storage.objects;
create policy nexora_delivery_evidence_upload on storage.objects
for insert to authenticated
with check (
  bucket_id='nexora-delivery-evidence'
  and split_part(name,'/',1) ~ '^[0-9a-fA-F-]{36}$'
  and private.can_manage_delivery_job_evidence(split_part(name,'/',1)::uuid)
);
drop policy if exists nexora_delivery_evidence_read on storage.objects;
create policy nexora_delivery_evidence_read on storage.objects
for select to authenticated
using (
  bucket_id='nexora-delivery-evidence'
  and split_part(name,'/',1) ~ '^[0-9a-fA-F-]{36}$'
  and private.can_read_delivery_job_evidence(split_part(name,'/',1)::uuid)
);

create or replace function private.update_my_delivery_job_status(
  p_job_id uuid,p_next_status text,p_location_label text default null,p_note text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_old text;v_allowed boolean:=false;
begin
  if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
  if not private.is_assigned_delivery_staff(p_job_id) then
    raise exception 'Only the assigned active delivery worker can update this job' using errcode='42501';
  end if;
  if length(coalesce(p_location_label,''))>120 or length(coalesce(p_note,''))>1000
     or p_next_status not in ('accepted','picked_up','in_transit','out_for_delivery','delivery_failed') then
    raise exception 'Invalid delivery status update' using errcode='22023';
  end if;
  select job_status into v_old from public.delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'Delivery Job not found' using errcode='P0002'; end if;
  v_allowed:=case v_old
    when 'assigned' then p_next_status in ('accepted','delivery_failed')
    when 'accepted' then p_next_status in ('picked_up','delivery_failed')
    when 'picked_up' then p_next_status in ('in_transit','delivery_failed')
    when 'in_transit' then p_next_status in ('out_for_delivery','delivery_failed')
    when 'out_for_delivery' then p_next_status='delivery_failed'
    when 'partially_delivered' then p_next_status in ('in_transit','out_for_delivery','delivery_failed')
    else false end;
  if not v_allowed then raise exception 'Invalid delivery status transition: % -> %',v_old,p_next_status using errcode='22023'; end if;
  update public.delivery_jobs set job_status=p_next_status,updated_at=now() where id=p_job_id;
  insert into public.delivery_tracking_events(job_id,previous_status,new_status,location_description,note,
    external_tracking_code,actor_user_id,actor_type)
  values(p_job_id,v_old,p_next_status,nullif(btrim(coalesce(p_location_label,'')), ''),
    nullif(btrim(coalesce(p_note,'')),''),null,v_actor,'delivery_staff');
  return jsonb_build_object('job_id',p_job_id,'previous_status',v_old,'status',p_next_status);
end;
$$$;
revoke all on function private.update_my_delivery_job_status(uuid,text,text,text) from public,anon;
grant execute on function private.update_my_delivery_job_status(uuid,text,text,text) to authenticated;

create or replace function public.update_my_delivery_job_status(
 p_job_id uuid,p_next_status text,p_location_label text default null,p_note text default null
) returns jsonb language sql security invoker set search_path=''
as $$ select private.update_my_delivery_job_status($1,$2,$3,$4); $$$;
revoke all on function public.update_my_delivery_job_status(uuid,text,text,text) from public,anon;
grant execute on function public.update_my_delivery_job_status(uuid,text,text,text) to authenticated;

create or replace function private.record_delivery_proof(
 p_job_id uuid,p_delivered_quantity numeric,p_delivered_package_count integer,
 p_recipient_name text,p_recipient_acknowledged boolean,p_photo_paths text[],
 p_signature_path text,p_note text
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_admin_code text;v_actor_type text;v_job public.delivery_jobs%rowtype;
 v_order_quantity numeric;v_already_delivered numeric;v_record_id uuid;v_path text;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 if private.is_assigned_delivery_staff(p_job_id) then
   v_actor_type:='delivery_staff';
 elsif (select auth.jwt()->>'aal')='aal2'
   and private.has_nexora_permission('logistics.assign') then
   select s.admin_code into v_admin_code from public.admin_staff s join public.profiles p on p.id=s.user_id
    where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
   if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
   v_actor_type:='admin';
 else
   raise exception 'Assigned delivery worker or AAL2 logistics Admin required' using errcode='42501';
 end if;
 if p_delivered_quantity is null or p_delivered_quantity<0
   or coalesce(p_delivered_package_count,0)<0 or p_delivered_package_count>10000
   or (p_delivered_quantity=0 and coalesce(p_delivered_package_count,0)=0)
   or coalesce(cardinality(p_photo_paths),0)>5
   or length(coalesce(p_recipient_name,''))>160 or length(coalesce(p_note,''))>1000 then
   raise exception 'Invalid proof-of-delivery details' using errcode='22023';
 end if;
 select * into v_job from public.delivery_jobs where id=p_job_id for update;
 if not found then raise exception 'Delivery Job not found' using errcode='P0002'; end if;
 if v_job.job_status not in ('out_for_delivery','partially_delivered','delivered') then
   raise exception 'Proof can only be recorded for an out-for-delivery or completed shipment' using errcode='22023';
 end if;
 if v_job.commerce_order_id is not null then
   select quantity into v_order_quantity from public.commerce_orders where id=v_job.commerce_order_id;
   if v_order_quantity is null or p_delivered_quantity<=0 then
     raise exception 'A positive delivered quantity is required for an Order-linked shipment' using errcode='22023';
   end if;
   select coalesce(sum(delivered_quantity),0) into v_already_delivered
   from private.delivery_proof_records where job_id=p_job_id;
   if v_already_delivered+p_delivered_quantity>v_order_quantity then
     raise exception 'Delivered quantity cannot exceed the ordered quantity' using errcode='22023';
   end if;
 else
   v_already_delivered:=0;
 end if;
 if coalesce(cardinality(p_photo_paths),0)=0 and p_signature_path is null then
   raise exception 'At least one delivery photo or recipient signature is required' using errcode='22023';
 end if;
 foreach v_path in array coalesce(p_photo_paths,'{}') loop
   if v_path !~ ('^'||p_job_id::text||'/[A-Za-z0-9._/-]{1,240}$')
      or position('..' in v_path)>0
      or not exists(select 1 from storage.objects o where o.bucket_id='nexora-delivery-evidence' and o.name=v_path) then
     raise exception 'Delivery photo must be uploaded to this Job private evidence folder' using errcode='22023';
   end if;
 end loop;
 if p_signature_path is not null and (
   p_signature_path !~ ('^'||p_job_id::text||'/[A-Za-z0-9._/-]{1,240}$')
   or position('..' in p_signature_path)>0
   or not exists(select 1 from storage.objects o where o.bucket_id='nexora-delivery-evidence' and o.name=p_signature_path)
 ) then
   raise exception 'Recipient signature must be uploaded to this Job private evidence folder' using errcode='22023';
 end if;
 insert into private.delivery_proof_records(job_id,commerce_order_id,delivered_quantity,delivered_package_count,
   recipient_name,recipient_acknowledged,photo_paths,signature_path,note,created_by,actor_type)
 values(p_job_id,v_job.commerce_order_id,p_delivered_quantity,coalesce(p_delivered_package_count,0),
   nullif(btrim(coalesce(p_recipient_name,'')),''),coalesce(p_recipient_acknowledged,false),
   coalesce(p_photo_paths,'{}'),p_signature_path,nullif(btrim(coalesce(p_note,'')),''),v_actor,v_actor_type)
 returning id into v_record_id;
 if v_job.commerce_order_id is not null and v_job.job_status<>'partially_delivered'
    and v_already_delivered+p_delivered_quantity<v_order_quantity then
   update public.delivery_jobs set job_status='partially_delivered',updated_at=now() where id=p_job_id;
   insert into public.delivery_tracking_events(job_id,previous_status,new_status,location_description,note,
     external_tracking_code,actor_user_id,actor_type)
   values(p_job_id,v_job.job_status,'partially_delivered',null,'আংশিক ডেলিভারির প্রমাণ সংরক্ষণ করা হয়েছে।',
     null,v_actor,v_actor_type);
 end if;
 if v_actor_type='admin' then
   insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
   values(v_actor,v_admin_code,'delivery_job.proof_recorded','delivery_job',p_job_id::text,
     jsonb_build_object('proof_id',v_record_id,'photo_count',cardinality(coalesce(p_photo_paths,'{}')),
       'has_signature',p_signature_path is not null,'delivered_quantity',p_delivered_quantity));
 end if;
 return jsonb_build_object('proof_id',v_record_id,'job_id',p_job_id,'status',
   case when v_job.commerce_order_id is not null and v_already_delivered+p_delivered_quantity<v_order_quantity
     then 'partially_delivered' else v_job.job_status end);
end;
$$$;
revoke all on function private.record_delivery_proof(uuid,numeric,integer,text,boolean,text[],text,text) from public,anon;
grant execute on function private.record_delivery_proof(uuid,numeric,integer,text,boolean,text[],text,text) to authenticated;

create or replace function public.record_delivery_proof(
 p_job_id uuid,p_delivered_quantity numeric,p_delivered_package_count integer,
 p_recipient_name text,p_recipient_acknowledged boolean,p_photo_paths text[],
 p_signature_path text,p_note text
) returns jsonb language sql security invoker set search_path=''
as $$ select private.record_delivery_proof($1,$2,$3,$4,$5,$6,$7,$8); $$$;
revoke all on function public.record_delivery_proof(uuid,numeric,integer,text,boolean,text[],text,text) from public,anon;
grant execute on function public.record_delivery_proof(uuid,numeric,integer,text,boolean,text[],text,text) to authenticated;

create or replace function private.raise_delivery_dispute(
 p_job_id uuid,p_reason_code text,p_description text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_job public.delivery_jobs%rowtype;v_role text;v_dispute uuid;v_admin_code text;
begin
 if v_actor is null then raise exception 'Login required' using errcode='42501'; end if;
 select * into v_job from public.delivery_jobs where id=p_job_id for update;
 if not found then raise exception 'Delivery Job not found' using errcode='P0002'; end if;
 if p_reason_code not in ('missing_items','damaged_items','wrong_items','quantity_mismatch',
   'recipient_denies_receipt','late_delivery','proof_concern','other')
   or length(btrim(coalesce(p_description,''))) not between 10 and 2000 then
   raise exception 'Invalid dispute details' using errcode='22023';
 end if;
 if exists(select 1 from private.delivery_disputes d where d.job_id=p_job_id
   and d.dispute_status in ('open','under_review')) then
   raise exception 'An active dispute already exists for this delivery' using errcode='23505';
 end if;
 if exists(select 1 from public.commerce_orders o where o.id=v_job.commerce_order_id and o.buyer_id=v_actor) then
   v_role:='buyer';
 elsif exists(select 1 from public.commerce_orders o where o.id=v_job.commerce_order_id and o.seller_id=v_actor) then
   v_role:='seller';
 elsif private.is_assigned_delivery_staff(p_job_id) then
   v_role:='delivery_staff';
 elsif (select auth.jwt()->>'aal')='aal2' and private.has_nexora_permission('logistics.assign') then
   select s.admin_code into v_admin_code from public.admin_staff s join public.profiles p on p.id=s.user_id
    where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
   if v_admin_code is not null then v_role:='admin'; end if;
 end if;
 if v_role is null then raise exception 'Only the order Buyer/Seller, assigned worker or AAL2 logistics Admin can raise a dispute' using errcode='42501'; end if;
 if v_job.job_status not in ('out_for_delivery','partially_delivered','delivered','disputed','delivery_failed','returned') then
   raise exception 'This delivery is not in a disputable state' using errcode='22023';
 end if;
 insert into private.delivery_disputes(job_id,commerce_order_id,raised_by,raiser_role,reason_code,description)
 values(p_job_id,v_job.commerce_order_id,v_actor,v_role,p_reason_code,btrim(p_description))
 returning id into v_dispute;
 if v_job.job_status in ('partially_delivered','delivered') and v_job.job_status<>'disputed' then
   update public.delivery_jobs set job_status='disputed',updated_at=now() where id=p_job_id;
 end if;
 if v_role='admin' then
   insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
   values(v_actor,v_admin_code,'delivery_job.dispute_raised','delivery_dispute',v_dispute::text,
     jsonb_build_object('job_id',p_job_id,'reason_code',p_reason_code));
 end if;
 return v_dispute;
end;
$$$;
revoke all on function private.raise_delivery_dispute(uuid,text,text) from public,anon;
grant execute on function private.raise_delivery_dispute(uuid,text,text) to authenticated;

create or replace function public.raise_delivery_dispute(p_job_id uuid,p_reason_code text,p_description text)
returns uuid language sql security invoker set search_path=''
as $$ select private.raise_delivery_dispute($1,$2,$3); $$$;
revoke all on function public.raise_delivery_dispute(uuid,text,text) from public,anon;
grant execute on function public.raise_delivery_dispute(uuid,text,text) to authenticated;

create or replace function private.review_delivery_dispute(
 p_dispute_id uuid,p_next_status text,p_resolution text
) returns void
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_admin_code text;v_old text;v_job uuid;
begin
 if v_actor is null or (select auth.jwt()->>'aal') is distinct from 'aal2'
   or not private.has_nexora_permission('logistics.assign') then
   raise exception 'Active Admin MFA and logistics.assign permission required' using errcode='42501';
 end if;
 select s.admin_code into v_admin_code from public.admin_staff s join public.profiles p on p.id=s.user_id
 where s.user_id=v_actor and s.is_active=true and p.role='admin' and p.account_status='active';
 if v_admin_code is null then raise exception 'Active Admin membership required' using errcode='42501'; end if;
 if p_next_status not in ('under_review','resolved','rejected')
   or (p_next_status in ('resolved','rejected') and length(btrim(coalesce(p_resolution,'')))<10)
   or length(coalesce(p_resolution,''))>2000 then
   raise exception 'Invalid dispute decision or resolution note' using errcode='22023';
 end if;
 select dispute_status,job_id into v_old,v_job from private.delivery_disputes where id=p_dispute_id for update;
 if not found then raise exception 'Delivery dispute not found' using errcode='P0002'; end if;
 if v_old not in ('open','under_review') then raise exception 'Dispute is already closed' using errcode='22023'; end if;
 update private.delivery_disputes set dispute_status=p_next_status,
   resolution=case when p_next_status in ('resolved','rejected') then btrim(p_resolution) else null end,
   reviewed_by=v_actor,reviewed_at=now(),updated_at=now()
 where id=p_dispute_id;
 insert into public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,details)
 values(v_actor,v_admin_code,'delivery_dispute.reviewed','delivery_dispute',p_dispute_id::text,
   jsonb_build_object('job_id',v_job,'previous_status',v_old,'new_status',p_next_status));
end;
$$$;
revoke all on function private.review_delivery_dispute(uuid,text,text) from public,anon;
grant execute on function private.review_delivery_dispute(uuid,text,text) to authenticated;

create or replace function public.review_delivery_dispute(p_dispute_id uuid,p_next_status text,p_resolution text)
returns void language sql security invoker set search_path=''
as $$ select private.review_delivery_dispute($1,$2,$3); $$$;
revoke all on function public.review_delivery_dispute(uuid,text,text) from public,anon;
grant execute on function public.review_delivery_dispute(uuid,text,text) to authenticated;


create or replace function private.get_my_assigned_delivery_jobs()
returns table(
 job_id uuid,job_reference text,job_status text,package_description text,package_count integer,
 pickup_contact_name text,pickup_contact_phone text,pickup_address text,pickup_city text,pickup_country text,
 recipient_contact_name text,recipient_contact_phone text,delivery_address text,delivery_city text,delivery_country text,
 delivery_deadline timestamptz,updated_at timestamptz
)
language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();
begin
 if v_actor is null or not exists(select 1 from public.profiles p where p.id=v_actor
   and p.role in ('buyer','seller','porter') and p.account_status='active') then
   raise exception 'Active identity-bound delivery worker account required' using errcode='42501';
 end if;
 return query
 select j.id,j.job_reference,j.job_status,j.package_description,j.package_count,
   j.pickup_contact_name,j.pickup_contact_phone,j.pickup_address,j.pickup_city,j.pickup_country,
   j.recipient_contact_name,j.recipient_contact_phone,j.delivery_address,j.delivery_city,j.delivery_country,
   j.delivery_deadline,j.updated_at
 from public.delivery_jobs j
 join public.delivery_network_staff s on s.id=j.assigned_staff_id
 join public.delivery_network_partners dp on dp.id=s.partner_id
 where s.auth_user_id=v_actor and s.staff_status='active' and dp.partner_status='approved'
   and j.assignment_source in ('nexora_team','courier_partner')
   and j.job_status in ('assigned','accepted','picked_up','in_transit','out_for_delivery','partially_delivered')
 order by j.delivery_deadline asc nulls last,j.updated_at desc
 limit 100;
end;
$$$;
revoke all on function private.get_my_assigned_delivery_jobs() from public,anon,authenticated;
grant execute on function private.get_my_assigned_delivery_jobs() to authenticated;
create or replace function public.get_my_assigned_delivery_jobs()
returns table(
 job_id uuid,job_reference text,job_status text,package_description text,package_count integer,
 pickup_contact_name text,pickup_contact_phone text,pickup_address text,pickup_city text,pickup_country text,
 recipient_contact_name text,recipient_contact_phone text,delivery_address text,delivery_city text,delivery_country text,
 delivery_deadline timestamptz,updated_at timestamptz
)
language sql security invoker set search_path=''
as $$ select * from private.get_my_assigned_delivery_jobs(); $$;
revoke all on function public.get_my_assigned_delivery_jobs() from public,anon;
grant execute on function public.get_my_assigned_delivery_jobs() to authenticated;

create or replace function private.get_my_delivery_proof_records(p_job_id uuid)
returns table(
 proof_id uuid,delivered_quantity numeric,delivered_package_count integer,recipient_name text,
 recipient_acknowledged boolean,photo_paths text[],signature_path text,note text,created_at timestamptz
)
language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid() is null or not private.can_read_delivery_job_evidence(p_job_id) then
   raise exception 'You are not authorized to view this delivery evidence' using errcode='42501';
 end if;
 return query
 select p.id,p.delivered_quantity,p.delivered_package_count,p.recipient_name,
   p.recipient_acknowledged,p.photo_paths,p.signature_path,p.note,p.created_at
 from private.delivery_proof_records p where p.job_id=p_job_id
 order by p.created_at,p.id;
end;
$$$;
revoke all on function private.get_my_delivery_proof_records(uuid) from public,anon,authenticated;
grant execute on function private.get_my_delivery_proof_records(uuid) to authenticated;
create or replace function public.get_my_delivery_proof_records(p_job_id uuid)
returns table(
 proof_id uuid,delivered_quantity numeric,delivered_package_count integer,recipient_name text,
 recipient_acknowledged boolean,photo_paths text[],signature_path text,note text,created_at timestamptz
)
language sql security invoker set search_path=''
as $$ select * from private.get_my_delivery_proof_records($1); $$;
revoke all on function public.get_my_delivery_proof_records(uuid) from public,anon;
grant execute on function public.get_my_delivery_proof_records(uuid) to authenticated;

create or replace function private.get_my_delivery_disputes(p_job_id uuid)
returns table(
 dispute_id uuid,reason_code text,description text,raiser_role text,dispute_status text,
 resolution text,created_at timestamptz,updated_at timestamptz
)
language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid() is null or not (
   private.is_assigned_delivery_staff(p_job_id)
   or exists(select 1 from public.delivery_jobs j join public.commerce_orders o on o.id=j.commerce_order_id
     where j.id=p_job_id and (o.buyer_id=auth.uid() or o.seller_id=auth.uid()))
   or ((select auth.jwt()->>'aal')='aal2' and private.has_nexora_permission('logistics.view')
     and exists(select 1 from public.admin_staff s join public.profiles p on p.id=s.user_id
       where s.user_id=auth.uid() and s.is_active=true and p.role='admin' and p.account_status='active'))
 ) then
   raise exception 'You are not authorized to view this delivery dispute' using errcode='42501';
 end if;
 return query select d.id,d.reason_code,d.description,d.raiser_role,d.dispute_status,
   d.resolution,d.created_at,d.updated_at
 from private.delivery_disputes d where d.job_id=p_job_id order by d.created_at desc;
end;
$$$;
revoke all on function private.get_my_delivery_disputes(uuid) from public,anon,authenticated;
grant execute on function private.get_my_delivery_disputes(uuid) to authenticated;
create or replace function public.get_my_delivery_disputes(p_job_id uuid)
returns table(
 dispute_id uuid,reason_code text,description text,raiser_role text,dispute_status text,
 resolution text,created_at timestamptz,updated_at timestamptz
)
language sql security invoker set search_path=''
as $$ select * from private.get_my_delivery_disputes($1); $$;
revoke all on function public.get_my_delivery_disputes(uuid) from public,anon;
grant execute on function public.get_my_delivery_disputes(uuid) to authenticated;

comment on table private.delivery_proof_records is
 'Append-only delivery evidence metadata. Images and recipient signatures live in a private Storage bucket; never expose public object URLs.';
comment on table private.delivery_disputes is
 'Private delivery dispute workflow with Buyer/Seller/assigned-worker initiation and AAL2 Admin review.';
comment on function public.update_my_delivery_job_status(uuid,text,text,text) is
 'Assigned active NEXORA Team/Courier worker may perform guarded operational status transitions; delivered requires Buyer receipt OTP.';
comment on function public.record_delivery_proof(uuid,numeric,integer,text,boolean,text[],text,text) is
 'Records private photo/signature proof for an assigned job; cumulative Order quantity cannot exceed the Buyer Order quantity.';
comment on function public.raise_delivery_dispute(uuid,text,text) is
 'Allows only the related Buyer/Seller, assigned active worker or AAL2 logistics Admin to open a delivery dispute.';
comment on function public.review_delivery_dispute(uuid,text,text) is
 'AAL2 logistics Admin moves a dispute to review/resolution with an auditable reason.';

commit;
