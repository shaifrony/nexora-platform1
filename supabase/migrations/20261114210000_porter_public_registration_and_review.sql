-- NEXORA public Porter registration and approval-gated account access.
-- Development branch staging only. Do not apply to hosted DB without explicit approval.
begin;

-- Public registration supports Buyer, Seller and Porter only. Admin identities remain
-- provisioned exclusively through the protected administration workflow.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role = any (array['buyer'::text,'seller'::text,'porter'::text,'admin'::text]));

alter table public.profiles drop constraint if exists profiles_market_categories_check;
alter table public.profiles add constraint profiles_market_categories_check check (
  (role = 'buyer' and buyer_category is not null
    and buyer_category in ('wholesale','retail') and seller_categories = '{}'::text[])
  or
  (role = 'seller' and buyer_category is null
    and cardinality(seller_categories) between 1 and 2
    and seller_categories <@ array['wholesale','retail']::text[])
  or
  (role in ('porter','admin') and buyer_category is null
    and seller_categories = '{}'::text[])
);

-- A separate review record preserves the difference between rejected and suspended
-- while profiles.account_status gates every authenticated workspace.
create table if not exists public.porter_account_reviews (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  review_status text not null default 'pending'
    check (review_status in ('pending','approved','rejected','suspended')),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(coalesce(admin_note,'')) <= 1000)
);
create index if not exists porter_account_reviews_queue_idx
  on public.porter_account_reviews(review_status,submitted_at)
  where review_status='pending';

alter table public.porter_account_reviews enable row level security;
revoke all on public.porter_account_reviews from public,anon,authenticated;

-- Replace the Auth trigger so a client-supplied role can only be Buyer, Seller or Porter.
-- OAuth registrations remain Buyer by default; no metadata can create an Admin account.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role text;
  v_full_name text;
  v_provider text;
  v_buyer_category text;
  v_seller_categories text[];
  v_account_status text;
begin
  v_provider := lower(coalesce(new.app_metadata ->> 'provider', ''));

  if v_provider in ('google','facebook') then
    v_role := 'buyer';
  else
    v_role := lower(trim(coalesce(new.raw_user_meta_data ->> 'role','buyer')));
  end if;

  if v_role not in ('buyer','seller','porter') then
    raise exception 'Invalid public registration role';
  end if;

  v_full_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')), '');
  if v_full_name is not null and length(v_full_name) > 150 then
    raise exception 'Full name is too long';
  end if;

  if v_role = 'buyer' then
    v_buyer_category := lower(trim(coalesce(new.raw_user_meta_data ->> 'buyer_category','wholesale')));
    if v_buyer_category not in ('wholesale','retail') then
      raise exception 'Invalid Buyer market category';
    end if;
    v_seller_categories := '{}'::text[];
    v_account_status := 'active';
  elsif v_role = 'seller' then
    v_buyer_category := null;
    if jsonb_typeof(new.raw_user_meta_data -> 'seller_categories') = 'array' then
      select coalesce(array_agg(category order by category), array[]::text[])
      into v_seller_categories
      from (
        select distinct jsonb_array_elements_text(new.raw_user_meta_data -> 'seller_categories') as category
      ) selected
      where category in ('wholesale','retail');
    else
      v_seller_categories := array['wholesale']::text[];
    end if;
    if coalesce(cardinality(v_seller_categories),0) = 0 then
      raise exception 'Select at least one Seller market category';
    end if;
    v_account_status := 'active';
  else
    v_buyer_category := null;
    v_seller_categories := '{}'::text[];
    v_account_status := 'pending';
  end if;

  insert into public.profiles (id,full_name,role,account_status,buyer_category,seller_categories)
  values (new.id,v_full_name,v_role,v_account_status,v_buyer_category,v_seller_categories)
  on conflict (id) do nothing;

  if v_role = 'porter' then
    insert into public.porter_account_reviews(user_id,review_status)
    values (new.id,'pending')
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$function$;

-- A Porter must also be an active account before applying to become an individual
-- transport provider. Provider/vehicle approval remains a separate operational check.
drop policy if exists transport_provider_owner_insert on public.transport_providers;
create policy transport_provider_owner_insert on public.transport_providers for insert to authenticated
with check(owner_user_id=(select auth.uid()) and application_status='pending'
 and admin_note is null and reviewed_by is null and reviewed_at is null
 and exists(select 1 from public.profiles p where p.id=(select auth.uid())
 and p.role in ('buyer','seller','porter') and p.account_status='active'));

create or replace function private.review_porter_account(
  p_user_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_admin_code text;
  v_old_status text;
  v_new_status text;
  v_old_account_status text;
begin
  if v_actor is null
     or (select auth.jwt()->>'aal') is distinct from 'aal2'
     or not private.has_nexora_permission('logistics.assign') then
    raise exception 'Active Admin MFA and logistics.assign permission required'
      using errcode='42501';
  end if;

  if p_action is null or p_action not in ('approve','reject','suspend') then
    raise exception 'Unsupported Porter review action' using errcode='22023';
  end if;
  if p_action in ('reject','suspend')
     and length(btrim(coalesce(p_reason,''))) < 5 then
    raise exception 'A review reason of at least 5 characters is required'
      using errcode='22023';
  end if;
  if length(coalesce(p_reason,'')) > 1000 then
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

  select r.review_status,p.account_status
    into v_old_status,v_old_account_status
  from public.porter_account_reviews r
  join public.profiles p on p.id=r.user_id
  where r.user_id=p_user_id and p.role='porter'
  for update of r,p;

  if not found then
    raise exception 'Pending Porter account not found' using errcode='P0002';
  end if;

  if p_action='approve' then
    if v_old_status not in ('pending','rejected','suspended') then
      raise exception 'Only pending/rejected/suspended Porter accounts can be approved'
        using errcode='22023';
    end if;
    v_new_status := 'approved';
  elsif p_action='reject' then
    if v_old_status<>'pending' then
      raise exception 'Only pending Porter accounts can be rejected'
        using errcode='22023';
    end if;
    v_new_status := 'rejected';
  else
    if v_old_status<>'approved' or v_old_account_status<>'active' then
      raise exception 'Only an approved active Porter can be suspended'
        using errcode='22023';
    end if;
    v_new_status := 'suspended';
  end if;

  update public.porter_account_reviews
  set review_status=v_new_status,
      admin_note=nullif(btrim(coalesce(p_reason,'')),''),
      reviewed_by=v_actor,reviewed_at=now(),updated_at=now()
  where user_id=p_user_id;

  update public.profiles
  set account_status=case when p_action='approve' then 'active' else 'suspended' end,
      updated_at=now()
  where id=p_user_id and role='porter';

  insert into public.admin_audit_logs(
    actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details
  ) values (
    v_actor,v_admin_code,'porter_account.'||p_action,
    'porter_account',p_user_id::text,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'previous_review_status',v_old_status,
      'new_review_status',v_new_status,
      'previous_account_status',v_old_account_status,
      'new_account_status',case when p_action='approve' then 'active' else 'suspended' end
    )
  );

  return jsonb_build_object(
    'user_id',p_user_id,'previous_status',v_old_status,
    'review_status',v_new_status,
    'account_status',case when p_action='approve' then 'active' else 'suspended' end
  );
end;
$$;

revoke all on function private.review_porter_account(uuid,text,text) from public,anon;
grant execute on function private.review_porter_account(uuid,text,text) to authenticated;

create or replace function public.review_porter_account(
  p_user_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $rpc$
  select private.review_porter_account(p_user_id,p_action,p_reason);
$rpc$;

revoke all on function public.review_porter_account(uuid,text,text) from public,anon;
grant execute on function public.review_porter_account(uuid,text,text) to authenticated;

comment on table public.porter_account_reviews is
  'Admin-reviewed public Porter registrations; approval activates the profile, rejection/suspension blocks all workspaces.';
commit;
