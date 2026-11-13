-- NEXORA central officer account, position and permission administration.
-- Development-branch staging only. Do not apply until the complete migration chain is reconciled
-- and this migration is tested on an isolated Supabase database.

begin;

alter table public.admin_staff
  add column if not exists staff_email text,
  add column if not exists position_key text not null default 'department_officer',
  add column if not exists reports_to_user_id uuid references public.admin_staff(user_id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.admin_staff'::regclass
      and conname='admin_staff_position_key_check'
  ) then
    alter table public.admin_staff
      add constraint admin_staff_position_key_check
      check (position_key in ('director','managing_director','department_head','department_officer'));
  end if;
end $$;

update public.admin_staff
set position_key = case when admin_level='super_admin' then 'director' else 'department_officer' end
where position_key is null
   or (admin_level='super_admin' and position_key<>'director');

insert into public.admin_departments(department_key,department_name,description,is_assignable)
values
 ('managing_director','Managing Director Office','দৈনন্দিন পরিচালনা ও বিভাগগুলোর সমন্বয়; সাংগঠনিক কাঠামো পরিবর্তনের ক্ষমতা নেই।',true),
 ('marketing','Marketing Department','Buyer, Seller, ব্যবসা ও অংশীদার সংগ্রহ এবং ব্যবসা বৃদ্ধি।',true),
 ('transport','Transport & Logistics Department','Retail ও Wholesale ডেলিভারি, Provider/Partner, Assignment ও Tracking।',true),
 ('accounts','Accounts & Finance Department','আর্থিক রেকর্ড, হিসাব, ফি, Refund ও Settlement নিয়ন্ত্রণ।',true)
on conflict (department_key) do update
set department_name=excluded.department_name,
    description=excluded.description,
    is_assignable=true;

insert into public.admin_permission_catalog(permission_key,department_key,permission_name,description,is_sensitive)
values
 ('marketing.leads.view','marketing','সম্ভাব্য Buyer/Seller দেখা','Marketing lead ও onboarding তালিকা দেখা।',false),
 ('marketing.leads.manage','marketing','Buyer/Seller সংগ্রহ ব্যবস্থাপনা','Marketing lead ও outreach কাজ পরিচালনা।',true),
 ('marketing.campaigns.manage','marketing','Marketing Campaign পরিচালনা','Campaign তৈরি ও পরিচালনা।',true),
 ('transport.partners.view','transport','Transport Partner দেখা','Courier ও delivery partner তালিকা দেখা।',false),
 ('transport.partners.manage','transport','Transport Partner পরিচালনা','Partner onboarding ও operational status পরিচালনা।',true),
 ('transport.staff.manage','transport','Transport Staff পরিচালনা','NEXORA delivery roster পরিচালনা।',true),
 ('logistics.view','transport','Delivery দেখা','Retail ও Wholesale delivery কাজ দেখা।',false),
 ('logistics.assign','transport','Delivery Assignment','Delivery Provider, Team বা Courier Partner assign ও status পরিচালনা।',true),
 ('finance.view','accounts','Finance তথ্য দেখা','অনুমোদিত আর্থিক রেকর্ড ও সারাংশ দেখা।',false),
 ('finance.transactions.view','accounts','লেনদেন দেখা','আর্থিক লেনদেন ও reconciliation record দেখা।',false),
 ('finance.transactions.manage','accounts','লেনদেন ব্যবস্থাপনা','অনুমোদিত finance transaction workflow পরিচালনা।',true),
 ('finance.refunds.request','accounts','Refund অনুরোধ','Refund request তৈরি ও জমা দেওয়া।',true),
 ('finance.refunds.approve','accounts','Refund অনুমোদন','স্বতন্ত্র অনুমোদনকারী হিসেবে Refund অনুমোদন।',true),
 ('finance.payouts.manage','accounts','Payout ও Settlement পরিচালনা','অনুমোদিত payout ও settlement workflow পরিচালনা।',true)
on conflict (permission_key) do nothing;

create unique index if not exists admin_staff_one_active_md_idx
  on public.admin_staff(position_key)
  where position_key='managing_director' and is_active=true;

create index if not exists admin_staff_department_position_idx
  on public.admin_staff(department_key,position_key,is_active);

create or replace function private.manage_nexora_officer(
  p_email text,
  p_action text,
  p_department_key text default null,
  p_position_key text default null,
  p_permissions jsonb default '[]'::jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_code text;
  v_target uuid;
  v_staff public.admin_staff%rowtype;
  v_code text;
  v_permission text;
  v_permissions text[] := array[]::text[];
  v_sensitive boolean := false;
  v_reports_to uuid;
  v_details jsonb;
  v_email text := lower(trim(coalesce(p_email,'')));
begin
  if v_actor is null
     or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.is_nexora_super_admin() then
    raise exception 'শুধু MFA-যাচাইকৃত Director এই কাজ করতে পারবেন।'
      using errcode='42501';
  end if;

  if p_action not in ('create','update','deactivate') then
    raise exception 'অবৈধ action।' using errcode='22023';
  end if;
  if v_email !~* '^[A-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
    raise exception 'সঠিক ইমেইল দিন।' using errcode='22023';
  end if;

  select admin_code into v_actor_code
  from public.admin_staff
  where user_id=v_actor and admin_level='super_admin' and is_active=true;

  select id into v_target
  from auth.users
  where lower(email)=v_email
  limit 1;

  if v_target is null then
    raise exception 'এই ইমেইলে Auth account পাওয়া যায়নি। প্রথমে নিরাপদ Invite পাঠাতে হবে।'
      using errcode='P0002';
  end if;
  if v_target=v_actor then
    raise exception 'Director নিজের অ্যাকাউন্টকে কর্মকর্তা হিসেবে পরিবর্তন করতে পারবেন না।'
      using errcode='42501';
  end if;

  if p_action in ('create','update') then
    if p_position_key not in ('managing_director','department_head','department_officer') then
      raise exception 'সঠিক পদ নির্বাচন করুন।' using errcode='22023';
    end if;
    if p_position_key='managing_director' then
      if p_department_key<>'managing_director' then
        raise exception 'MD-কে Managing Director Office-এ নিয়োগ করতে হবে।' using errcode='22023';
      end if;
    elsif p_department_key not in ('marketing','transport','accounts') then
      raise exception 'বিভাগীয় কর্মকর্তা বা প্রধানকে Marketing, Transport অথবা Accounts বিভাগে নিয়োগ করুন।'
        using errcode='22023';
    end if;
    if not exists (
      select 1 from public.admin_departments
      where department_key=p_department_key and is_assignable=true
    ) then
      raise exception 'নির্বাচিত বিভাগ সক্রিয় নয়।' using errcode='22023';
    end if;
    if jsonb_typeof(coalesce(p_permissions,'[]'::jsonb))<>'array' then
      raise exception 'Permission তালিকা array হতে হবে।' using errcode='22023';
    end if;

    for v_permission in
      select distinct jsonb_array_elements_text(coalesce(p_permissions,'[]'::jsonb))
    loop
      if not exists (
        select 1 from public.admin_permission_catalog c
        where c.permission_key=v_permission
          and (p_position_key='managing_director' or c.department_key=p_department_key)
      ) then
        raise exception 'এই পদ ও বিভাগের জন্য Permission বৈধ নয়: %',v_permission
          using errcode='22023';
      end if;
      select is_sensitive into v_sensitive
      from public.admin_permission_catalog
      where permission_key=v_permission;
      v_permissions := array_append(v_permissions,v_permission);
      if coalesce(v_sensitive,false) then
        v_sensitive := true;
      end if;
    end loop;
    if v_sensitive and length(btrim(coalesce(p_reason,'')))<5 then
      raise exception 'সংবেদনশীল Permission দেওয়ার কারণ অন্তত ৫ অক্ষরে লিখুন।'
        using errcode='22023';
    end if;
  end if;

  select * into v_staff
  from public.admin_staff
  where user_id=v_target
  for update;

  if p_action='create' then
    if found then
      raise exception 'এই অ্যাকাউন্টে Admin record আগে থেকেই আছে; Update ব্যবহার করুন।'
        using errcode='23505';
    end if;
    if not exists (
      select 1 from public.profiles
      where id=v_target and role='buyer' and account_status='active'
    ) then
      raise exception 'নতুন Invite account-এর সক্রিয় Buyer profile তৈরি হয়নি; নিয়োগ বন্ধ রাখা হয়েছে।'
        using errcode='23514';
    end if;
    if p_position_key='managing_director' and exists (
      select 1 from public.admin_staff
      where position_key='managing_director' and is_active=true
    ) then
      raise exception 'একজন সক্রিয় Managing Director ইতোমধ্যে নিয়োগপ্রাপ্ত।'
        using errcode='23505';
    end if;
    if p_position_key='department_head' and exists (
      select 1 from public.admin_staff
      where department_key=p_department_key and position_key='department_head' and is_active=true
    ) then
      raise exception 'এই বিভাগের একজন সক্রিয় বিভাগীয় প্রধান ইতোমধ্যে আছেন।'
        using errcode='23505';
    end if;

    if p_position_key='department_head' then
      select user_id into v_reports_to from public.admin_staff
      where position_key='managing_director' and is_active=true limit 1;
    elsif p_position_key='department_officer' then
      select user_id into v_reports_to from public.admin_staff
      where department_key=p_department_key and position_key='department_head' and is_active=true limit 1;
      if v_reports_to is null then
        select user_id into v_reports_to from public.admin_staff
        where position_key='managing_director' and is_active=true limit 1;
      end if;
    end if;

    perform pg_advisory_xact_lock(hashtext('nexora-officer-admin-code'));
    select 'NEX-ADM-' || lpad((coalesce(max(substring(admin_code from '[0-9]+$')::bigint),0)+1)::text,5,'0')
    into v_code
    from public.admin_staff
    where admin_code like 'NEX-ADM-%';

    update public.profiles set role='admin',updated_at=now() where id=v_target;
    insert into public.admin_staff(
      user_id,admin_code,admin_level,department_key,is_active,created_by,
      staff_email,position_key,reports_to_user_id
    ) values (
      v_target,v_code,'assistant_admin',p_department_key,true,v_actor,
      v_email,p_position_key,v_reports_to
    );
    insert into public.admin_permission_grants(admin_user_id,permission_key,is_allowed,granted_by)
    select v_target,unnest(v_permissions),true,v_actor;
    v_details:=jsonb_build_object(
      'email',v_email,'admin_code',v_code,'department_key',p_department_key,
      'position_key',p_position_key,'permissions',to_jsonb(v_permissions)
    );
  elsif p_action='update' then
    if not found or v_staff.admin_level<>'assistant_admin' then
      raise exception 'এই অ্যাকাউন্টটি পরিচালনাযোগ্য কর্মকর্তা নয়।' using errcode='42501';
    end if;
    if p_position_key='managing_director' and exists (
      select 1 from public.admin_staff
      where position_key='managing_director' and is_active=true and user_id<>v_target
    ) then
      raise exception 'একজন সক্রিয় Managing Director ইতোমধ্যে নিয়োগপ্রাপ্ত।'
        using errcode='23505';
    end if;
    if p_position_key='department_head' and exists (
      select 1 from public.admin_staff
      where department_key=p_department_key and position_key='department_head'
        and is_active=true and user_id<>v_target
    ) then
      raise exception 'এই বিভাগের একজন সক্রিয় বিভাগীয় প্রধান ইতোমধ্যে আছেন।'
        using errcode='23505';
    end if;
    if length(btrim(coalesce(p_reason,'')))<5 then
      raise exception 'পরিবর্তনের কারণ অন্তত ৫ অক্ষরে লিখুন।' using errcode='22023';
    end if;

    if p_position_key='department_head' then
      select user_id into v_reports_to from public.admin_staff
      where position_key='managing_director' and is_active=true limit 1;
    elsif p_position_key='department_officer' then
      select user_id into v_reports_to from public.admin_staff
      where department_key=p_department_key and position_key='department_head' and is_active=true limit 1;
      if v_reports_to is null then
        select user_id into v_reports_to from public.admin_staff
        where position_key='managing_director' and is_active=true limit 1;
      end if;
    end if;

    update public.admin_staff
    set department_key=p_department_key,position_key=p_position_key,
        staff_email=v_email,reports_to_user_id=v_reports_to,
        is_active=true,updated_at=now()
    where user_id=v_target;
    delete from public.admin_permission_grants where admin_user_id=v_target;
    insert into public.admin_permission_grants(admin_user_id,permission_key,is_allowed,granted_by)
    select v_target,unnest(v_permissions),true,v_actor;
    v_code:=v_staff.admin_code;
    v_details:=jsonb_build_object(
      'email',v_email,'admin_code',v_code,'department_key',p_department_key,
      'position_key',p_position_key,'permissions',to_jsonb(v_permissions),
      'previous_department',v_staff.department_key,'previous_position',v_staff.position_key
    );
  else
    if not found or v_staff.admin_level<>'assistant_admin' then
      raise exception 'এই অ্যাকাউন্টটি পরিচালনাযোগ্য কর্মকর্তা নয়।' using errcode='42501';
    end if;
    if length(btrim(coalesce(p_reason,'')))<5 then
      raise exception 'অ্যাকাউন্ট নিষ্ক্রিয় করার কারণ অন্তত ৫ অক্ষরে লিখুন।' using errcode='22023';
    end if;
    update public.admin_staff
    set is_active=false,updated_at=now()
    where user_id=v_target;
    delete from public.admin_permission_grants where admin_user_id=v_target;
    v_code:=v_staff.admin_code;
    v_details:=jsonb_build_object('email',v_email,'admin_code',v_code,'is_active',false);
  end if;

  insert into public.admin_audit_logs(
    actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details
  ) values (
    v_actor,v_actor_code,'officer.'||p_action,'admin_staff',v_target::text,
    nullif(btrim(coalesce(p_reason,'')),'Director Dashboard'),v_details
  );

  return jsonb_build_object('success',true,'admin_code',v_code,'action',p_action);
end;
$$;

revoke all on function private.manage_nexora_officer(text,text,text,text,jsonb,text) from public,anon;
grant execute on function private.manage_nexora_officer(text,text,text,text,jsonb,text) to authenticated;

create or replace function public.manage_nexora_officer(
  p_email text,
  p_action text,
  p_department_key text default null,
  p_position_key text default null,
  p_permissions jsonb default '[]'::jsonb,
  p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $rpc$
  select private.manage_nexora_officer(
    p_email,p_action,p_department_key,p_position_key,p_permissions,p_reason
  );
$rpc$;

revoke all on function public.manage_nexora_officer(text,text,text,text,jsonb,text) from public,anon;
grant execute on function public.manage_nexora_officer(text,text,text,text,jsonb,text) to authenticated;

commit;
