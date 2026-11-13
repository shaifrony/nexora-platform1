-- NEXORA LOCAL-ONLY REVIEW RPC PROTOTYPE
-- Public PostgREST wrappers are SECURITY INVOKER; privileged cores stay in private schema.
-- SAFE TARGET: Android/Termux PostgreSQL database nexora_test ONLY.
-- NOT A MIGRATION. NEVER RUN AGAINST HOSTED SUPABASE OR PRODUCTION.
-- This creates local prototype RPC wrappers/cores and grants only.
-- Hosted deployment must keep schema 'private' out of PostgREST exposed schemas.
-- It does not alter existing rows, policies, table grants, owners, or RLS settings.
\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %', current_database();
  END IF;

  IF to_regclass('public.profiles') IS NULL
     OR to_regclass('public.role_requests') IS NULL
     OR to_regclass('public.profile_change_requests') IS NULL
     OR to_regclass('public.admin_staff') IS NULL
     OR to_regclass('public.admin_audit_logs') IS NULL
     OR to_regprocedure('auth.uid()') IS NULL
     OR to_regprocedure('private.has_nexora_permission(text)') IS NULL
     OR to_regnamespace('private') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: required local foundation objects are missing';
  END IF;

  IF NOT has_schema_privilege(current_user,'public','CREATE') THEN
    RAISE EXCEPTION 'SAFETY STOP: current role cannot create public RPC wrappers';
  END IF;
  IF NOT has_schema_privilege(current_user,'private','CREATE') THEN
    RAISE EXCEPTION 'SAFETY STOP: current role cannot create private RPC cores';
  END IF;
END
$guard$;

BEGIN;

-- Buyer -> Seller review core. Reviewer identity is always auth.uid().
CREATE OR REPLACE FUNCTION private._rpc_review_role_request_core(
  p_request_id uuid,
  p_decision text,
  p_admin_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $fn$
DECLARE
  v_actor uuid;
  v_admin_code text;
  v_user_id uuid;
  v_requested_role text;
  v_status text;
  v_note text;
BEGIN
  v_actor := auth.uid();

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;

  IF p_decision IS NULL OR p_decision NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'Decision must be approved or rejected' USING ERRCODE='22023';
  END IF;

  v_note := NULLIF(btrim(p_admin_note),'');
  IF v_note IS NOT NULL AND length(v_note)>1000 THEN
    RAISE EXCEPTION 'Admin note cannot exceed 1000 characters' USING ERRCODE='22023';
  END IF;

  IF NOT private.has_nexora_permission('users.role_requests.review') THEN
    RAISE EXCEPTION 'Not authorized to review role requests' USING ERRCODE='42501';
  END IF;

  SELECT s.admin_code
    INTO v_admin_code
  FROM public.admin_staff s
  JOIN public.profiles ap ON ap.id=s.user_id
  WHERE s.user_id=v_actor
    AND s.is_active=true
    AND ap.role='admin'
    AND ap.account_status='active';

  IF v_admin_code IS NULL THEN
    RAISE EXCEPTION 'Active Admin staff record required' USING ERRCODE='42501';
  END IF;

  SELECT r.user_id, r.requested_role, r.status
    INTO v_user_id, v_requested_role, v_status
  FROM public.role_requests r
  WHERE r.id=p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Role request not found' USING ERRCODE='P0002';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending requests can be reviewed' USING ERRCODE='55000';
  END IF;

  IF v_user_id=v_actor THEN
    RAISE EXCEPTION 'Self-review is not allowed' USING ERRCODE='42501';
  END IF;

  IF v_requested_role <> 'seller' THEN
    RAISE EXCEPTION 'Only Buyer-to-Seller requests are supported' USING ERRCODE='22023';
  END IF;

  IF p_decision='approved' THEN
    UPDATE public.profiles
       SET role='seller',
           buyer_category=NULL,
           seller_categories=ARRAY['wholesale']::text[],
           updated_at=now()
     WHERE id=v_user_id
       AND role='buyer'
       AND account_status='active';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Request owner is not an active Buyer' USING ERRCODE='55000';
    END IF;
  END IF;

  UPDATE public.role_requests
     SET status=p_decision,
         admin_note=v_note,
         reviewed_by=v_actor,
         reviewed_at=now(),
         updated_at=now()
   WHERE id=p_request_id;

  INSERT INTO public.admin_audit_logs(
    actor_user_id, actor_admin_code, action_key, target_type,
    target_id, reason, details
  )
  VALUES(
    v_actor, v_admin_code,
    CASE WHEN p_decision='approved'
      THEN 'users.role_request.approved'
      ELSE 'users.role_request.rejected' END,
    'role_request', p_request_id::text, v_note,
    jsonb_build_object(
      'decision',p_decision,
      'requested_role',v_requested_role,
      'previous_status','pending',
      'new_status',p_decision,
      'profile_role_changed',(p_decision='approved')
    )
  );
END;
$fn$;

-- Personal full-name change review core.
CREATE OR REPLACE FUNCTION private._rpc_review_profile_change_request_core(
  p_request_id uuid,
  p_decision text,
  p_admin_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $fn$
DECLARE
  v_actor uuid;
  v_admin_code text;
  v_user_id uuid;
  v_requested_full_name text;
  v_status text;
  v_note text;
BEGIN
  v_actor := auth.uid();

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;

  IF p_decision IS NULL OR p_decision NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'Decision must be approved or rejected' USING ERRCODE='22023';
  END IF;

  v_note := NULLIF(btrim(p_admin_note),'');
  IF v_note IS NOT NULL AND length(v_note)>1000 THEN
    RAISE EXCEPTION 'Admin note cannot exceed 1000 characters' USING ERRCODE='22023';
  END IF;

  IF NOT private.has_nexora_permission('users.profile_changes.review') THEN
    RAISE EXCEPTION 'Not authorized to review profile changes' USING ERRCODE='42501';
  END IF;

  SELECT s.admin_code
    INTO v_admin_code
  FROM public.admin_staff s
  JOIN public.profiles ap ON ap.id=s.user_id
  WHERE s.user_id=v_actor
    AND s.is_active=true
    AND ap.role='admin'
    AND ap.account_status='active';

  IF v_admin_code IS NULL THEN
    RAISE EXCEPTION 'Active Admin staff record required' USING ERRCODE='42501';
  END IF;

  SELECT r.user_id, r.requested_full_name, r.status
    INTO v_user_id, v_requested_full_name, v_status
  FROM public.profile_change_requests r
  WHERE r.id=p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile change request not found' USING ERRCODE='P0002';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending requests can be reviewed' USING ERRCODE='55000';
  END IF;

  IF v_user_id=v_actor THEN
    RAISE EXCEPTION 'Self-review is not allowed' USING ERRCODE='42501';
  END IF;

  IF v_requested_full_name IS NULL
     OR length(btrim(v_requested_full_name)) NOT BETWEEN 1 AND 150 THEN
    RAISE EXCEPTION 'Requested name must contain 1 to 150 characters' USING ERRCODE='22023';
  END IF;

  IF p_decision='approved' THEN
    UPDATE public.profiles
       SET full_name=btrim(v_requested_full_name),
           updated_at=now()
     WHERE id=v_user_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Profile for request owner was not found' USING ERRCODE='P0002';
    END IF;
  END IF;

  UPDATE public.profile_change_requests
     SET status=p_decision,
         admin_note=v_note,
         reviewed_by=v_actor,
         reviewed_at=now(),
         updated_at=now()
   WHERE id=p_request_id;

  INSERT INTO public.admin_audit_logs(
    actor_user_id, actor_admin_code, action_key, target_type,
    target_id, reason, details
  )
  VALUES(
    v_actor, v_admin_code,
    CASE WHEN p_decision='approved'
      THEN 'users.profile_change.approved'
      ELSE 'users.profile_change.rejected' END,
    'profile_change_request', p_request_id::text, v_note,
    jsonb_build_object(
      'decision',p_decision,
      'previous_status','pending',
      'new_status',p_decision,
      'profile_name_changed',(p_decision='approved')
    )
  );
END;
$fn$;

-- Public PostgREST entry points are SECURITY INVOKER only.
-- The privileged implementation stays in the non-exposed private schema.
CREATE OR REPLACE FUNCTION public.rpc_review_role_request(
  p_request_id uuid,
  p_decision text,
  p_admin_note text DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path=''
AS $wrapper$
  SELECT private._rpc_review_role_request_core($1,$2,$3);
$wrapper$;

CREATE OR REPLACE FUNCTION public.rpc_review_profile_change_request(
  p_request_id uuid,
  p_decision text,
  p_admin_note text DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path=''
AS $wrapper$
  SELECT private._rpc_review_profile_change_request_core($1,$2,$3);
$wrapper$;

-- Keep the implementation functions private and grant only the intended caller.
GRANT USAGE ON SCHEMA private TO authenticated;

REVOKE ALL ON FUNCTION private._rpc_review_role_request_core(uuid,text,text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private._rpc_review_profile_change_request_core(uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private._rpc_review_role_request_core(uuid,text,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION private._rpc_review_profile_change_request_core(uuid,text,text)
  TO authenticated;

-- No direct UPDATE grant is added to request/profile tables.
REVOKE ALL ON FUNCTION public.rpc_review_role_request(uuid,text,text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_review_profile_change_request(uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_review_role_request(uuid,text,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_review_profile_change_request(uuid,text,text)
  TO authenticated;

-- Verify the intended RPC ACLs and pinned search_path before commit.
DO $verify$
DECLARE
  v_count integer;
BEGIN
  -- Public wrappers must be invoker; privileged cores must remain private.
  SELECT count(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname IN ('rpc_review_role_request','rpc_review_profile_change_request')
    AND p.prosecdef=false
    AND p.proconfig @> ARRAY['search_path=""']
    AND has_function_privilege('anon',p.oid,'EXECUTE')=false
    AND has_function_privilege('authenticated',p.oid,'EXECUTE')=true;

  IF v_count<>2 THEN
    RAISE EXCEPTION 'RPC verification failed: expected 2 invoker public wrappers, found %',v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private'
    AND p.proname IN ('_rpc_review_role_request_core','_rpc_review_profile_change_request_core')
    AND p.prosecdef=true
    AND p.proconfig @> ARRAY['search_path=""']
    AND has_function_privilege('anon',p.oid,'EXECUTE')=false
    AND has_function_privilege('authenticated',p.oid,'EXECUTE')=true;

  IF v_count<>2 THEN
    RAISE EXCEPTION 'RPC verification failed: expected 2 private definer cores, found %',v_count;
  END IF;

  IF has_table_privilege('authenticated','public.role_requests','UPDATE')
     OR has_table_privilege('authenticated','public.profile_change_requests','UPDATE')
     OR has_table_privilege('authenticated','public.profiles','UPDATE') THEN
    RAISE EXCEPTION 'Unsafe direct UPDATE table grant detected';
  END IF;
END
$verify$;

COMMIT;

\echo
\echo '=== LOCAL REVIEW RPC PROTOTYPE CREATED ==='
\echo 'Public invoker RPC: public.rpc_review_role_request(uuid,text,text)'
\echo 'Public invoker RPC: public.rpc_review_profile_change_request(uuid,text,text)'
\echo 'Private definer core: private._rpc_review_role_request_core(uuid,text,text)'
\echo 'Private definer core: private._rpc_review_profile_change_request_core(uuid,text,text)'
\echo 'No table UPDATE grants were added. No existing rows were changed.'
\echo 'This is a local prototype only; validate with tests and real Supabase JWT/Auth before deployment.'
