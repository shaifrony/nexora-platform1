-- NEXORA RECOVERY COPY — SQL body recovered from GitHub commit e468347c43e9a88d17504fca7c5ed8304aaa8374.
-- Live history version is 20261112153453; the repository source file is timestamped 20261112153000.
-- The body is source-recovered, but the original 153453 file/timestamp is not.
-- Do not execute as a new migration; it is already represented in the live schema.
DROP POLICY IF EXISTS demands_public_open_read ON public.buyer_demands;
CREATE POLICY demands_public_open_read
  ON public.buyer_demands
  FOR SELECT TO anon
  USING (demand_status = 'open');
GRANT SELECT (
  id, demand_code, product_name, category, description, specifications_quality,
  required_quantity, budget, currency, destination_country, destination_city,
  required_date, demand_status, created_at
) ON public.buyer_demands TO anon;
