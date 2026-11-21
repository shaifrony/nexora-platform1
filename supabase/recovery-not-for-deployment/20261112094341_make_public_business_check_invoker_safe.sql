-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED as the final observed hardening state.
-- This explicitly keeps the public lookup SECURITY INVOKER with empty search_path.
-- Do not execute without isolated RLS tests and approval.
BEGIN;
ALTER FUNCTION public.is_public_business(uuid) SECURITY INVOKER;
ALTER FUNCTION public.is_public_business(uuid) SET search_path = '';
REVOKE ALL ON FUNCTION public.is_public_business(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_public_business(uuid) TO anon, authenticated;
COMMIT;
