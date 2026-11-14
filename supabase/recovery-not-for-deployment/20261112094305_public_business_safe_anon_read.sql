-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from current public_businesses policy and anon column grants.
-- Do not execute without isolated RLS tests and approval.
BEGIN;
DROP POLICY IF EXISTS public_businesses_anon_read ON public.public_businesses;
CREATE POLICY public_businesses_anon_read
  ON public.public_businesses FOR SELECT TO anon USING (true);
REVOKE ALL PRIVILEGES ON TABLE public.public_businesses FROM anon;
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT column_name
    FROM information_schema.column_privileges
    WHERE table_schema='public' AND table_name='public_businesses' AND grantee='anon'
  LOOP
    EXECUTE format('REVOKE SELECT (%I) ON TABLE public.public_businesses FROM anon', r.column_name);
  END LOOP;
END $$;
GRANT SELECT (business_id, display_name, country, city)
  ON public.public_businesses TO anon;
COMMIT;
