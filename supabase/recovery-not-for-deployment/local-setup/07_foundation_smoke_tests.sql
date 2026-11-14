-- NEXORA LOCAL FOUNDATION SMOKE TESTS
-- Run only after 06_local_foundation_baseline_fixture.sql.
-- Tests local PostgreSQL trigger/constraint behavior only; not real Supabase Auth/RLS/JWT/MFA.
\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test';
  END IF;
  IF to_regclass('public.profiles') IS NULL
     OR to_regprocedure('public.handle_new_user()') IS NULL THEN
    RAISE EXCEPTION 'Run 06_local_foundation_baseline_fixture.sql first';
  END IF;
END
$guard$;

BEGIN;

-- Valid Buyer signup.
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
VALUES(
 '10000000-0000-4000-8000-000000000001',
 'local-buyer@nexora.invalid',
 '{"role":"buyer","full_name":"Local Buyer","buyer_category":"wholesale"}'::jsonb,
 '{}'::jsonb
);

-- Valid Seller signup.
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
VALUES(
 '10000000-0000-4000-8000-000000000002',
 'local-seller@nexora.invalid',
 '{"role":"seller","full_name":"Local Seller","seller_categories":["wholesale"]}'::jsonb,
 '{}'::jsonb
);

-- Porter signup must be pending and receive a separate pending review record.
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
VALUES(
 '10000000-0000-4000-8000-000000000003',
 'local-porter@nexora.invalid',
 '{"role":"porter","full_name":"Local Porter"}'::jsonb,
 '{}'::jsonb
);

-- OAuth signup must become Buyer even if editable user metadata asks for Admin.
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
VALUES(
 '10000000-0000-4000-8000-000000000004',
 'local-oauth@nexora.invalid',
 '{"role":"admin","full_name":"Local OAuth"}'::jsonb,
 '{"provider":"google"}'::jsonb
);

DO $validations$
DECLARE
  v_count integer;
  v_status text;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.profiles
  WHERE id IN (
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000004'
  );
  IF v_count<>4 THEN RAISE EXCEPTION 'Expected four valid profiles; found %',v_count; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='10000000-0000-4000-8000-000000000001'
      AND role='buyer' AND account_status='active'
      AND buyer_category IS NULL AND seller_categories='{}'::text[]
  ) THEN RAISE EXCEPTION 'Buyer signup assertion failed'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='10000000-0000-4000-8000-000000000002'
      AND role='seller' AND account_status='active'
      AND buyer_category IS NULL
      AND seller_categories='{}'::text[]
  ) THEN RAISE EXCEPTION 'Seller signup assertion failed'; END IF;

  SELECT account_status INTO v_status
  FROM public.profiles WHERE id='10000000-0000-4000-8000-000000000003';
  IF v_status<>'pending' OR NOT EXISTS (
    SELECT 1 FROM public.porter_account_reviews
    WHERE user_id='10000000-0000-4000-8000-000000000003'
      AND review_status='pending'
  ) THEN RAISE EXCEPTION 'Porter pending approval assertion failed'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='10000000-0000-4000-8000-000000000004'
      AND role='buyer' AND account_status='active'
  ) THEN RAISE EXCEPTION 'OAuth Buyer-only assertion failed'; END IF;
END
$validations$;

-- Public signup must reject Admin role; legacy Retail metadata must be ignored.
DO $negative_tests$
DECLARE
  v_rejected boolean;
BEGIN
  v_rejected:=false;
  BEGIN
    INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
    VALUES(
      '10000000-0000-4000-8000-000000000005',
      'local-admin-forbidden@nexora.invalid',
      '{"role":"admin","full_name":"Forbidden Admin"}'::jsonb,
      '{}'::jsonb
    );
  EXCEPTION WHEN others THEN
    v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Public Admin signup was not rejected'; END IF;

  -- Retail metadata is ignored; the Buyer profile remains universal.
  INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
  VALUES(
    '10000000-0000-4000-8000-000000000006',
    'local-retail-metadata@nexora.invalid',
    '{"role":"buyer","full_name":"Universal Buyer","buyer_category":"retail"}'::jsonb,
    '{}'::jsonb
  );

  IF EXISTS (
    SELECT 1 FROM auth.users
    WHERE id='10000000-0000-4000-8000-000000000005'
  ) THEN RAISE EXCEPTION 'Rejected Admin signup left an Auth fixture row'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='10000000-0000-4000-8000-000000000006'
      AND role='buyer' AND account_status='active'
      AND buyer_category IS NULL AND seller_categories='{}'::text[]
  ) THEN RAISE EXCEPTION 'Legacy Retail metadata was not safely ignored'; END IF;
END
$negative_tests$;

-- A user cannot self-promote their profile role.
DO $protected_field_test$
DECLARE
  v_rejected boolean:=false;
BEGIN
  PERFORM set_config(
    'request.jwt.claim.sub',
    '10000000-0000-4000-8000-000000000001',
    true
  );
  BEGIN
    UPDATE public.profiles
    SET role='admin'
    WHERE id='10000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN others THEN
    v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Self role-change was not rejected'; END IF;
END
$protected_field_test$;

SELECT
  'PASS' AS result,
  'Buyer/Seller/Porter signup, universal category metadata handling, OAuth Buyer-only, Admin rejection, Porter pending gate, and role immutability' AS checks;

ROLLBACK;

\echo '=== LOCAL FOUNDATION SMOKE TESTS PASSED; ALL TEST DATA ROLLED BACK ==='
\echo 'These checks do not validate Supabase Auth, real RLS JWT context, PostgREST, Storage, Realtime or MFA/AAL2.';
