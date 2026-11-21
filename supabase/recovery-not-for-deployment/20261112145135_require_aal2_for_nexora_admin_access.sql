-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from current private.is_nexora_super_admin() definition and ACL.
-- Requires AAL2 and an active super_admin staff identity linked to an active Admin profile.
-- Do not execute without isolated authentication/RLS tests and approval.
BEGIN;
CREATE OR REPLACE FUNCTION private.is_nexora_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT (SELECT auth.jwt()->>'aal') = 'aal2'
    AND EXISTS (
      SELECT 1
      FROM public.admin_staff s
      JOIN public.profiles p ON p.id = s.user_id
      WHERE s.user_id = (SELECT auth.uid())
        AND s.admin_level = 'super_admin'
        AND s.is_active = true
        AND p.role = 'admin'
        AND p.account_status = 'active'
    );
$function$;
REVOKE ALL ON FUNCTION private.is_nexora_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_nexora_super_admin() TO authenticated;
COMMIT;
