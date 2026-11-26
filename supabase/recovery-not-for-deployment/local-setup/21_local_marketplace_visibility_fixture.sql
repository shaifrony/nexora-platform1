-- NEXORA LOCAL MARKETPLACE VISIBILITY FIXTURE
-- PURPOSE: create only the minimum local schema needed to exercise the
-- dual-market public listing visibility and column-boundary catalog checks.
-- NOT a recovered schema, NOT a full Marketplace fixture, NOT deployable.
-- NEVER run against hosted Supabase or any database other than nexora_test.
-- Does not create sample users/listings and does not emulate Supabase services.

\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %', current_database();
  END IF;
  IF to_regclass('public.profiles') IS NULL
     OR to_regprocedure('auth.uid()') IS NULL
     OR to_regprocedure('auth.jwt()') IS NULL
     OR to_regprocedure('public.is_nexora_admin()') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: run the local foundation fixture first';
  END IF;
  IF to_regclass('public.products') IS NOT NULL
     OR to_regclass('public.public_businesses') IS NOT NULL
     OR to_regclass('public.business_profiles') IS NOT NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: Marketplace visibility objects already exist; inspect instead of overwriting';
  END IF;
END
$guard$;

BEGIN;

-- This is deliberately a small visibility test schema, not the full app schema.
CREATE TABLE public.business_profiles (
  business_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  country text NOT NULL,
  city text NOT NULL,
  sales_center_address text,
  approval_status text NOT NULL DEFAULT 'pending'
    CHECK (approval_status IN ('pending','approved','rejected','suspended')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.public_businesses (
  business_id uuid PRIMARY KEY REFERENCES public.business_profiles(business_id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  country text NOT NULL,
  city text NOT NULL
);

CREATE TABLE public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_code text NOT NULL UNIQUE DEFAULT ('NX-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  slug text NOT NULL UNIQUE,
  seller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  business_id uuid NOT NULL REFERENCES public.public_businesses(business_id) ON DELETE CASCADE,
  product_name text NOT NULL,
  category text NOT NULL,
  subcategory text NOT NULL,
  market_category text NOT NULL CHECK (market_category IN ('wholesale','retail')),
  image_urls text[] NOT NULL DEFAULT '{}'::text[],
  description text,
  origin text,
  specifications_quality text,
  price numeric(18,2) NOT NULL CHECK (price>0),
  currency text NOT NULL,
  minimum_order_quantity numeric(18,3) NOT NULL DEFAULT 1 CHECK (minimum_order_quantity>0),
  listing_status text NOT NULL DEFAULT 'pending'
    CHECK (listing_status IN ('pending','approved','rejected','suspended')),
  admin_note text,
  reviewed_by uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.business_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA public TO anon,authenticated;
GRANT SELECT (business_id,display_name,country,city) ON public.public_businesses TO anon,authenticated;
GRANT SELECT (id,product_code,slug,product_name,category,subcategory,market_category,
 image_urls,description,origin,specifications_quality,price,currency,
 minimum_order_quantity,listing_status,business_id,created_at)
 ON public.products TO anon;
GRANT SELECT ON public.products TO authenticated;

CREATE POLICY public_businesses_anon_read
 ON public.public_businesses FOR SELECT TO anon USING (true);
CREATE POLICY public_businesses_authenticated_read
 ON public.public_businesses FOR SELECT TO authenticated USING (true);

CREATE POLICY products_public_approved_read
 ON public.products FOR SELECT TO anon
 USING (listing_status='approved' AND EXISTS (
   SELECT 1 FROM public.public_businesses b WHERE b.business_id=products.business_id
 ));
CREATE POLICY products_owner_approved_or_admin_read
 ON public.products FOR SELECT TO authenticated
 USING (
   seller_id=(SELECT auth.uid())
   OR public.is_nexora_admin()
   OR (listing_status='approved' AND EXISTS (
     SELECT 1 FROM public.public_businesses b WHERE b.business_id=products.business_id
   ))
 );

COMMIT;

\echo 'LOCAL VISIBILITY FIXTURE CREATED.'
\echo 'Scope: business/product visibility schema and RLS catalog only.'
\echo 'No sample records inserted. Demand, quotation, order and RPC workflows are not represented.'
\echo 'Next: run 20_dual_market_visibility_read_only_verification.sql.'
