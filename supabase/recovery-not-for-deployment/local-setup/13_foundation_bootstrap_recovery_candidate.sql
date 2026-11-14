-- RECOVERY-ONLY FOUNDATION CANDIDATE.
-- New design based on the owner-approved Foundation spec and active frontend/migration contracts.
-- NOT historical SQL. NOT a Supabase migration. NOT deployable. Never apply to hosted projects.
-- Requires a fresh disposable Supabase local stack with 12_rls_auto_enable_recovery_candidate.sql installed first.

BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

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
 ('managing_director','Managing Director Office','দৈনন্দিন পরিচালনা ও বিভাগগুলোর সমন্বয়।',true),
 ('marketing','Marketing Department','Buyer ও Seller সংগ্রহ, প্রচার এবং ব্যবসা বৃদ্ধি।',true),
 ('transport','Transport Department','বাহ্যিক পরিবহন অংশীদার, যানবাহন ও পরিবহন কর্মী।',true),
 ('logistics','Logistics Department','ডেলিভারি পরিচালনা, fulfilment ও assignment।',true),
 ('product_business','Product & Business Department','পণ্য ও সেবা listing workflow।',true),
 ('trust_safety','Trust & Safety Department','ব্যবহারকারী, ব্যবসা ও পণ্যের moderation।',true),
 ('accounts','Accounts & Finance Department','আর্থিক রেকর্ড, হিসাব, refund ও settlement।',true);

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text CHECK (full_name IS NULL OR length(full_name) <= 150),
  role text NOT NULL CONSTRAINT profiles_role_check
    CHECK (role IN ('buyer','seller','porter','admin')),
  account_status text NOT NULL DEFAULT 'active'
    CHECK (account_status IN ('active','pending','suspended','rejected','disabled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX profiles_role_status_idx ON public.profiles(role,account_status);
CREATE INDEX profiles_updated_at_idx ON public.profiles(updated_at DESC);

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
CREATE UNIQUE INDEX one_pending_role_request_per_user
  ON public.role_requests(user_id) WHERE status='pending';
CREATE INDEX role_requests_review_queue_idx ON public.role_requests(status,created_at)
  WHERE status='pending';

CREATE TABLE public.profile_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  requested_full_name text NOT NULL
    CHECK (length(btrim(requested_full_name)) BETWEEN 1 AND 150),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  admin_note text,
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX profile_change_requests_review_queue_idx
  ON public.profile_change_requests(status,created_at) WHERE status='pending';

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
  ),
  CONSTRAINT admin_staff_department_required CHECK (
    (position_key='director' AND department_key='managing_director')
    OR (position_key<>'director' AND department_key IS NOT NULL)
  )
);
CREATE UNIQUE INDEX admin_staff_one_active_director_idx
  ON public.admin_staff(position_key) WHERE position_key='director' AND is_active;
CREATE UNIQUE INDEX admin_staff_one_active_md_idx
  ON public.admin_staff(position_key) WHERE position_key='managing_director' AND is_active;
CREATE UNIQUE INDEX admin_staff_one_active_department_head_idx
  ON public.admin_staff(department_key) WHERE position_key='department_head' AND is_active;
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

CREATE TABLE public.porter_account_reviews (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE RESTRICT,
  review_status text NOT NULL DEFAULT 'pending'
    CHECK (review_status IN ('pending','approved','rejected','suspended')),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  admin_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (length(coalesce(admin_note,'')) <= 1000)
);
CREATE INDEX porter_account_reviews_queue_idx
  ON public.porter_account_reviews(review_status,submitted_at)
  WHERE review_status='pending';

-- Only stable, confirmed permission contracts are seeded here. #34 adds its own keys.
INSERT INTO public.admin_permission_catalog
  (permission_key,department_key,permission_name,description,is_sensitive,is_active)
VALUES
 ('logistics.view','logistics','Delivery view','View authorized delivery operations.',false,true),
 ('logistics.assign','logistics','Delivery assignment','Assign eligible approved delivery resources.',true,true),
 ('services.edit','product_business','Service listing edit','Review and edit service listing changes.',true,true),
 ('users.view','trust_safety','User moderation view','View limited user moderation records.',true,false),
 ('users.suspend','trust_safety','User suspension','Suspend an account through an audited workflow.',true,false),
 ('users.restore','trust_safety','User restoration','Restore an account through an audited workflow.',true,false),
 ('users.cancel','trust_safety','User deactivation','Reversibly deactivate an account; never delete Auth identity.',true,false),
 ('businesses.view','trust_safety','Business moderation view','View limited business moderation records.',true,false),
 ('businesses.suspend','trust_safety','Business suspension','Suspend a business through an audited workflow.',true,false),
 ('products.view','trust_safety','Product moderation view','View limited product moderation records.',true,false),
 ('products.suspend','trust_safety','Product suspension','Suspend a listing through an audited workflow.',true,false),
 ('products.restore','trust_safety','Product restoration','Restore a listing through an audited workflow.',true,false),
 ('products.cancel','trust_safety','Product deactivation','Reversibly deactivate a listing through an audited workflow.',true,false)
ON CONFLICT (permission_key) DO NOTHING;

CREATE OR REPLACE FUNCTION private.is_nexora_super_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_staff AS staff
    JOIN public.profiles AS profile ON profile.id=staff.user_id
    WHERE staff.user_id=(SELECT auth.uid())
      AND staff.is_active
      AND staff.position_key='director'
      AND staff.admin_level='super_admin'
      AND staff.department_key='managing_director'
      AND profile.role='admin'
      AND profile.account_status='active'
      AND (SELECT auth.jwt()->>'aal')='aal2'
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_nexora_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT private.is_nexora_super_admin();
$function$;

CREATE OR REPLACE FUNCTION public.is_nexora_super_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT private.is_nexora_super_admin();
$function$;

CREATE OR REPLACE FUNCTION private.has_nexora_permission(p_permission text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT CASE WHEN p_permission IS NULL OR btrim(p_permission)='' THEN false ELSE EXISTS (
    SELECT 1
    FROM public.admin_staff AS staff
    JOIN public.profiles AS profile ON profile.id=staff.user_id
    JOIN public.admin_permission_catalog AS permission
      ON permission.permission_key=p_permission AND permission.is_active
    WHERE staff.user_id=(SELECT auth.uid())
      AND staff.is_active
      AND profile.role='admin'
      AND profile.account_status='active'
      AND (SELECT auth.jwt()->>'aal')='aal2'
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_permission_grants AS denied
        WHERE denied.admin_user_id=staff.user_id
          AND denied.permission_key=permission.permission_key
          AND denied.is_allowed=false
      )
      AND (
        (staff.position_key='director' AND staff.admin_level='super_admin'
          AND staff.department_key='managing_director')
        OR (
          staff.position_key<>'director'
          AND staff.department_key=permission.department_key
          AND EXISTS (
            SELECT 1 FROM public.admin_permission_grants AS granted
            WHERE granted.admin_user_id=staff.user_id
              AND granted.permission_key=permission.permission_key
              AND granted.is_allowed=true
          )
        )
      )
  ) END;
$function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_role text;
  v_full_name text;
  v_provider text;
  v_account_status text := 'active';
BEGIN
  v_provider := lower(coalesce(new.raw_app_meta_data ->> 'provider',''));
  IF v_provider NOT IN ('','email','phone') THEN
    v_role := 'buyer';
  ELSE
    v_role := lower(trim(coalesce(new.raw_user_meta_data ->> 'role','buyer')));
  END IF;
  IF v_role NOT IN ('buyer','seller','porter') THEN
    RAISE EXCEPTION 'Invalid public registration role';
  END IF;
  v_full_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name',new.raw_user_meta_data ->> 'name')),'');
  IF v_full_name IS NOT NULL AND length(v_full_name)>150 THEN
    RAISE EXCEPTION 'Full name is too long';
  END IF;
  IF v_role='porter' THEN v_account_status:='pending'; END IF;
  INSERT INTO public.profiles(id,full_name,role,account_status)
  VALUES(new.id,v_full_name,v_role,v_account_status)
  ON CONFLICT(id) DO NOTHING;
  IF v_role='porter' THEN
    INSERT INTO public.porter_account_reviews(user_id,review_status)
    VALUES(new.id,'pending') ON CONFLICT(user_id) DO NOTHING;
  END IF;
  RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.review_role_request(request_id uuid, decision text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_request public.role_requests%ROWTYPE;
  v_profile_role text;
  v_profile_status text;
BEGIN
  IF v_actor IS NULL OR NOT private.is_nexora_super_admin() THEN
    RAISE EXCEPTION 'Director MFA required' USING errcode='42501';
  END IF;
  IF decision NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'Unsupported decision' USING errcode='22023';
  END IF;
  SELECT * INTO v_request
  FROM public.role_requests
  WHERE id=request_id
  FOR UPDATE;
  IF NOT FOUND OR v_request.status<>'pending' OR v_request.requested_role<>'seller' THEN
    RAISE EXCEPTION 'Pending Seller request not found' USING errcode='P0002';
  END IF;
  SELECT role,account_status INTO v_profile_role,v_profile_status
  FROM public.profiles WHERE id=v_request.user_id FOR UPDATE;
  IF v_profile_role IS DISTINCT FROM 'buyer' OR v_profile_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Buyer can be approved as Seller' USING errcode='23514';
  END IF;
  IF decision='approved' THEN
    UPDATE public.profiles SET role='seller',updated_at=now() WHERE id=v_request.user_id;
  END IF;
  UPDATE public.role_requests
  SET status=decision,reviewed_by=v_actor,reviewed_at=now(),updated_at=now()
  WHERE id=request_id;
  INSERT INTO public.admin_audit_logs(actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details)
  SELECT v_actor,staff.admin_code,'role_request.'||decision,'role_request',request_id::text,
         'Director review',jsonb_build_object('requested_role','seller','decision',decision,'applicant_id',v_request.user_id)
  FROM public.admin_staff AS staff WHERE staff.user_id=v_actor AND staff.is_active;
  RETURN jsonb_build_object('request_id',request_id,'decision',decision,'user_id',v_request.user_id);
END;
$function$;

-- One Auth trigger only. Never replace/remove unrelated Supabase-managed triggers.
DO $trigger$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_catalog.pg_trigger
  WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal
    AND tgfoid='public.handle_new_user()'::regprocedure;
  IF v_count=0 THEN
    CREATE TRIGGER nexora_handle_new_user
      AFTER INSERT ON auth.users
      FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
  ELSIF v_count>1 THEN
    RAISE EXCEPTION 'More than one Auth trigger invokes public.handle_new_user()';
  END IF;
END;
$trigger$;

-- Fail-closed RLS: users see only their own profile/request; governance data is Director-only.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_permission_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_permission_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.porter_account_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_owner_select ON public.profiles
  FOR SELECT TO authenticated USING (id=(SELECT auth.uid()));

CREATE POLICY role_requests_owner_select ON public.role_requests
  FOR SELECT TO authenticated USING (user_id=(SELECT auth.uid()));
CREATE POLICY role_requests_director_select ON public.role_requests
  FOR SELECT TO authenticated USING (public.is_nexora_admin());
CREATE POLICY role_requests_owner_insert ON public.role_requests
  FOR INSERT TO authenticated WITH CHECK (
    user_id=(SELECT auth.uid()) AND requested_role='seller' AND status='pending'
    AND reviewed_by IS NULL AND reviewed_at IS NULL AND admin_note IS NULL
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=(SELECT auth.uid())
      AND p.role='buyer' AND p.account_status='active')
  );

CREATE POLICY profile_change_owner_select ON public.profile_change_requests
  FOR SELECT TO authenticated USING (user_id=(SELECT auth.uid()));
CREATE POLICY profile_change_director_select ON public.profile_change_requests
  FOR SELECT TO authenticated USING (public.is_nexora_admin());
CREATE POLICY profile_change_owner_insert ON public.profile_change_requests
  FOR INSERT TO authenticated WITH CHECK (
    user_id=(SELECT auth.uid()) AND status='pending'
    AND reviewed_by IS NULL AND reviewed_at IS NULL AND admin_note IS NULL
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=(SELECT auth.uid())
      AND p.account_status='active')
  );

CREATE POLICY admin_departments_director_select ON public.admin_departments
  FOR SELECT TO authenticated USING (public.is_nexora_admin());
CREATE POLICY admin_staff_director_select ON public.admin_staff
  FOR SELECT TO authenticated USING (public.is_nexora_admin());
CREATE POLICY admin_catalog_director_select ON public.admin_permission_catalog
  FOR SELECT TO authenticated USING (public.is_nexora_admin());
CREATE POLICY admin_grants_director_select ON public.admin_permission_grants
  FOR SELECT TO authenticated USING (public.is_nexora_admin());
CREATE POLICY admin_audit_director_select ON public.admin_audit_logs
  FOR SELECT TO authenticated USING (public.is_nexora_admin());
CREATE POLICY porter_review_owner_select ON public.porter_account_reviews
  FOR SELECT TO authenticated USING (user_id=(SELECT auth.uid()));
CREATE POLICY porter_review_authorized_select ON public.porter_account_reviews
  FOR SELECT TO authenticated USING (private.has_nexora_permission('logistics.assign'));

REVOKE ALL ON public.profiles,public.role_requests,public.profile_change_requests,
  public.admin_departments,public.admin_staff,public.admin_permission_catalog,
  public.admin_permission_grants,public.admin_audit_logs,public.porter_account_reviews
FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT,INSERT ON public.role_requests TO authenticated;
GRANT SELECT,INSERT ON public.profile_change_requests TO authenticated;
GRANT SELECT ON public.admin_departments,public.admin_staff,public.admin_permission_catalog,
  public.admin_permission_grants,public.admin_audit_logs,public.porter_account_reviews TO authenticated;

ALTER FUNCTION private.is_nexora_super_admin() OWNER TO postgres;
ALTER FUNCTION public.is_nexora_admin() OWNER TO postgres;
ALTER FUNCTION public.is_nexora_super_admin() OWNER TO postgres;
ALTER FUNCTION private.has_nexora_permission(text) OWNER TO postgres;
ALTER FUNCTION public.handle_new_user() OWNER TO postgres;
ALTER FUNCTION public.review_role_request(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.is_nexora_super_admin() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.is_nexora_admin() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.is_nexora_super_admin() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.has_nexora_permission(text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.review_role_request(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.is_nexora_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_nexora_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_nexora_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_nexora_permission(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_role_request(uuid,text) TO authenticated;

COMMIT;
