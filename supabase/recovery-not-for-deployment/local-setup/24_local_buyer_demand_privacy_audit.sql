-- NEXORA LOCAL B-03 BUYER DEMAND PRIVACY / ROUTING CATALOG AUDIT
-- Current fixture companion: 25_local_buyer_demand_fixture.sql
-- READ-ONLY: no schema, data, grants, or policies are changed.
-- Run only on local nexora_test after the complete Marketplace migrations are rehearsed.
-- This script is NOT a migration and must never be run against Live Supabase.
\set ON_ERROR_STOP on
\pset pager off

BEGIN READ ONLY;

DO $audit$
DECLARE
  v_missing text[] := ARRAY[]::text[];
  v_def text;
  v_policy text;
  v_view_cols text[];
  v_required text[] := ARRAY[
    'id','demand_code','product_name','category','subcategory','description',
    'specifications_quality','required_quantity','budget','currency',
    'destination_country','destination_city','required_date','demand_status','created_at'
  ];
  v_col text;
  v_count integer;
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %',current_database();
  END IF;

  IF to_regclass('public.buyer_demands') IS NULL
     OR to_regclass('public.seller_offers') IS NULL
     OR to_regclass('public.buyer_demand_inbox') IS NULL
     OR to_regclass('public.public_buyer_demands') IS NULL
     OR to_regclass('public.products') IS NULL
     OR to_regclass('public.public_businesses') IS NULL THEN
    RAISE NOTICE 'SKIP: full Marketplace Demand schema is not installed in this local database.';
    RETURN;
  END IF;

  -- All Demand-related base tables must have RLS enabled.
  IF EXISTS (
    SELECT 1 FROM pg_class c
    WHERE c.oid IN (
      'public.buyer_demands'::regclass,
      'public.seller_offers'::regclass,
      'public.buyer_demand_inbox'::regclass
    ) AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'FAIL: RLS is disabled on a Demand-related table';
  END IF;
  RAISE NOTICE 'PASS: RLS enabled on buyer_demands, seller_offers and buyer_demand_inbox';

  -- The public projection must be security-invoker and expose an explicit safe allowlist.
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    WHERE c.oid='public.public_buyer_demands'::regclass
      AND coalesce(c.reloptions,'{}'::text[]) @> ARRAY['security_invoker=true']
  ) THEN
    RAISE EXCEPTION 'FAIL: public_buyer_demands is not SECURITY INVOKER';
  END IF;

  SELECT array_agg(a.attname ORDER BY a.attname) INTO v_view_cols
  FROM pg_attribute a
  WHERE a.attrelid='public.public_buyer_demands'::regclass
    AND a.attnum>0 AND NOT a.attisdropped;

  IF v_view_cols IS DISTINCT FROM ARRAY(
    SELECT unnest(v_required) ORDER BY 1
  ) THEN
    RAISE EXCEPTION 'FAIL: public Demand view columns differ from the safe allowlist; found %',v_view_cols;
  END IF;

  IF v_view_cols && ARRAY[
    'buyer_id','email','phone','full_name','profile_id','contact_name','contact_phone'
  ]::text[] THEN
    RAISE EXCEPTION 'FAIL: public Demand projection contains private identity/contact columns';
  END IF;
  RAISE NOTICE 'PASS: public Demand view is SECURITY INVOKER with exact safe column allowlist';

  -- Anonymous callers must not be able to select the Buyer foreign key or private offer/inbox tables.
  IF has_column_privilege('anon','public.buyer_demands','buyer_id','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon can SELECT buyer_demands.buyer_id';
  END IF;
  IF has_any_column_privilege('anon','public.buyer_demand_inbox','SELECT')
     OR has_any_column_privilege('anon','public.seller_offers','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon can read private Demand inbox or Seller offers';
  END IF;
  IF NOT has_table_privilege('anon','public.public_buyer_demands','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon cannot read the intended public Demand projection';
  END IF;
  RAISE NOTICE 'PASS: anonymous Demand access is limited to public projection; Buyer ID, inbox and offers are private';

  -- Demand ownership and Buyer-only create/update policies.
  SELECT qual INTO v_policy FROM pg_policies
  WHERE schemaname='public' AND tablename='buyer_demands'
    AND policyname='demands_owner_inbox_admin_read';
  IF v_policy IS NULL OR v_policy NOT ILIKE '%buyer_id%' OR v_policy NOT ILIKE '%auth.uid%'
     OR v_policy NOT ILIKE '%buyer_demand_inbox%' THEN
    RAISE EXCEPTION 'FAIL: Seller Demand read policy does not enforce Buyer ownership / Seller inbox routing';
  END IF;

  SELECT with_check INTO v_policy FROM pg_policies
  WHERE schemaname='public' AND tablename='buyer_demands'
    AND policyname='demands_insert_buyer_or_admin';
  IF v_policy IS NULL OR v_policy NOT ILIKE '%buyer_id%' OR v_policy NOT ILIKE '%auth.uid%'
     OR v_policy NOT ILIKE '%buyer%' OR v_policy NOT ILIKE '%active%' THEN
    RAISE EXCEPTION 'FAIL: Demand INSERT policy does not require the active Buyer to own the row';
  END IF;

  SELECT qual INTO v_policy FROM pg_policies
  WHERE schemaname='public' AND tablename='buyer_demands'
    AND policyname='demands_update_owner_or_admin';
  IF v_policy IS NULL OR v_policy NOT ILIKE '%buyer_id%' OR v_policy NOT ILIKE '%auth.uid%'
     OR v_policy NOT ILIKE '%demand_status%' OR v_policy NOT ILIKE '%open%' THEN
    RAISE EXCEPTION 'FAIL: Demand UPDATE policy does not restrict edits to the owning Buyer while open';
  END IF;
  RAISE NOTICE 'PASS: Buyer owns Demand create/read/update; edits require an open Demand';

  -- Seller inbox is owner-scoped; direct browser writes to routing table are forbidden.
  SELECT qual INTO v_policy FROM pg_policies
  WHERE schemaname='public' AND tablename='buyer_demand_inbox'
    AND policyname='buyer_demand_inbox_seller_read';
  IF v_policy IS NULL OR v_policy NOT ILIKE '%seller_id%' OR v_policy NOT ILIKE '%auth.uid%'
     OR v_policy NOT ILIKE '%role%' OR v_policy NOT ILIKE '%seller%'
     OR v_policy NOT ILIKE '%active%' THEN
    RAISE EXCEPTION 'FAIL: Seller inbox SELECT policy is not scoped to the active owning Seller';
  END IF;
  IF has_any_column_privilege('authenticated','public.buyer_demand_inbox','INSERT')
     OR has_any_column_privilege('authenticated','public.buyer_demand_inbox','UPDATE')
     OR has_table_privilege('authenticated','public.buyer_demand_inbox','DELETE') THEN
    RAISE EXCEPTION 'FAIL: authenticated users have direct write access to Demand routing rows';
  END IF;
  RAISE NOTICE 'PASS: Seller inbox is owner-scoped and browser users cannot write routing rows';

  -- Offers can be submitted only by the active Seller to whom an open Demand was routed.
  SELECT with_check INTO v_policy FROM pg_policies
  WHERE schemaname='public' AND tablename='seller_offers'
    AND policyname='offers_approved_seller_inbox_insert';
  IF v_policy IS NULL OR v_policy NOT ILIKE '%seller_id%' OR v_policy NOT ILIKE '%auth.uid%'
     OR v_policy NOT ILIKE '%buyer_demand_inbox%' OR v_policy NOT ILIKE '%demand_status%'
     OR v_policy NOT ILIKE '%open%' THEN
    RAISE EXCEPTION 'FAIL: quotation INSERT policy does not require Seller-owned open inbox Demand';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.seller_offers'::regclass
      AND contype='u'
      AND pg_get_constraintdef(oid) ILIKE '%demand_id%'
      AND pg_get_constraintdef(oid) ILIKE '%seller_id%'
  ) THEN
    RAISE EXCEPTION 'FAIL: one-quotation-per-Seller-per-Demand uniqueness constraint missing';
  END IF;
  RAISE NOTICE 'PASS: quotation INSERT is inbox-scoped and one offer per Seller/Demand';

  -- Required date remains mandatory and non-past.
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid='public.buyer_demands'::regclass
      AND attname='required_date' AND attnotnull
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.buyer_demands'::regclass
      AND contype='c'
      AND pg_get_constraintdef(oid) ILIKE '%required_date%'
      AND pg_get_constraintdef(oid) ILIKE '%current_date%'
  ) THEN
    RAISE EXCEPTION 'FAIL: required_date is not mandatory and/or non-past constrained';
  END IF;
  RAISE NOTICE 'PASS: required_date is NOT NULL and cannot be earlier than current_date';

  -- Both routing functions must match taxonomy and approved business, without account sale-type gates.
  FOREACH v_col IN ARRAY ARRAY[
    'private.route_new_buyer_demand_to_sellers()',
    'private.route_new_approved_product_to_open_demands()'
  ] LOOP
    IF to_regprocedure(v_col) IS NULL THEN
      RAISE EXCEPTION 'FAIL: routing function missing: %',v_col;
    END IF;
    SELECT pg_get_functiondef(to_regprocedure(v_col)) INTO v_def;
    IF v_def NOT ILIKE '%category%' OR v_def NOT ILIKE '%subcategory%'
       OR v_def NOT ILIKE '%listing_status%' OR v_def NOT ILIKE '%approved%'
       OR v_def NOT ILIKE '%public_businesses%' OR v_def NOT ILIKE '%account_status%' THEN
      RAISE EXCEPTION 'FAIL: routing function lacks approved product taxonomy/business eligibility: %',v_col;
    END IF;
    IF v_def ILIKE '%buyer_category%' OR v_def ILIKE '%seller_categories%' OR v_def ILIKE '%market_category%' THEN
      RAISE EXCEPTION 'FAIL: routing function contains account or product sale-type gate: %',v_col;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid=to_regprocedure(v_col) AND p.prosecdef
        AND p.proconfig @> ARRAY['search_path=""']
    ) THEN
      RAISE EXCEPTION 'FAIL: routing function must be SECURITY DEFINER with empty search_path: %',v_col;
    END IF;
    IF has_function_privilege('anon',to_regprocedure(v_col),'EXECUTE')
       OR has_function_privilege('authenticated',to_regprocedure(v_col),'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL: client role can directly execute trigger-only routing function: %',v_col;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS: Demand routing matches category/subcategory + approved business; no sale-type gate; trigger functions are private';

  RAISE NOTICE '=== B-03 DEMAND PRIVACY / ROUTING CATALOG AUDIT PASSED ===';
END
$audit$;

ROLLBACK;
\echo '=== READ-ONLY B-03 AUDIT FINISHED; NO DATABASE CHANGES MADE ==='
