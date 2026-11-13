-- NEXORA LOCAL REVIEW RPC TESTS
-- Run only after 06_local_foundation_baseline_fixture.sql and 12_local_review_rpc_prototype.sql.
-- SAFE TARGET: nexora_test ONLY. ALL TEST DATA IS ROLLED BACK.
-- The public RPC wrappers must be invoker; private implementation cores are definer.
-- Running this script as local superuser does NOT simulate authenticated RLS/ACL enforcement.
-- Does not validate real Supabase Auth/JWT/PostgREST/MFA or hosted ownership semantics.
\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test';
  END IF;
  IF to_regprocedure('public.rpc_review_role_request(uuid,text,text)') IS NULL
     OR to_regprocedure('public.rpc_review_profile_change_request(uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Run 12_local_review_rpc_prototype.sql first';
  END IF;
END
$guard$;

BEGIN;

-- Test identities. Signup trigger creates Buyer profiles; Admin is provisioned
-- manually inside this rolled-back test, never through public signup.
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('20000000-0000-4000-8000-000000000001','rpc-admin@nexora.invalid','{"role":"buyer","full_name":"Local RPC Admin"}','{}'),
 ('20000000-0000-4000-8000-000000000002','rpc-buyer-approve@nexora.invalid','{"role":"buyer","full_name":"Buyer To Promote"}','{}'),
 ('20000000-0000-4000-8000-000000000003','rpc-buyer-reject@nexora.invalid','{"role":"buyer","full_name":"Buyer To Keep"}','{}'),
 ('20000000-0000-4000-8000-000000000004','rpc-profile-approve@nexora.invalid','{"role":"buyer","full_name":"Old Name Approve"}','{}'),
 ('20000000-0000-4000-8000-000000000005','rpc-profile-reject@nexora.invalid','{"role":"buyer","full_name":"Old Name Reject"}','{}');

UPDATE public.profiles
SET role='admin', buyer_category=NULL, seller_categories='{}'::text[]
WHERE id='20000000-0000-4000-8000-000000000001';

INSERT INTO public.admin_staff(
  user_id,admin_code,admin_level,department_key,is_active,position_key
)
VALUES(
 '20000000-0000-4000-8000-000000000001',
 'LOCAL-RPC-MD-TEST','assistant_admin','managing_director',true,'managing_director'
);

INSERT INTO public.admin_permission_grants(admin_user_id,permission_key,is_allowed)
VALUES
 ('20000000-0000-4000-8000-000000000001','users.role_requests.review',true),
 ('20000000-0000-4000-8000-000000000001','users.profile_changes.review',true);

INSERT INTO public.role_requests(id,user_id,requested_role,status)
VALUES
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','seller','pending'),
 ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000003','seller','pending'),
 ('30000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000001','seller','pending');

INSERT INTO public.profile_change_requests(id,user_id,requested_full_name,status)
VALUES
 ('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000004','New Approved Name','pending'),
 ('40000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000005','New Rejected Name','pending');

DO $tests$
DECLARE
  v_failed boolean;
  v_audit_count integer;
BEGIN
  -- No authenticated identity.
  PERFORM set_config('request.jwt.claim.sub','',true);
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request(
      '30000000-0000-4000-8000-000000000001','approved',NULL
    );
  EXCEPTION WHEN SQLSTATE '28000' THEN
    v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: unauthenticated review was not rejected'; END IF;

  -- Ordinary Buyer cannot review.
  PERFORM set_config(
    'request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true
  );
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request(
      '30000000-0000-4000-8000-000000000001','approved',NULL
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: Buyer review was not rejected'; END IF;

  -- Admin with explicit permissions approves Buyer -> Seller.
  PERFORM set_config(
    'request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true
  );
  PERFORM public.rpc_review_role_request(
    '30000000-0000-4000-8000-000000000001','approved','Verified test approval'
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='20000000-0000-4000-8000-000000000002'
      AND role='seller' AND account_status='active'
      AND buyer_category IS NULL
      AND seller_categories=ARRAY['wholesale']::text[]
  ) THEN RAISE EXCEPTION 'FAIL: Buyer -> Seller approval did not update profile correctly'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.role_requests
    WHERE id='30000000-0000-4000-8000-000000000001'
      AND status='approved'
      AND reviewed_by='20000000-0000-4000-8000-000000000001'
      AND reviewed_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'FAIL: approved role request audit fields missing'; END IF;

  -- Re-review of a completed request must fail.
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request(
      '30000000-0000-4000-8000-000000000001','rejected',NULL
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: completed role request was reviewed twice'; END IF;

  -- Self-review must fail.
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request(
      '30000000-0000-4000-8000-000000000003','approved',NULL
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: self-review was not rejected'; END IF;

  -- Rejecting a role request must not change the user's role.
  PERFORM public.rpc_review_role_request(
    '30000000-0000-4000-8000-000000000002','rejected','Test rejection'
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='20000000-0000-4000-8000-000000000003'
      AND role='buyer' AND buyer_category='wholesale'
  ) THEN RAISE EXCEPTION 'FAIL: rejected role request changed profile role'; END IF;

  -- NULL decision must fail explicitly.
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request(
      '30000000-0000-4000-8000-000000000003',NULL,NULL
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN
    v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: NULL decision was not rejected'; END IF;

  -- Approve a profile-name change.
  PERFORM public.rpc_review_profile_change_request(
    '40000000-0000-4000-8000-000000000001','approved','Name checked'
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='20000000-0000-4000-8000-000000000004'
      AND full_name='New Approved Name'
  ) THEN RAISE EXCEPTION 'FAIL: approved profile name was not applied'; END IF;

  -- Reject a profile-name change; original name must remain unchanged.
  PERFORM public.rpc_review_profile_change_request(
    '40000000-0000-4000-8000-000000000002','rejected','Name not accepted'
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='20000000-0000-4000-8000-000000000005'
      AND full_name='Old Name Reject'
  ) THEN RAISE EXCEPTION 'FAIL: rejected profile name changed the profile'; END IF;

  -- Four completed decisions, four corresponding audit events.
  SELECT count(*) INTO v_audit_count
  FROM public.admin_audit_logs
  WHERE actor_user_id='20000000-0000-4000-8000-000000000001'
    AND target_id IN (
      '30000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000002',
      '40000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000002'
    );
  IF v_audit_count<>4 THEN
    RAISE EXCEPTION 'FAIL: expected 4 audit records, found %',v_audit_count;
  END IF;

  -- Public wrapper ACL/security mode and private core ACL/security mode.
  IF has_function_privilege('anon','public.rpc_review_role_request(uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.rpc_review_profile_change_request(uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','private._rpc_review_role_request_core(uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','private._rpc_review_profile_change_request_core(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon can execute a review RPC or private core';
  END IF;
  IF NOT has_function_privilege('authenticated','public.rpc_review_role_request(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.rpc_review_profile_change_request(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','private._rpc_review_role_request_core(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','private._rpc_review_profile_change_request_core(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated lacks intended review RPC/core EXECUTE';
  END IF;
  IF (SELECT prosecdef FROM pg_proc WHERE oid='public.rpc_review_role_request(uuid,text,text)'::regprocedure)
     OR (SELECT prosecdef FROM pg_proc WHERE oid='public.rpc_review_profile_change_request(uuid,text,text)'::regprocedure) THEN
    RAISE EXCEPTION 'FAIL: public RPC wrapper must be SECURITY INVOKER';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid='private._rpc_review_role_request_core(uuid,text,text)'::regprocedure)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='private._rpc_review_profile_change_request(uuid,text,text)'::regprocedure) THEN
    RAISE EXCEPTION 'FAIL: private RPC core must be SECURITY DEFINER';
  END IF;
  IF has_table_privilege('authenticated','public.role_requests','UPDATE')
     OR has_table_privilege('authenticated','public.profile_change_requests','UPDATE')
     OR has_table_privilege('authenticated','public.profiles','UPDATE') THEN
    RAISE EXCEPTION 'FAIL: authenticated has a direct UPDATE grant';
  END IF;

  RAISE NOTICE 'PASS: review RPC authorization, Buyer-to-Seller approval, rejection, self-review block, repeat-review block, profile-name workflow, audit writes, NULL decision validation, and narrow ACLs';
END
$tests$;

ROLLBACK;

\echo '=== LOCAL REVIEW RPC TESTS PASSED; ALL TEST DATA ROLLED BACK ==='
\echo 'These tests validate local function logic and catalog ACL metadata only; local superuser execution bypasses real authenticated RLS/ACL behavior.'
\echo 'They do not validate Supabase Auth/JWT/PostgREST, private-schema exposure settings, or MFA/AAL2.';
