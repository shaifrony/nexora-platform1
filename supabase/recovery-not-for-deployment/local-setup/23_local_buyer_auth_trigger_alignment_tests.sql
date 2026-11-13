-- NEXORA LOCAL B-01 AUTH TRIGGER ALIGNMENT + TESTS
-- SAFE TARGET: local PostgreSQL database nexora_test ONLY.
-- This patches the local-only reconstructed fixture, NOT Supabase hosted Auth.
-- It is not a migration and must never be moved into supabase/migrations/.
-- Schema/function alignment is committed locally; all test Auth/Profile rows roll back.

\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %',current_database();
  END IF;
  IF to_regclass('auth.users') IS NULL
     OR to_regclass('public.profiles') IS NULL
     OR to_regclass('public.porter_account_reviews') IS NULL
     OR to_regprocedure('public.handle_new_user()') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: local foundation fixture is incomplete; do not run this script';
  END IF;
END
$guard$;

-- Align the already-created local foundation fixture with current NEXORA rules.
BEGIN;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_market_categories_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_market_categories_check
  CHECK (buyer_category IS NULL AND seller_categories='{}'::text[]);

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

COMMIT;

\echo 'LOCAL AUTH TRIGGER PATCH APPLIED; starting transactional tests.'

BEGIN;

-- Email Buyer: legacy category metadata is ignored and never stored on profile.
INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data) VALUES
('11000000-0000-4000-8000-000000000001','b01-buyer@nexora.invalid',
 '{"provider":"email"}',
 '{"role":"buyer","full_name":"B01 Buyer","buyer_category":"retail","seller_categories":["retail"]}');

-- Email Seller: sale type belongs to each product, not the account profile.
INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data) VALUES
('11000000-0000-4000-8000-000000000002','b01-seller@nexora.invalid',
 '{"provider":"email"}',
 '{"role":"seller","full_name":"B01 Seller","seller_categories":["wholesale","retail"]}');

-- Porter: registration is allowed but workspace access remains pending review.
INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data) VALUES
('11000000-0000-4000-8000-000000000003','b01-porter@nexora.invalid',
 '{"provider":"email"}',
 '{"role":"porter","full_name":"B01 Porter"}');

-- Every social provider is Buyer-only, even if user-editable metadata requests a privileged role.
INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data) VALUES
('11000000-0000-4000-8000-000000000004','b01-google@nexora.invalid',
 '{"provider":"google"}',
 '{"role":"admin","full_name":"B01 Google"}'),
('11000000-0000-4000-8000-000000000005','b01-facebook@nexora.invalid',
 '{"provider":"facebook"}',
 '{"role":"porter","full_name":"B01 Facebook"}'),
('11000000-0000-4000-8000-000000000006','b01-github@nexora.invalid',
 '{"provider":"github"}',
 '{"role":"seller","full_name":"B01 Social Provider"}');

-- Missing email-signup role defaults safely to Buyer.
INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data) VALUES
('11000000-0000-4000-8000-000000000007','b01-default@nexora.invalid',
 '{"provider":"email"}','{"full_name":"B01 Default"}');

DO $negative_tests$
DECLARE
  v_rejected boolean;
BEGIN
  v_rejected:=false;
  BEGIN
    INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data) VALUES
    ('11000000-0000-4000-8000-000000000008','b01-admin-forbidden@nexora.invalid',
     '{"provider":"email"}','{"role":"admin","full_name":"Forbidden Admin"}');
  EXCEPTION WHEN others THEN
    v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: public email signup accepted Admin role'; END IF;

  v_rejected:=false;
  BEGIN
    INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data) VALUES
    ('11000000-0000-4000-8000-000000000009','b01-director-forbidden@nexora.invalid',
     '{"provider":"email"}','{"role":"director","full_name":"Forbidden Director"}');
  EXCEPTION WHEN others THEN
    v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: public email signup accepted unknown role'; END IF;
END
$negative_tests$;

DO $assertions$
BEGIN
  IF (SELECT count(*) FROM public.profiles WHERE id IN (
    '11000000-0000-4000-8000-000000000001',
    '11000000-0000-4000-8000-000000000002',
    '11000000-0000-4000-8000-000000000003',
    '11000000-0000-4000-8000-000000000004',
    '11000000-0000-4000-8000-000000000005',
    '11000000-0000-4000-8000-000000000006',
    '11000000-0000-4000-8000-000000000007'
  )) <> 7 THEN
    RAISE EXCEPTION 'FAIL: expected seven valid signup profiles';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id IN (
      '11000000-0000-4000-8000-000000000001',
      '11000000-0000-4000-8000-000000000002',
      '11000000-0000-4000-8000-000000000003',
      '11000000-0000-4000-8000-000000000004',
      '11000000-0000-4000-8000-000000000005',
      '11000000-0000-4000-8000-000000000006',
      '11000000-0000-4000-8000-000000000007'
    )
    AND (buyer_category IS NOT NULL OR seller_categories<>'{}'::text[])
  ) THEN
    RAISE EXCEPTION 'FAIL: legacy market category metadata was stored on a profile';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles
    WHERE id='11000000-0000-4000-8000-000000000001'
      AND role='buyer' AND account_status='active') THEN
    RAISE EXCEPTION 'FAIL: Buyer must be active immediately';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles
    WHERE id='11000000-0000-4000-8000-000000000002'
      AND role='seller' AND account_status='active') THEN
    RAISE EXCEPTION 'FAIL: Seller registration/profile completion should be active before public listing approval';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles
    WHERE id='11000000-0000-4000-8000-000000000003'
      AND role='porter' AND account_status='pending')
     OR NOT EXISTS (SELECT 1 FROM public.porter_account_reviews
       WHERE user_id='11000000-0000-4000-8000-000000000003'
         AND review_status='pending') THEN
    RAISE EXCEPTION 'FAIL: Porter must remain pending with a pending review record';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles
    WHERE id IN (
      '11000000-0000-4000-8000-000000000004',
      '11000000-0000-4000-8000-000000000005',
      '11000000-0000-4000-8000-000000000006',
      '11000000-0000-4000-8000-000000000007'
    ) AND (role<>'buyer' OR account_status<>'active')) THEN
    RAISE EXCEPTION 'FAIL: OAuth/default signup must resolve to active Buyer';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles
    WHERE id IN ('11000000-0000-4000-8000-000000000008',
                 '11000000-0000-4000-8000-000000000009')) THEN
    RAISE EXCEPTION 'FAIL: rejected privileged role signup left a profile';
  END IF;

  IF has_function_privilege('anon','public.handle_new_user()','EXECUTE')
     OR has_function_privilege('authenticated','public.handle_new_user()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Auth trigger function remains executable by Data API roles';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='public.handle_new_user()'::regprocedure
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""']
  ) THEN
    RAISE EXCEPTION 'FAIL: Auth trigger function must be SECURITY DEFINER with empty search_path';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='auth.users'::regclass
      AND t.tgfoid='public.handle_new_user()'::regprocedure
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'FAIL: Auth users trigger is not attached to the expected function';
  END IF;
END
$assertions$;

SELECT 'PASS' AS result,
  'B-01 trigger: universal Buyer/Seller metadata, OAuth Buyer-only, Admin role rejection, Porter pending gate, safe function ACL/search_path' AS checks;

ROLLBACK;

\echo '=== LOCAL B-01 AUTH TRIGGER TESTS PASSED; ALL TEST DATA ROLLED BACK ==='
\echo 'The local fixture schema/function alignment remains in nexora_test; no Hosted Supabase was changed.'
