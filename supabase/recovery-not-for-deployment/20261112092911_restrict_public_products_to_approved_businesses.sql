-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from current pg_policies definition.
-- Do not execute without isolated RLS tests and approval.
BEGIN;
DROP POLICY IF EXISTS products_public_approved_select ON public.products;
CREATE POLICY products_public_approved_select
  ON public.products FOR SELECT TO anon
  USING (listing_status = 'approved' AND public.is_public_business(business_id));
COMMIT;
