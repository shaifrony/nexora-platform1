-- NEXORA CONCURRENCY TEST FIXTURE CLEANUP
-- LOCAL ONLY: nexora_test. Run only after both psql sessions are closed.
-- Deletes only the dedicated fixture IDs from file 17.
-- Dependency order matters: permission grants -> admin staff -> role request -> auth users.
\set ON_ERROR_STOP on
\pset pager off
DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test';
  END IF;
END
$guard$;
BEGIN;
DELETE FROM public.admin_audit_logs
WHERE target_id='32000000-0000-4000-8000-000000000001';
DELETE FROM public.role_requests
WHERE id='32000000-0000-4000-8000-000000000001';
DELETE FROM public.admin_permission_grants
WHERE admin_user_id='22000000-0000-4000-8000-000000000001';
DELETE FROM public.admin_staff
WHERE user_id='22000000-0000-4000-8000-000000000001';
DELETE FROM auth.users
WHERE id IN (
 '22000000-0000-4000-8000-000000000001',
 '22000000-0000-4000-8000-000000000002'
);
COMMIT;
SELECT CASE
 WHEN NOT EXISTS (SELECT 1 FROM auth.users WHERE id IN (
   '22000000-0000-4000-8000-000000000001',
   '22000000-0000-4000-8000-000000000002'
 )) AND NOT EXISTS (SELECT 1 FROM public.role_requests WHERE id='32000000-0000-4000-8000-000000000001')
 AND NOT EXISTS (SELECT 1 FROM public.admin_staff WHERE user_id='22000000-0000-4000-8000-000000000001')
 AND NOT EXISTS (SELECT 1 FROM public.admin_permission_grants WHERE admin_user_id='22000000-0000-4000-8000-000000000001')
 THEN 'CLEANED'
 ELSE 'CLEANUP CHECK REQUIRED'
END AS cleanup_status;
