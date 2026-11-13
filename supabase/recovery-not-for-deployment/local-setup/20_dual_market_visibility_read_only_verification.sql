-- NEXORA DUAL-MARKET VISIBILITY VERIFICATION
-- READ-ONLY LOCAL VERIFICATION ONLY. NOT A MIGRATION. NOT DEPLOYABLE.
-- Safe target: local PostgreSQL database nexora_test ONLY.
-- Checks: public approved listing visibility, safe anon columns, universal
-- authenticated Buyer visibility, sale-type constraints, and category-free
-- Inquiry / Order / Demand routing definitions.
-- This script makes NO schema changes and inserts NO test data.
-- It does not emulate hosted Supabase Auth, PostgREST, JWT validation or MFA.

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
  AND to_regclass('public.business_profiles') IS NOT NULL
  AND to_regclass('public.buyer_demands') IS NOT NULL
  AND to_regclass('public.buyer_demand_inbox') IS NOT NULL
  AND to_regclass('public.seller_offers') IS NOT NULL
  AND to_regclass('public.commerce_orders') IS NOT NULL
  AS marketplace_schema_ready
\gset

\if :marketplace_schema_ready
  \echo 'Marketplace schema detected. Running catalog and role-scoped checks.'

  -- A. Required RLS and sale-type schema.
  SELECT
    CASE WHEN c.relrowsecurity THEN 'PASS' ELSE 'FAIL' END AS result,
    'RLS enabled: '||n.nspname||'.'||c.relname AS check_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE (n.nspname,c.relname) IN (
    ('public','profiles'),('public','products'),('public','public_businesses'),
    ('public','business_profiles'),('public','buyer_demands'),
    ('public','buyer_demand_inbox'),('public','seller_offers'),
    ('public','commerce_orders')
  )
  ORDER BY c.relname;

  SELECT
    CASE WHEN a.attnotnull AND d.adbin IS NULL
      AND EXISTS (
        SELECT 1 FROM pg_constraint co
        WHERE co.conrelid=a.attrelid AND co.contype='c'
          AND pg_get_constraintdef(co.oid) ILIKE '%market_category%'
          AND pg_get_constraintdef(co.oid) ILIKE '%wholesale%'
          AND pg_get_constraintdef(co.oid) ILIKE '%retail%'
      )
      THEN 'PASS' ELSE 'FAIL' END AS result,
    'products.market_category is NOT NULL, has no default, and allows wholesale/retail'
      AS check_name
  FROM pg_attribute a
  LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attrelid='public.products'::regclass
    AND a.attname='market_category' AND NOT a.attisdropped;

  SELECT
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE buyer_category IS NOT NULL
         OR coalesce(cardinality(seller_categories),0)<>0
    ) THEN 'PASS' ELSE 'FAIL' END AS result,
    'Legacy profile market categories are NULL/empty' AS check_name;

  -- B. Required policy definitions: visibility is independent of sale type.
  SELECT
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename='products'
        AND policyname='products_public_approved_read'
        AND cmd='SELECT' AND roles @> ARRAY['anon']::name[]
        AND coalesce(qual,'') ILIKE '%approved%'
    ) THEN 'PASS' ELSE 'FAIL' END AS result,
    'Anonymous approved-product SELECT policy exists' AS check_name;

  SELECT
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename='products'
        AND policyname='products_owner_approved_or_admin_read'
        AND cmd='SELECT' AND roles @> ARRAY['authenticated']::name[]
        AND coalesce(qual,'') ILIKE '%approved%'
        AND coalesce(qual,'') NOT ILIKE '%buyer_category%'
        AND coalesce(qual,'') NOT ILIKE '%seller_categories%'
        AND coalesce(qual,'') NOT ILIKE '%market_category%'
    ) THEN 'PASS' ELSE 'FAIL' END AS result,
    'Authenticated product SELECT policy has no sale-type visibility gate' AS check_name;

  SELECT
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename='public_businesses'
        AND policyname='public_businesses_anon_read'
        AND cmd='SELECT' AND roles @> ARRAY['anon']::name[]
    ) THEN 'PASS' ELSE 'FAIL' END AS result,
    'Anonymous public-business projection policy exists' AS check_name;

  -- C. Anonymous column boundary: safe listing fields are readable; sensitive
  -- ownership and review fields are not exposed through the anon role.
  SELECT
    CASE WHEN
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

  SELECT
    CASE WHEN
      has_column_privilege('anon','public.public_businesses','business_id','SELECT')
      AND has_column_privilege('anon','public.public_businesses','display_name','SELECT')
      AND has_column_privilege('anon','public.public_businesses','country','SELECT')
      AND has_column_privilege('anon','public.public_businesses','city','SELECT')
      AND NOT has_column_privilege('anon','public.public_businesses','seller_id','SELECT')
      THEN 'PASS' ELSE 'FAIL' END AS result,
    'Anonymous public-business columns exclude seller identity' AS check_name;

  -- D. RPC and Demand routing source checks.
  SELECT
    CASE WHEN pg_get_functiondef(
      'private.create_product_inquiry(uuid,text)'::regprocedure
    ) !~* 'buyer_category|seller_categories|market_category'
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'Product Inquiry RPC has no Buyer/Seller market-category restriction' AS check_name;

  SELECT
    CASE WHEN pg_get_functiondef(
      'private.create_commerce_order(text,uuid,numeric,text,text)'::regprocedure
    ) !~* 'buyer_category|seller_categories'
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'Latest Product Order RPC has no Buyer/Seller account-category restriction' AS check_name;

  SELECT
    CASE WHEN
      pg_get_functiondef('private.route_new_buyer_demand_to_sellers()'::regprocedure)
        !~* 'buyer_category|seller_categories'
      AND
      pg_get_functiondef('private.route_new_approved_product_to_open_demands()'::regprocedure)
        !~* 'buyer_category|seller_categories'
    THEN 'PASS' ELSE 'FAIL' END AS result,
    'Buyer Demand routing is independent of Buyer/Seller account categories' AS check_name;

  -- E. Role-scoped visibility smoke check. No rows are inserted or changed.
  -- A local active Buyer is selected only to set the compatibility helper claim.
  SELECT id::text AS test_buyer_uid
  FROM public.profiles
  WHERE role='buyer' AND account_status='active'
  ORDER BY created_at
  LIMIT 1
  \gset

  SET LOCAL ROLE anon;
  SELECT count(*)::bigint AS anon_approved_count
  FROM public.products p
  WHERE p.listing_status='approved'
    AND EXISTS (
      SELECT 1 FROM public.public_businesses b
      WHERE b.business_id=p.business_id
    )
  \gset
  RESET ROLE;
  \echo 'Anonymous visitor approved listings: ' :anon_approved_count

  SELECT market_category,count(*) AS approved_count
  FROM public.products p
  WHERE p.listing_status='approved'
    AND EXISTS (SELECT 1 FROM public.public_businesses b WHERE b.business_id=p.business_id)
  GROUP BY market_category
  ORDER BY market_category;

  \if :{?test_buyer_uid}
    SET LOCAL ROLE authenticated;
    SELECT set_config('request.jwt.claim.sub', :'test_buyer_uid', true);
    SELECT count(*)::bigint AS buyer_approved_count
    FROM public.products p
    WHERE p.listing_status='approved'
      AND EXISTS (
        SELECT 1 FROM public.public_businesses b
        WHERE b.business_id=p.business_id
      )
    \gset
    RESET ROLE;
    \echo 'Authenticated Buyer approved listings: ' :buyer_approved_count
    SELECT
      CASE WHEN :anon_approved_count::bigint=:buyer_approved_count::bigint
        THEN 'PASS' ELSE 'FAIL' END AS result,
      'Anonymous and active Buyer see the same approved listing set' AS check_name;
    SELECT
      CASE WHEN :anon_approved_count::bigint>0 THEN 'DATA PRESENT'
        ELSE 'REVIEW: no approved public products exist yet' END AS sample_data_status;
  \else
    \echo 'SKIP: no active Buyer profile exists for authenticated visibility smoke check.'
  \endif

\else
  \echo 'SKIP: marketplace schema is incomplete. No marketplace queries were executed.'
  \echo 'Apply/rehearse the complete marketplace schema on an isolated local database first.'
\endif

ROLLBACK;
\echo '=== READ-ONLY VERIFICATION FINISHED; NO DATABASE CHANGES MADE ==='
