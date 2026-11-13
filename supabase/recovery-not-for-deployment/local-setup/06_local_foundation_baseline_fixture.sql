-- NEXORA NEW LOCAL FOUNDATION BASELINE FIXTURE
-- NOT ORIGINAL / NOT RECOVERED / NOT DEPLOYABLE.
-- SAFE TARGET: local PostgreSQL database named nexora_test ONLY.
-- This is a fresh design fixture, not a Supabase migration.
-- Never move to supabase/migrations/ and never execute against hosted Supabase.
-- Android PostgreSQL does not emulate Supabase Auth, PostgREST, Realtime, Storage API or MFA.

\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %', current_database();
  END IF;
  IF to_regclass('auth.users') IS NULL
     OR to_regprocedure('auth.uid()') IS NULL
     OR to_regprocedure('auth.jwt()') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: run 00_bootstrap_supabase_compat.sql first';
  END IF;
  IF to_regclass('public.profiles') IS NOT NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: public.profiles already exists; inspect before applying this fixture';
  END IF;
END
$guard$;

BEGIN;

-- Minimal organizational lookup tables.
CREATE TABLE public.admin_departments (
  department_key text PRIMARY KEY,
  department_name text NOT NULL,
  description text,
  is_assignable boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.admin_departments(department_key,department_name,description,is_assignable)
VALUES
 ('managing_director','Managing Director Office','Executive operations coordination.',true),
 ('marketing','Marketing Department','Buyer/Seller acquisition, campaigns and growth.',true),
 ('transport','Transport & Logistics Department','Provider review, delivery operations and tracking.',true),
 ('accounts','Accounts & Finance Department','Financial records, reconciliation and settlements.',true)
ON CONFLICT (department_key) DO NOTHING;

-- One internal profile per Supabase Auth identity.
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text,
  role text NOT NULL CHECK (role IN ('buyer','seller','porter','admin')),
  account_status text NOT NULL DEFAULT 'active'
    CHECK (account_status IN ('active','pending','suspended','rejected','disabled')),
  buyer_category text,
  seller_categories text[] NOT NULL DEFAULT '{}'::text[],
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_market_categories_check CHECK (
    buyer_category IS NULL AND seller_categories='{}'::text[]
  )
);

CREATE INDEX profiles_role_status_idx ON public.profiles(role,account_status);
CREATE INDEX profiles_updated_at_idx ON public.profiles(updated_at DESC);

-- Buyer -> Seller request only. Porter is a public signup role, not a role escalation.
CREATE TABLE public.role_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  requested_role text NOT NULL CHECK (requested_role='seller'),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  admin_note text,
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX role_requests_user_status_idx ON public.role_requests(user_id,status);
CREATE INDEX role_requests_review_queue_idx ON public.role_requests(status,created_at)
  WHERE status='pending';

CREATE TABLE public.profile_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  requested_full_name text NOT NULL CHECK (length(btrim(requested_full_name)) BETWEEN 1 AND 150),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  admin_note text,
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX profile_change_requests_user_status_idx
  ON public.profile_change_requests(user_id,status);
CREATE INDEX profile_change_requests_review_queue_idx
  ON public.profile_change_requests(status,created_at)
  WHERE status='pending';

CREATE TABLE public.admin_staff (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE RESTRICT,
  admin_code text NOT NULL UNIQUE,
  admin_level text NOT NULL CHECK (admin_level IN ('super_admin','assistant_admin')),
  department_key text REFERENCES public.admin_departments(department_key) ON DELETE RESTRICT,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  staff_email text,
  position_key text NOT NULL DEFAULT 'department_officer'
    CHECK (position_key IN ('director','managing_director','department_head','department_officer')),
  reports_to_user_id uuid REFERENCES public.admin_staff(user_id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_staff_director_level_check CHECK (
    (position_key='director' AND admin_level='super_admin')
    OR (position_key<>'director' AND admin_level='assistant_admin')
  )
);
CREATE UNIQUE INDEX admin_staff_one_active_director_idx
  ON public.admin_staff(position_key)
  WHERE position_key='director' AND is_active=true;
CREATE UNIQUE INDEX admin_staff_one_active_md_idx
  ON public.admin_staff(position_key)
  WHERE position_key='managing_director' AND is_active=true;
CREATE UNIQUE INDEX admin_staff_one_active_department_head_idx
  ON public.admin_staff(department_key)
  WHERE position_key='department_head' AND is_active=true;
CREATE INDEX admin_staff_department_position_idx
  ON public.admin_staff(department_key,position_key,is_active);

CREATE TABLE public.admin_permission_catalog (
  permission_key text PRIMARY KEY,
  department_key text NOT NULL REFERENCES public.admin_departments(department_key) ON DELETE RESTRICT,
  permission_name text NOT NULL,
  description text,
  is_sensitive boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.admin_permission_grants (
  admin_user_id uuid NOT NULL REFERENCES public.admin_staff(user_id) ON DELETE CASCADE,
  permission_key text NOT NULL REFERENCES public.admin_permission_catalog(permission_key) ON DELETE RESTRICT,
  is_allowed boolean NOT NULL DEFAULT true,
  granted_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(admin_user_id,permission_key)
);

CREATE TABLE public.admin_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  actor_admin_code text,
  action_key text NOT NULL,
  target_type text NOT NULL,
  target_id text,
  reason text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_audit_logs_actor_created_idx
  ON public.admin_audit_logs(actor_user_id,created_at DESC);
CREATE INDEX admin_audit_logs_target_idx
  ON public.admin_audit_logs(target_type,target_id,created_at DESC);

-- Separate Porter account review; provider and vehicle reviews are later feature tables.
CREATE TABLE public.porter_account_reviews (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE RESTRICT,
  review_status text NOT NULL DEFAULT 'pending'
    CHECK (review_status IN ('pending','approved','rejected','suspended')),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  admin_note text CHECK (length(coalesce(admin_note,''))<=1000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX porter_account_reviews_queue_idx
  ON public.porter_account_reviews(review_status,submitted_at)
  WHERE review_status='pending';

-- Initial permission catalogue: capability keys are explicit, never implied by job title.
INSERT INTO public.admin_permission_catalog
(permission_key,department_key,permission_name,description,is_sensitive)
VALUES
 ('organization.view','managing_director','Organization overview','View approved organization structure.',false),
 ('organization.structure.manage','managing_director','Organization structure','Create/retire departments and alter structure.',true),
 ('organization.executives.manage','managing_director','Executive appointments','Appoint/remove MD and department heads.',true),
 ('users.view_limited','managing_director','Limited user identity','View only minimum user identity data needed for authorized support.',true),
 ('users.role_requests.review','managing_director','Role request review','Review Buyer-to-Seller role requests.',true),
 ('users.profile_changes.review','managing_director','Profile change review','Review profile change requests.',true),
 ('operations.view','managing_director','Operations overview','View cross-department operations.',false),
 ('operations.coordinate','managing_director','Operations coordination','Coordinate work within approved policy.',true),
 ('marketing.leads.view','marketing','Marketing leads','View acquisition leads.',false),
 ('marketing.leads.manage','marketing','Marketing acquisition','Manage outreach and acquisition pipeline.',true),
 ('marketing.campaigns.manage','marketing','Campaign management','Create and manage approved campaigns.',true),
 ('transport.partners.view','transport','Transport partners','View provider and partner records.',false),
 ('transport.partners.manage','transport','Transport partners management','Manage partner onboarding workflow.',true),
 ('transport.providers.review','transport','Provider review','Review provider applications.',true),
 ('transport.vehicles.review','transport','Vehicle review','Review vehicle submissions.',true),
 ('logistics.porter_accounts.review','transport','Porter account review','Review public Porter account applications.',true),
 ('logistics.view','transport','Delivery view','View authorized delivery operations.',false),
 ('logistics.assign','transport','Delivery assignment','Assign eligible approved delivery resources.',true),
 ('logistics.tracking.update','transport','Tracking update','Update authorized tracking events.',true),
 ('finance.view','accounts','Finance overview','View authorized finance summaries.',false),
 ('finance.transactions.view','accounts','Transactions view','View authorized transactions.',false),
 ('finance.transactions.manage','accounts','Transactions management','Manage permitted finance records.',true),
 ('finance.refunds.request','accounts','Refund request','Prepare refund requests.',true),
 ('finance.refunds.approve','accounts','Refund approval','Approve another person''s eligible refund request.',true),
 ('finance.payouts.manage','accounts','Payout management','Prepare and manage payout workflow.',true),
 ('audit.view','managing_director','Audit view','View audit records within authorized scope.',true)
ON CONFLICT (permission_key) DO NOTHING;

-- Authorization helpers. Director receives capability checks, but structural RPCs
-- must separately require Director + AAL2 and must always write audit records.
CREATE OR REPLACE FUNCTION private.is_nexora_super_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=''
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_staff s
    JOIN public.profiles p ON p.id=s.user_id
    WHERE s.user_id=auth.uid()
      AND s.is_active=true
      AND s.position_key='director'
      AND s.admin_level='super_admin'
      AND p.role='admin'
      AND p.account_status='active'
  );
$fn$;

CREATE OR REPLACE FUNCTION public.is_nexora_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=''
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_staff s
    JOIN public.profiles p ON p.id=s.user_id
    WHERE s.user_id=auth.uid()
      AND s.is_active=true
      AND p.role='admin'
      AND p.account_status='active'
  );
$fn$;

CREATE OR REPLACE FUNCTION private.has_nexora_permission(p_permission text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=''
AS $fn$
  SELECT private.is_nexora_super_admin()
    OR EXISTS (
      SELECT 1
      FROM public.admin_staff s
      JOIN public.profiles p ON p.id=s.user_id
      JOIN public.admin_permission_grants g ON g.admin_user_id=s.user_id
      JOIN public.admin_permission_catalog c ON c.permission_key=g.permission_key
      WHERE s.user_id=auth.uid()
        AND s.is_active=true
        AND p.role='admin'
        AND p.account_status='active'
        AND g.permission_key=p_permission
        AND g.is_allowed=true
        AND c.is_active=true
        AND (c.department_key=s.department_key OR s.position_key='managing_director')
        AND NOT (
          s.position_key='managing_director'
          AND p_permission IN ('organization.structure.manage','organization.executives.manage')
        )
    );
$fn$;

-- Prevent users from changing authorization and review-controlled profile fields.
CREATE OR REPLACE FUNCTION private.protect_profile_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path=''
AS $fn$
BEGIN
  IF auth.uid()=OLD.id THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.role IS DISTINCT FROM OLD.role
       OR NEW.account_status IS DISTINCT FROM OLD.account_status
       OR NEW.buyer_category IS DISTINCT FROM OLD.buyer_category
       OR NEW.seller_categories IS DISTINCT FROM OLD.seller_categories
       OR NEW.full_name IS DISTINCT FROM OLD.full_name THEN
      RAISE EXCEPTION 'Protected profile fields require an authorized server-side workflow'
        USING ERRCODE='42501';
    END IF;
  END IF;
  NEW.updated_at:=now();
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER protect_profile_updates
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION private.protect_profile_updates();

-- Local fixture Auth trigger. This is not the real Supabase Auth lifecycle.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $fn$
DECLARE
  v_role text;
  v_name text;
  v_provider text;
  v_status text := 'active';
BEGIN
  v_provider:=lower(coalesce(NEW.raw_app_meta_data->>'provider',''));
  -- Every non-email/non-phone identity provider is Buyer-only.
  -- Email/phone signup may request only Buyer, Seller or Porter.
  IF v_provider NOT IN ('','email','phone') THEN
    v_role:='buyer';
  ELSE
    v_role:=lower(trim(coalesce(NEW.raw_user_meta_data->>'role','buyer')));
  END IF;

  IF v_role NOT IN ('buyer','seller','porter') THEN
    RAISE EXCEPTION 'Public signup role must be buyer, seller or porter';
  END IF;

  v_name:=nullif(btrim(coalesce(
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'name',
    ''
  )),'');
  IF v_name IS NOT NULL AND length(v_name)>150 THEN
    RAISE EXCEPTION 'Full name is too long';
  END IF;

  IF v_role='porter' THEN v_status:='pending'; END IF;

  INSERT INTO public.profiles(id,full_name,role,account_status,buyer_category,seller_categories)
  VALUES(NEW.id,v_name,v_role,v_status,NULL,'{}'::text[])
  ON CONFLICT(id) DO NOTHING;

  IF v_role='porter' THEN
    INSERT INTO public.porter_account_reviews(user_id,review_status)
    VALUES(NEW.id,'pending')
    ON CONFLICT(user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$fn$;

-- Trigger functions are not client RPCs; remove PostgreSQL's default PUBLIC EXECUTE grant.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;

DO $trigger$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname='nexora_local_auth_user_created'
      AND tgrelid='auth.users'::regclass
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER nexora_local_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
  END IF;
END
$trigger$;

-- Enable RLS on every public foundation table.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_permission_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_permission_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.porter_account_reviews ENABLE ROW LEVEL SECURITY;

-- Narrow grants; row policies provide the second authorization layer.
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT SELECT ON public.profiles,public.role_requests,public.profile_change_requests,
  public.admin_staff,public.admin_departments,public.admin_permission_catalog,
  public.admin_permission_grants,public.admin_audit_logs,public.porter_account_reviews
TO authenticated;
GRANT INSERT ON public.role_requests,public.profile_change_requests TO authenticated;

CREATE POLICY profiles_owner_read ON public.profiles
FOR SELECT TO authenticated USING(id=(SELECT auth.uid()));
CREATE POLICY profiles_limited_admin_read ON public.profiles
FOR SELECT TO authenticated USING(private.has_nexora_permission('users.view_limited'));

CREATE POLICY role_requests_owner_read ON public.role_requests
FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
CREATE POLICY role_requests_owner_insert ON public.role_requests
FOR INSERT TO authenticated WITH CHECK(
  user_id=(SELECT auth.uid()) AND requested_role='seller' AND status='pending'
  AND reviewed_by IS NULL AND reviewed_at IS NULL AND admin_note IS NULL
);
CREATE POLICY role_requests_reviewer_read ON public.role_requests
FOR SELECT TO authenticated USING(private.has_nexora_permission('users.role_requests.review'));
CREATE POLICY role_requests_reviewer_update ON public.role_requests
FOR UPDATE TO authenticated
USING(private.has_nexora_permission('users.role_requests.review'))
WITH CHECK(private.has_nexora_permission('users.role_requests.review'));

CREATE POLICY profile_change_owner_read ON public.profile_change_requests
FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
CREATE POLICY profile_change_owner_insert ON public.profile_change_requests
FOR INSERT TO authenticated WITH CHECK(
  user_id=(SELECT auth.uid()) AND status='pending'
  AND reviewed_by IS NULL AND reviewed_at IS NULL AND admin_note IS NULL
);
CREATE POLICY profile_change_reviewer_read ON public.profile_change_requests
FOR SELECT TO authenticated USING(private.has_nexora_permission('users.profile_changes.review'));
CREATE POLICY profile_change_reviewer_update ON public.profile_change_requests
FOR UPDATE TO authenticated
USING(private.has_nexora_permission('users.profile_changes.review'))
WITH CHECK(private.has_nexora_permission('users.profile_changes.review'));

CREATE POLICY admin_staff_self_read ON public.admin_staff
FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
CREATE POLICY admin_staff_director_read ON public.admin_staff
FOR SELECT TO authenticated USING(private.is_nexora_super_admin());
CREATE POLICY admin_departments_director_read ON public.admin_departments
FOR SELECT TO authenticated USING(private.is_nexora_super_admin());
CREATE POLICY admin_catalog_director_read ON public.admin_permission_catalog
FOR SELECT TO authenticated USING(private.is_nexora_super_admin());
CREATE POLICY admin_grants_self_read ON public.admin_permission_grants
FOR SELECT TO authenticated USING(admin_user_id=(SELECT auth.uid()));
CREATE POLICY admin_grants_director_read ON public.admin_permission_grants
FOR SELECT TO authenticated USING(private.is_nexora_super_admin());
CREATE POLICY admin_audit_read ON public.admin_audit_logs
FOR SELECT TO authenticated USING(private.has_nexora_permission('audit.view'));

CREATE POLICY porter_review_owner_read ON public.porter_account_reviews
FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
CREATE POLICY porter_review_admin_read ON public.porter_account_reviews
FOR SELECT TO authenticated USING(private.has_nexora_permission('logistics.porter_accounts.review'));

-- No client UPDATE/DELETE on profiles, Admin structure, grants or audit history.
REVOKE INSERT,UPDATE,DELETE ON public.profiles,public.admin_staff,public.admin_departments,
  public.admin_permission_catalog,public.admin_permission_grants,public.admin_audit_logs,
  public.porter_account_reviews FROM anon,authenticated;
REVOKE UPDATE,DELETE ON public.role_requests,public.profile_change_requests FROM anon,authenticated;

REVOKE ALL ON FUNCTION public.is_nexora_admin() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.is_nexora_super_admin() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.has_nexora_permission(text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.protect_profile_updates() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.is_nexora_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_nexora_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_nexora_permission(text) TO authenticated;

DO $verify$
DECLARE
  missing text[];
BEGIN
  SELECT array_agg(x) INTO missing
  FROM (VALUES
    ('public.profiles'),('public.role_requests'),('public.profile_change_requests'),
    ('public.admin_staff'),('public.admin_departments'),('public.admin_permission_catalog'),
    ('public.admin_permission_grants'),('public.admin_audit_logs'),
    ('public.porter_account_reviews'),('public.is_nexora_admin()'),
    ('private.has_nexora_permission(text)'),('private.is_nexora_super_admin()'),
    ('public.handle_new_user()')
  ) AS required(x)
  WHERE CASE
    WHEN x LIKE '%()' OR x LIKE '%(text)' THEN to_regprocedure(x) IS NULL
    ELSE to_regclass(x) IS NULL
  END;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'Foundation fixture verification failed; missing: %',array_to_string(missing,', ');
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname IN ('profiles','role_requests','profile_change_requests',
        'admin_staff','admin_departments','admin_permission_catalog',
        'admin_permission_grants','admin_audit_logs','porter_account_reviews')
      AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'RLS is not enabled on every foundation table';
  END IF;
END
$verify$;

COMMIT;

\echo '=== LOCAL FOUNDATION FIXTURE CREATED ==='
\echo 'This is a new local-only reconstruction, not original schema and not deployable.'
\echo 'Do not replay active migrations or recovery drafts on top of it.';
