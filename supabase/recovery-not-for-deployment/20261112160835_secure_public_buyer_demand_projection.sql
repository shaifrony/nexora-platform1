-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from current pg_get_viewdef, reloptions and view grants.
-- Exposes only open-demand fields and omits buyer_id/private identity.
-- Do not execute without isolated view/RLS tests and approval.
BEGIN;
CREATE OR REPLACE VIEW public.public_buyer_demands
WITH (security_invoker = true)
AS
SELECT
  id, demand_code, product_name, category, description, specifications_quality,
  required_quantity, budget, currency, destination_country, destination_city,
  required_date, demand_status, created_at
FROM public.buyer_demands
WHERE demand_status = 'open';
GRANT SELECT ON public.public_buyer_demands TO anon, authenticated;
COMMIT;
