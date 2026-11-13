-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from current anonymous column privileges.
-- Dynamic revoke clears any prior per-column grants before applying the observed allowlist.
-- Do not execute without isolated permission tests and approval.
BEGIN;
REVOKE ALL PRIVILEGES ON TABLE public.products FROM anon;
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT column_name
    FROM information_schema.column_privileges
    WHERE table_schema='public' AND table_name='products' AND grantee='anon'
  LOOP
    EXECUTE format('REVOKE SELECT (%I) ON TABLE public.products FROM anon', r.column_name);
  END LOOP;
END $$;
GRANT SELECT (
  id, business_id, product_code, slug, product_name, category, image_urls,
  description, origin, specifications_quality, price, currency, price_unit,
  minimum_order_quantity, price_negotiable, listing_status, created_at
) ON public.products TO anon;
COMMIT;
