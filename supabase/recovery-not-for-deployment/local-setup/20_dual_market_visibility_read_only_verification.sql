-- NEXORA DUAL-MARKET VISIBILITY VERIFICATION
-- READ-ONLY LOCAL VERIFICATION ONLY. NOT A MIGRATION. NOT DEPLOYABLE.
-- Safe target: local PostgreSQL database nexora_test ONLY.
-- The companion fixture 21 creates a deliberately LIMITED visibility schema.
-- This script checks catalog policy/column boundaries and optional role counts.
-- It does NOT validate the full Marketplace, Demand, Inquiry, Order, quotations,
-- listing-edit RPCs, hosted Supabase Auth/JWT/PostgREST, Storage, Realtime or MFA.

\set ON_ERROR_STOP on
\pset pager off
\echo '=== NEXORA DUAL-MARKET READ-ONLY VERIFICATION ==='

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected local database nexora_test, connected to %', current_database();
  END IF;
  IF to_regprocedure('auth.uid()') IS NULL OR to_regprocedure('auth.jwt()') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: local Supabase compatibility helpers are missing';
  END IF;
END
$guard$;

BEGIN READ ONLY;

SELECT
  to_regclass('public.profiles') IS NOT NULL
  AND to_regclass('public.products') IS NOT NULL
  AND to_regclass('public.public_businesses') IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='products' AND column_name='market_category')
  AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='products' AND column_name='subcategory')
  AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='products' AND column_name='minimum_order_quantity')
  AS visibility_schema_ready
\gset

\if :visibility_schema_ready
  \echo 'Visibility schema detected. Running focused catalog checks.'

  SELECT CASE WHEN bool_and(c.relrowsecurity) THEN 'PASS' ELSE 'FAIL' END AS result,
    'RLS enabled on profiles/products/public_businesses/business_profiles where present' AS check_name
  FROM (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relname IN ('profiles','products','public_businesses','business_profiles')
          AND c.relkind='r') c;

  SELECT CASE WHEN a.attnotnull AND d.adbin IS NULL
    AND EXISTS (SELECT 1 FROM pg_constraint co WHERE co.conrelid=a.attrelid AND co.contype='c'
      AND pg_get_constraintdef(co.oid) ILIKE '%market_category%'
      AND pg_get_constraintdef(co.oid) ILIKE '%wholesale%'
      AND pg_get_constraintdef(co.oid) ILIKE '%retail%')
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'products.market_category is NOT NULL, has no default, and allows wholesale/retail' AS check_name
  FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attrelid='public.products'::regclass AND a.attname='market_category' AND NOT a.attisdropped;

  SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='products' AND policyname='products_public_approved_read'
      AND cmd='SELECT' AND roles @> ARRAY['anon']::name[] AND coalesce(qual,'') ILIKE '%approved%')
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'Anonymous approved-product SELECT policy exists' AS check_name;

  SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='products' AND policyname='products_owner_approved_or_admin_read'
      AND cmd='SELECT' AND roles @> ARRAY['authenticated']::name[]
      AND coalesce(qual,'') ILIKE '%approved%'
      AND coalesce(qual,'') NOT ILIKE '%buyer_category%'
      AND coalesce(qual,'') NOT ILIKE '%seller_categories%'
      AND coalesce(qual,'') NOT ILIKE '%market_category%')
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'Authenticated product SELECT policy has no account/product sale-type visibility gate' AS check_name;

  SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='public_businesses' AND policyname='public_businesses_anon_read'
      AND cmd='SELECT' AND roles @> ARRAY['anon']::name[])
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'Anonymous public-business projection policy exists' AS check_name;

  SELECT CASE WHEN
    has_column_privilege('anon','public.products','id','SELECT')
    AND has_column_privilege('anon','public.products','product_name','SELECT')
    AND has_column_privilege('anon','public.products','market_category','SELECT')
    AND has_column_privilege('anon','public.products','listing_status','SELECT')
    AND has_column_privilege('anon','public.products','business_id','SELECT')
    AND has_column_privilege('anon','public.products','subcategory','SELECT')
    AND has_column_privilege('anon','public.products','minimum_order_quantity','SELECT')
    AND NOT has_column_privilege('anon','public.products','seller_id','SELECT')
    AND NOT has_column_privilege('anon','public.products','admin_note','SELECT')
    AND NOT has_column_privilege('anon','public.products','reviewed_by','SELECT')
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'Anonymous product columns are limited to public listing data' AS check_name;

  SELECT CASE WHEN
    has_column_privilege('anon','public.public_businesses','business_id','SELECT')
    AND has_column_privilege('anon','public.public_businesses','display_name','SELECT')
    AND has_column_privilege('anon','public.public_businesses','country','SELECT')
    AND has_column_privilege('anon','public.public_businesses','city','SELECT')
    AND NOT has_column_privilege('anon','public.public_businesses','seller_id','SELECT')
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'Anonymous public-business columns exclude Seller identity' AS check_name;

  \echo 'RPC/source checks: SKIP in the limited fixture; inspect actual staged migration definitions separately.'
  SELECT 'SKIP' AS result, 'Inquiry / Order / Demand routing / listing edit RPCs are not installed in this fixture' AS check_name;

  SELECT count(*)::bigint AS anon_approved_count FROM public.products p
    WHERE p.listing_status='approved' AND EXISTS
      (SELECT 1 FROM public.public_businesses b WHERE b.business_id=p.business_id) \gset
  \echo 'Anonymous visitor approved listings: ' :anon_approved_count

  SELECT market_category,count(*) AS approved_count FROM public.products p
    WHERE p.listing_status='approved' AND EXISTS
      (SELECT 1 FROM public.public_businesses b WHERE b.business_id=p.business_id)
    GROUP BY market_category ORDER BY market_category;

  SELECT EXISTS (SELECT 1 FROM public.profiles
    WHERE role='buyer' AND account_status='active') AS has_test_buyer \gset
  \if :has_test_buyer
    SELECT id::text AS test_buyer_uid FROM public.profiles
      WHERE role='buyer' AND account_status='active' ORDER BY created_at LIMIT 1 \gset
    SET LOCAL ROLE authenticated;
    SELECT set_config('request.jwt.claim.sub', :'test_buyer_uid', true);
    SELECT count(*)::bigint AS buyer_approved_count FROM public.products p
      WHERE p.listing_status='approved' AND EXISTS
        (SELECT 1 FROM public.public_businesses b WHERE b.business_id=p.business_id) \gset
    RESET ROLE;
    SELECT CASE WHEN :anon_approved_count::bigint=:buyer_approved_count::bigint THEN 'PASS'
      ELSE 'FAIL' END AS result, 'Anon and active Buyer approved listing counts match' AS check_name;
  \else
    \echo 'SKIP: no active Buyer profile exists.'
  \endif

  SELECT EXISTS (SELECT 1 FROM public.profiles
    WHERE role='seller' AND account_status='active') AS has_test_seller \gset
  \if :has_test_seller
    SELECT id::text AS test_seller_uid FROM public.profiles
      WHERE role='seller' AND account_status='active' ORDER BY created_at LIMIT 1 \gset
    SET LOCAL ROLE authenticated;
    SELECT set_config('request.jwt.claim.sub', :'test_seller_uid', true);
    SELECT count(*)::bigint AS seller_approved_count FROM public.products p
      WHERE p.listing_status='approved' AND EXISTS
        (SELECT 1 FROM public.public_businesses b WHERE b.business_id=p.business_id) \gset
    RESET ROLE;
    SELECT CASE WHEN :anon_approved_count::bigint=:seller_approved_count::bigint THEN 'PASS'
      ELSE 'FAIL' END AS result, 'Anon and active Seller approved listing counts match' AS check_name;
  \else
    \echo 'SKIP: no active Seller profile exists.'
  \endif

\else
  \echo 'SKIP: visibility schema is incomplete. Run 21_local_marketplace_visibility_fixture.sql first.'
\endif

ROLLBACK;
\echo '=== READ-ONLY VERIFICATION FINISHED; NO DATABASE CHANGES MADE ==='
