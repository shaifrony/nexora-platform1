-- NEXORA LOCAL REVIEW RPC EXTENDED NEGATIVE / ATOMICITY TESTS
-- Run only after 06_local_foundation_baseline_fixture.sql,
-- 12_local_review_rpc_prototype.sql, and 13_local_review_rpc_tests.sql.
-- SAFE TARGET: nexora_test ONLY. ALL TEST DATA / DDL IS ROLLED BACK.
-- This is still a local superuser logic test, NOT a Supabase JWT/RLS integration test.
\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test';
  END IF;
  IF to_regprocedure('public.rpc_review_role_request(uuid,text,text)') IS NULL
     OR to_regprocedure('public.rpc_review_profile_change_request(uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Run local review RPC prototype first';
  END IF;
END
$guard$;

BEGIN;

-- Identities: active authorized Admin, inactive Admin, active Admin without
-- exact permission, Seller caller, Porter caller, and Seller request target.
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('21000000-0000-4000-8000-000000000001','rpc-ext-authorized@nexora.invalid','{"role":"buyer","full_name":"Authorized Reviewer"}','{}'),
 ('21000000-0000-4000-8000-000000000002','rpc-ext-inactive@nexora.invalid','{"role":"buyer","full_name":"Inactive Reviewer"}','{}'),
 ('21000000-0000-4000-8000-000000000003','rpc-ext-no-permission@nexora.invalid','{"role":"buyer","full_name":"No Permission Reviewer"}','{}'),
 ('21000000-0000-4000-8000-000000000004','rpc-ext-seller@nexora.invalid','{"role":"seller","full_name":"Seller Caller","seller_categories":["wholesale"]}','{}'),
 ('21000000-0000-4000-8000-000000000005','rpc-ext-porter@nexora.invalid','{"role":"porter","full_name":"Porter Caller"}','{}'),
 ('21000000-0000-4000-8000-000000000006','rpc-ext-target-seller@nexora.invalid','{"role":"seller","full_name":"Existing Seller","seller_categories":["wholesale"]}','{}'),
 ('21000000-0000-4000-8000-000000000007','rpc-ext-target-buyer@nexora.invalid','{"role":"buyer","full_name":"Atomicity Buyer"}','{}');

UPDATE public.profiles
SET role='admin', buyer_category=NULL, seller_categories='{}'::text[]
WHERE id IN (
 '21000000-0000-4000-8000-000000000001',
 '21000000-0000-4000-8000-000000000002',
 '21000000-0000-4000-8000-000000000003'
);

INSERT INTO public.admin_staff(user_id,admin_code,admin_level,department_key,is_active,position_key)
VALUES
 ('21000000-0000-4000-8000-000000000001','LOCAL-EXT-AUTH','assistant_admin','managing_director',true,'department_officer'),
 ('21000000-0000-4000-8000-000000000002','LOCAL-EXT-INACTIVE','assistant_admin','managing_director',false,'department_officer'),
 ('21000000-0000-4000-8000-000000000003','LOCAL-EXT-NOPERM','assistant_admin','managing_director',true,'department_officer');

INSERT INTO public.admin_permission_grants(admin_user_id,permission_key,is_allowed)
VALUES
 ('21000000-0000-4000-8000-000000000001','users.role_requests.review',true),
 ('21000000-0000-4000-8000-000000000002','users.role_requests.review',true);

INSERT INTO public.role_requests(id,user_id,requested_role,status) VALUES
 ('31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000007','seller','pending'),
 ('31000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000007','seller','cancelled'),
 ('31000000-0000-4000-8000-000000000003','21000000-0000-4000-8000-000000000006','seller','pending'),
 ('31000000-0000-4000-8000-000000000004','21000000-0000-4000-8000-000000000007','seller','pending');

DO $tests$
DECLARE
  v_failed boolean;
  v_audit_before integer;
BEGIN
  -- All calls below use the intended reviewer UID through the local auth.uid fixture.
  -- Inactive Admin is denied even though a permission grant exists.
  PERFORM set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000002',true);
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request('31000000-0000-4000-8000-000000000001','approved',NULL);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: inactive Admin was not denied'; END IF;

  -- Active Admin without exact permission is denied.
  PERFORM set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000003',true);
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request('31000000-0000-4000-8000-000000000001','approved',NULL);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: Admin without permission was not denied'; END IF;

  -- Seller caller is denied.
  PERFORM set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000004',true);
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request('31000000-0000-4000-8000-000000000001','approved',NULL);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: Seller caller was not denied'; END IF;

  -- Porter caller is denied.
  PERFORM set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000005',true);
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request('31000000-0000-4000-8000-000000000001','approved',NULL);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: Porter caller was not denied'; END IF;

  -- Authorized reviewer.
  PERFORM set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000001',true);

  -- Missing request.
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request('31999999-0000-4000-8000-000000000099','approved',NULL);
  EXCEPTION WHEN SQLSTATE 'P0002' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: missing request ID was not rejected'; END IF;

  -- Invalid decision.
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request('31000000-0000-4000-8000-000000000001','approved_with_changes',NULL);
  EXCEPTION WHEN SQLSTATE '22023' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: invalid decision was not rejected'; END IF;

  -- Already-cancelled request.
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request('31000000-0000-4000-8000-000000000002','approved',NULL);
  EXCEPTION WHEN SQLSTATE '55000' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: cancelled request was not rejected'; END IF;

  -- Overlength note.
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request(
      '31000000-0000-4000-8000-000000000001','approved',repeat('x',1001)
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: overlength admin note was not rejected'; END IF;

  -- Target is already Seller, not an active Buyer eligible for promotion.
  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request('31000000-0000-4000-8000-000000000003','approved',NULL);
  EXCEPTION WHEN SQLSTATE '55000' THEN v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: non-Buyer target was not rejected'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='21000000-0000-4000-8000-000000000006' AND role='seller'
  ) THEN RAISE EXCEPTION 'FAIL: existing Seller profile unexpectedly changed'; END IF;

  -- Force the audit INSERT to fail, then prove the request and profile changes
  -- performed earlier in the same RPC statement were rolled back.
  SELECT count(*) INTO v_audit_before
  FROM public.admin_audit_logs
  WHERE target_id='31000000-0000-4000-8000-000000000004';

  CREATE FUNCTION pg_temp.nexora_force_audit_failure()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $trigger$
  BEGIN
    RAISE EXCEPTION 'intentional local test audit failure' USING ERRCODE='P0001';
  END;
  $trigger$;

  CREATE TRIGGER nexora_force_audit_failure
  BEFORE INSERT ON public.admin_audit_logs
  FOR EACH ROW EXECUTE FUNCTION pg_temp.nexora_force_audit_failure();

  v_failed:=false;
  BEGIN
    PERFORM public.rpc_review_role_request(
      '31000000-0000-4000-8000-000000000004','approved','Must rollback'
    );
  EXCEPTION WHEN SQLSTATE 'P0001' THEN v_failed:=true;
  END;

  DROP TRIGGER nexora_force_audit_failure ON public.admin_audit_logs;

  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: forced audit failure did not propagate'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.role_requests
    WHERE id='31000000-0000-4000-8000-000000000004' AND status='pending'
      AND reviewed_by IS NULL AND reviewed_at IS NULL
  ) THEN RAISE EXCEPTION 'FAIL: request update was not rolled back after audit failure'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='21000000-0000-4000-8000-000000000007'
      AND role='buyer' AND buyer_category='wholesale'
  ) THEN RAISE EXCEPTION 'FAIL: profile promotion was not rolled back after audit failure'; END IF;
  IF (SELECT count(*) FROM public.admin_audit_logs
      WHERE target_id='31000000-0000-4000-8000-000000000004') <> v_audit_before THEN
    RAISE EXCEPTION 'FAIL: audit row unexpectedly persisted after forced failure';
  END IF;

  RAISE NOTICE 'PASS: inactive Admin, missing permission, Seller/Porter denial, missing ID, invalid decision, cancelled request, overlength note, non-Buyer target, and audit-failure atomic rollback';
END
$tests$;

ROLLBACK;
\echo '=== LOCAL EXTENDED REVIEW RPC TESTS PASSED; ALL TEST DATA AND TEST DDL ROLLED BACK ==='
\echo 'Local superuser test only. Does not prove hosted Supabase Auth/JWT/PostgREST/RLS or concurrent-session behavior.';
