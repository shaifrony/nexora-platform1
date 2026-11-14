-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from current function definition and ACL.
-- The function must remain SECURITY INVOKER; do not change it to SECURITY DEFINER.
-- Do not execute without isolated RLS tests and approval.
BEGIN;
CREATE OR REPLACE FUNCTION public.is_public_business(p_business_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.public_businesses b
    WHERE b.business_id = p_business_id
  );
$function$;
REVOKE ALL ON FUNCTION public.is_public_business(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_public_business(uuid) TO anon, authenticated;
COMMIT;
