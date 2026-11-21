-- NEXORA LOCAL FOUNDATION DEEP-DIAGNOSTIC
-- READ ONLY. SAFE TARGET: nexora_test ONLY.
-- NOT A MIGRATION. DO NOT RUN AGAINST HOSTED/PRODUCTION SUPABASE.
\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %', current_database();
  END IF;
  IF to_regclass('public.profiles') IS NULL
     OR to_regclass('public.role_requests') IS NULL
     OR to_regclass('public.profile_change_requests') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: local foundation fixture is not present';
  END IF;
END
$guard$;

BEGIN READ ONLY;

\echo
\echo '=== 1. LOCAL ROLE ATTRIBUTES ==='
SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls
FROM pg_roles
WHERE rolname IN (current_user, session_user, 'anon', 'authenticated', 'service_role', 'postgres')
ORDER BY rolname;

\echo
\echo '=== 2. BOTH REVIEW POLICIES, FULL EXPRESSIONS ==='
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('role_requests','profile_change_requests')
ORDER BY tablename, policyname;

\echo
\echo '=== 3. REQUEST TABLE PRIVILEGES ==='
SELECT
  table_name,
  grantee,
  privilege_type,
  is_grantable
FROM information_schema.role_table_grants
WHERE table_schema='public'
  AND table_name IN ('role_requests','profile_change_requests','profiles','admin_audit_logs')
ORDER BY table_name, grantee, privilege_type;

\echo
\echo '=== 4. AUDIT LOG POLICIES ==='
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname='public' AND tablename='admin_audit_logs'
ORDER BY policyname;

\echo
\echo '=== 5. FUNCTION OWNERS, SECURITY, SEARCH PATH AND EXECUTE ACL ==='
SELECT
  n.nspname,
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_get_userbyid(p.proowner) AS function_owner,
  p.prosecdef AS security_definer,
  p.proconfig AS function_settings,
  p.proacl AS function_acl,
  has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname='public' AND p.proname IN ('is_nexora_admin','handle_new_user'))
   OR (n.nspname='private' AND p.proname IN (
      'is_nexora_super_admin','has_nexora_permission','protect_profile_updates'
   ))
ORDER BY n.nspname,p.proname;

\echo
\echo '=== 6. FUNCTION SOURCE: SECURITY DEFINER FUNCTIONS ONLY ==='
SELECT
  n.nspname || '.' || p.proname || '(' ||
  pg_get_function_identity_arguments(p.oid) || ')' AS function_name,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prosecdef=true
  AND ((n.nspname='public' AND p.proname IN ('is_nexora_admin','handle_new_user'))
    OR (n.nspname='private' AND p.proname IN ('is_nexora_super_admin','has_nexora_permission')))
ORDER BY n.nspname,p.proname;

\echo
\echo '=== 7. FOUNDATION TABLE OWNERS AND RLS FLAGS ==='
SELECT
  c.relname AS table_name,
  pg_get_userbyid(c.relowner) AS table_owner,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
AND c.relname IN (
  'profiles','role_requests','profile_change_requests','admin_staff',
  'admin_departments','admin_permission_catalog','admin_permission_grants',
  'admin_audit_logs','porter_account_reviews'
)
ORDER BY c.relname;

\echo
\echo '=== 8. AUDIT LOG TRIGGERS ==='
SELECT
  t.tgname,
  pg_get_triggerdef(t.oid) AS trigger_definition,
  t.tgenabled
FROM pg_trigger t
WHERE t.tgrelid='public.admin_audit_logs'::regclass
  AND NOT t.tgisinternal
ORDER BY t.tgname;

ROLLBACK;
\echo
\echo '=== READ-ONLY LOCAL DIAGNOSTIC COMPLETE ==='
