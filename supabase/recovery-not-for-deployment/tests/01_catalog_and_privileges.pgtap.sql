-- NEXORA recovery-draft verification checks
-- NOT A MIGRATION. Keep this file outside supabase/migrations/.
-- Run ONLY against a disposable, isolated PostgreSQL/Supabase clone
-- after the schema under test has been restored.
-- Requires pgTAP. This suite inspects catalog/privilege state; it does not
-- create fixtures or mutate application tables.

BEGIN;
SELECT plan(15);

SELECT ok(
  has_column('public', 'products', 'seller_id'),
  'products.seller_id exists in the test schema'
);

SELECT ok(
  NOT has_column_privilege('anon', 'public.products', 'seller_id', 'SELECT'),
  'anon cannot read products.seller_id'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'products'
      AND policyname = 'products_public_approved_select'
  ),
  'approved-products public SELECT policy exists'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'products'
      AND policyname = 'products_public_approved_select'
      AND coalesce(qual, '') ILIKE '%listing_status%'
      AND coalesce(qual, '') ILIKE '%approved%'
      AND coalesce(qual, '') ILIKE '%is_public_business%'
  ),
  'approved-products policy checks listing status and public business'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'is_public_business'
      AND p.prosecdef = false
  ),
  'is_public_business is SECURITY INVOKER'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'is_public_business'
      AND coalesce(array_to_string(p.proconfig, ','), '') LIKE '%search_path=%'
      AND coalesce(array_to_string(p.proconfig, ','), '') LIKE '%search_path=""%'
  ),
  'is_public_business pins an empty search_path'
);

SELECT ok(
  has_function_privilege('anon', 'public.is_public_business(uuid)', 'EXECUTE'),
  'anon can execute the public-business predicate used by the public policy'
);

SELECT ok(
  has_column('public', 'buyer_demands', 'buyer_id'),
  'buyer_demands.buyer_id exists in the base table'
);

SELECT ok(
  NOT has_column_privilege('anon', 'public.buyer_demands', 'buyer_id', 'SELECT'),
  'anon cannot read buyer_demands.buyer_id'
);

SELECT ok(
  has_column_privilege('anon', 'public.buyer_demands', 'required_date', 'SELECT'),
  'anon can read the demand required_date field'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'buyer_demands'
      AND policyname = 'demands_public_open_read'
      AND coalesce(qual, '') ILIKE '%open%'
  ),
  'public demand policy is restricted to open demands'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'public_buyer_demands'
      AND c.relkind = 'v'
      AND coalesce(c.reloptions, ARRAY[]::text[]) @> ARRAY['security_invoker=true']
  ),
  'public_buyer_demands view uses security_invoker=true'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private'
      AND p.proname = 'is_nexora_super_admin'
      AND p.prosecdef = true
      AND coalesce(array_to_string(p.proconfig, ','), '') LIKE '%search_path=""%'
  ),
  'super-admin helper is SECURITY DEFINER with an empty search_path'
);

SELECT ok(
  NOT has_function_privilege('anon', 'private.is_nexora_super_admin()', 'EXECUTE'),
  'anon cannot execute the super-admin helper'
);

SELECT ok(
  has_function_privilege('authenticated', 'private.is_nexora_super_admin()', 'EXECUTE'),
  'authenticated has EXECUTE on the super-admin helper'
);

SELECT * FROM finish();
ROLLBACK;
