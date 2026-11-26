-- Run only against a fresh disposable PostgreSQL database. Not a Supabase integration test.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN EXECUTE 'CREATE ROLE anon NOLOGIN'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN EXECUTE 'CREATE ROLE authenticated NOLOGIN'; END IF;
END $$;
CREATE SCHEMA private;
CREATE SCHEMA auth;
GRANT USAGE ON SCHEMA auth TO authenticated;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
CREATE TABLE public.products (
  id uuid PRIMARY KEY, seller_id uuid NOT NULL,
  listing_status text NOT NULL CHECK (listing_status IN ('pending','approved','rejected','suspended')),
  product_name text NOT NULL, business_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.commerce_orders (
  id uuid PRIMARY KEY, listing_type text NOT NULL CHECK (listing_type IN ('product','service')),
  listing_id uuid NOT NULL, buyer_id uuid NOT NULL, seller_id uuid NOT NULL,
  quantity numeric(18,3) NOT NULL, unit_price numeric(18,2) NOT NULL,
  currency text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY products_owner_read ON public.products FOR SELECT TO authenticated
  USING (seller_id = (SELECT auth.uid()));
CREATE POLICY products_owner_pending_insert ON public.products FOR INSERT TO authenticated
  WITH CHECK (seller_id = (SELECT auth.uid()) AND listing_status = 'pending');
CREATE POLICY products_owner_pending_update ON public.products FOR UPDATE TO authenticated
  USING (seller_id = (SELECT auth.uid()) AND listing_status = 'pending')
  WITH CHECK (seller_id = (SELECT auth.uid()) AND listing_status = 'pending');
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT ON public.products TO authenticated;
GRANT UPDATE (product_name) ON public.products TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.commerce_orders TO authenticated;
INSERT INTO public.products(id,seller_id,listing_status,product_name,business_id) VALUES
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','approved','Legacy Approved','30000000-0000-0000-0000-000000000001'),
('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','pending','Legacy Pending','30000000-0000-0000-0000-000000000001');
INSERT INTO public.commerce_orders(id,listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency) VALUES
('40000000-0000-0000-0000-000000000001','product','10000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',1,10,'BDT'),
('40000000-0000-0000-0000-000000000002','service','60000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',1,10,'BDT');
\ir 31_dual_listing_market_category_recovery_candidate.sql
DO $$
DECLARE v text;
BEGIN
  SELECT market_category INTO v FROM public.products WHERE id='10000000-0000-0000-0000-000000000001';
  IF v <> 'legacy_unclassified' THEN RAISE EXCEPTION 'legacy product backfill failed'; END IF;
  SELECT market_category_snapshot INTO v FROM public.commerce_orders WHERE id='40000000-0000-0000-0000-000000000001';
  IF v <> 'legacy_unclassified' THEN RAISE EXCEPTION 'existing product order snapshot backfill failed'; END IF;
  SELECT market_category_snapshot INTO v FROM public.commerce_orders WHERE id='40000000-0000-0000-0000-000000000002';
  IF v IS NOT NULL THEN RAISE EXCEPTION 'service order snapshot must be null'; END IF;
END $$;
SET ROLE authenticated;
SET request.jwt.claim.sub = '20000000-0000-0000-0000-000000000001';
INSERT INTO public.products(id,seller_id,listing_status,product_name,business_id,market_category)
VALUES ('10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','pending','New Wholesale','30000000-0000-0000-0000-000000000001','wholesale');
UPDATE public.products SET market_category='retail' WHERE id='10000000-0000-0000-0000-000000000002';
UPDATE public.products SET market_category='retail' WHERE id='10000000-0000-0000-0000-000000000001';
RESET ROLE;
DO $$
DECLARE v text;
BEGIN
  SELECT market_category INTO v FROM public.products WHERE id='10000000-0000-0000-0000-000000000002';
  IF v <> 'retail' THEN RAISE EXCEPTION 'pending seller classification failed'; END IF;
  SELECT market_category INTO v FROM public.products WHERE id='10000000-0000-0000-0000-000000000001';
  IF v <> 'legacy_unclassified' THEN RAISE EXCEPTION 'approved listing changed through RLS'; END IF;
  BEGIN
    INSERT INTO public.products(id,seller_id,listing_status,product_name,business_id)
    VALUES ('10000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000001','pending','Missing Type','30000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'unclassified new listing unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE public.products SET market_category='retail' WHERE id='10000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'approved listing type mutation unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
UPDATE public.products SET listing_status='approved' WHERE id='10000000-0000-0000-0000-000000000003';
INSERT INTO public.commerce_orders(id,listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency,market_category_snapshot)
VALUES ('40000000-0000-0000-0000-000000000003','product','10000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',1,10,'BDT','retail');
DO $$
DECLARE v text;
BEGIN
  SELECT market_category_snapshot INTO v FROM public.commerce_orders WHERE id='40000000-0000-0000-0000-000000000003';
  IF v <> 'wholesale' THEN RAISE EXCEPTION 'order snapshot was not derived from listing'; END IF;
  BEGIN
    UPDATE public.commerce_orders SET market_category_snapshot='retail' WHERE id='40000000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'order snapshot mutation unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
SELECT 'PASS: market category backfill, RLS, insert guard, approved immutability and order snapshot checks' AS result;
