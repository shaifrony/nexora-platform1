-- NEXORA LOCAL FOUNDATION SECURITY & SCHEMA AUDIT
-- READ-ONLY CATALOG AUDIT. Does not modify schema or application data.
-- SAFE TARGET: local PostgreSQL database named nexora_test ONLY.
-- NOT a Supabase Auth/RLS/JWT/PostgREST/Storage/Realtime/MFA test.
-- Do not run against hosted Supabase or production.

\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %', current_database();
  END IF;
  IF to_regclass('public.profiles') IS NULL
     OR to_regclass('public.role_requests') IS NULL
     OR to_regclass('public.profile_change_requests') IS NULL
     OR to_regclass('public.admin_staff') IS NULL
     OR to_regclass('public.admin_departments') IS NULL
     OR to_regclass('public.admin_permission_catalog') IS NULL
     OR to_regclass('public.admin_permission_grants') IS NULL
     OR to_regclass('public.admin_audit_logs') IS NULL
     OR to_regclass('public.porter_account_reviews') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: expected all nine local foundation tables; inspect fixture state first';
  END IF;
END
$guard$;

BEGIN READ ONLY;

\echo ''
\echo '=== 1. TABLE RLS STATUS ==='
SELECT n.nspname AS schema_name, c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls,
       CASE
         WHEN NOT c.relrowsecurity THEN 'CRITICAL: RLS DISABLED'
         WHEN NOT c.relforcerowsecurity THEN 'REVIEW: table owner may bypass RLS'
         ELSE 'RLS + FORCE RLS'
       END AS finding
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r'
  AND c.relname IN ('profiles','role_requests','profile_change_requests',
    'admin_staff','admin_departments','admin_permission_catalog',
    'admin_permission_grants','admin_audit_logs','porter_account_reviews')
ORDER BY c.relname;

\echo ''
\echo '=== 2. RLS POLICY INVENTORY ==='
SELECT schemaname, tablename, policyname, permissive, roles, cmd,
       coalesce(qual,'<none>') AS using_expression,
       coalesce(with_check,'<none>') AS with_check_expression
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('profiles','role_requests','profile_change_requests',
    'admin_staff','admin_departments','admin_permission_catalog',
    'admin_permission_grants','admin_audit_logs','porter_account_reviews')
ORDER BY tablename, policyname;

\echo ''
\echo '=== 3. TABLE PRIVILEGES BY APPLICATION ROLE ==='
SELECT t.table_name, r.role_name,
       has_table_privilege(r.role_name, format('public.%I',t.table_name), 'SELECT') AS can_select,
       has_table_privilege(r.role_name, format('public.%I',t.table_name), 'INSERT') AS can_insert,
       has_table_privilege(r.role_name, format('public.%I',t.table_name), 'UPDATE') AS can_update,
       has_table_privilege(r.role_name, format('public.%I',t.table_name), 'DELETE') AS can_delete,
       has_table_privilege(r.role_name, format('public.%I',t.table_name), 'TRUNCATE') AS can_truncate
FROM (VALUES
 ('profiles'),('role_requests'),('profile_change_requests'),('admin_staff'),
 ('admin_departments'),('admin_permission_catalog'),('admin_permission_grants'),
 ('admin_audit_logs'),('porter_account_reviews')
) AS t(table_name)
CROSS JOIN (VALUES ('anon'),('authenticated'),('service_role')) AS r(role_name)
WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r.role_name)
ORDER BY t.table_name, r.role_name;

\echo ''
\echo '=== 4. UPDATE POLICY / TABLE GRANT CONSISTENCY ==='
SELECT p.tablename, p.policyname, p.roles,
       has_table_privilege('authenticated', format('public.%I',p.tablename), 'UPDATE')
         AS authenticated_has_update_grant,
       CASE WHEN has_table_privilege('authenticated', format('public.%I',p.tablename), 'UPDATE')
         THEN 'REVIEW: UPDATE policy and grant both exist; verify intended column controls'
         ELSE 'FINDING: UPDATE policy exists but authenticated has no UPDATE table grant'
       END AS finding
FROM pg_policies p
WHERE p.schemaname='public'
  AND p.cmd='UPDATE'
  AND p.tablename IN ('profiles','role_requests','profile_change_requests',
    'admin_staff','admin_departments','admin_permission_catalog',
    'admin_permission_grants','admin_audit_logs','porter_account_reviews')
ORDER BY p.tablename,p.policyname;

\echo ''
\echo '=== 5. FUNCTION SECURITY / EXECUTE EXPOSURE ==='
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_get_userbyid(p.proowner) AS owner_name,
       p.prosecdef AS security_definer,
       coalesce(array_to_string(p.proconfig, ', '), '<not set>') AS function_settings,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_can_execute,
       CASE
         WHEN p.prosecdef AND n.nspname='public'
           THEN 'REVIEW: SECURITY DEFINER function resides in public schema'
         WHEN p.prosecdef AND NOT EXISTS (
           SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) cfg
           WHERE cfg LIKE 'search_path=%'
         )
           THEN 'CRITICAL: SECURITY DEFINER has no pinned search_path'
         ELSE 'REVIEWED BY CATALOG ONLY'
       END AS finding
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname='public' AND p.proname IN ('is_nexora_admin','handle_new_user'))
   OR (n.nspname='private' AND p.proname IN
       ('is_nexora_super_admin','has_nexora_permission','protect_profile_updates'))
ORDER BY n.nspname,p.proname;

\echo ''
\echo '=== 6. PRIVATE SCHEMA ACCESS ==='
SELECT r.rolname AS role_name,
       has_schema_privilege(r.rolname,'private','USAGE') AS private_schema_usage,
       has_schema_privilege(r.rolname,'private','CREATE') AS private_schema_create
FROM pg_roles r
WHERE r.rolname IN ('anon','authenticated','service_role')
ORDER BY r.rolname;

\echo ''
\echo '=== 7. TRIGGER INVENTORY ==='
SELECT n.nspname AS schema_name, c.relname AS table_name,
       t.tgname AS trigger_name, t.tgenabled AS enabled_code,
       pg_get_triggerdef(t.oid,true) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE NOT t.tgisinternal
  AND ((n.nspname='public' AND c.relname IN
       ('profiles','role_requests','profile_change_requests','admin_staff',
        'admin_departments','admin_permission_catalog','admin_permission_grants',
        'admin_audit_logs','porter_account_reviews'))
       OR (n.nspname='auth' AND c.relname='users'))
ORDER BY n.nspname,c.relname,t.tgname;

\echo ''
\echo '=== 8. CONSTRAINT INVENTORY ==='
SELECT c.conrelid::regclass AS table_name,
       c.conname AS constraint_name,
       CASE c.contype
         WHEN 'p' THEN 'PRIMARY KEY'
         WHEN 'f' THEN 'FOREIGN KEY'
         WHEN 'u' THEN 'UNIQUE'
         WHEN 'c' THEN 'CHECK'
         WHEN 'x' THEN 'EXCLUSION'
         ELSE c.contype::text
       END AS constraint_type,
       pg_get_constraintdef(c.oid,true) AS definition,
       c.convalidated AS validated
FROM pg_constraint c
WHERE c.conrelid IN (
  'public.profiles'::regclass,'public.role_requests'::regclass,
  'public.profile_change_requests'::regclass,'public.admin_staff'::regclass,
  'public.admin_departments'::regclass,'public.admin_permission_catalog'::regclass,
  'public.admin_permission_grants'::regclass,'public.admin_audit_logs'::regclass,
  'public.porter_account_reviews'::regclass
)
ORDER BY c.conrelid::regclass::text,c.conname;

\echo ''
\echo '=== 9. INDEX INVENTORY ==='
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname='public'
  AND tablename IN ('profiles','role_requests','profile_change_requests',
    'admin_staff','admin_departments','admin_permission_catalog',
    'admin_permission_grants','admin_audit_logs','porter_account_reviews')
ORDER BY tablename,indexname;

\echo ''
\echo '=== 10. AUTOMATED FINDING SUMMARY ==='
WITH findings AS (
  SELECT 'RLS disabled' AS finding, count(*)::int AS issue_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r'
    AND c.relname IN ('profiles','role_requests','profile_change_requests',
      'admin_staff','admin_departments','admin_permission_catalog',
      'admin_permission_grants','admin_audit_logs','porter_account_reviews')
    AND NOT c.relrowsecurity
  UNION ALL
  SELECT 'RLS not forced (owner-bypass review)', count(*)::int
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r'
    AND c.relname IN ('profiles','role_requests','profile_change_requests',
      'admin_staff','admin_departments','admin_permission_catalog',
      'admin_permission_grants','admin_audit_logs','porter_account_reviews')
    AND c.relrowsecurity AND NOT c.relforcerowsecurity
  UNION ALL
  SELECT 'SECURITY DEFINER function in public', count(*)::int
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef
    AND p.proname IN ('is_nexora_admin','handle_new_user')
  UNION ALL
  SELECT 'UPDATE policy without authenticated UPDATE grant', count(*)::int
  FROM pg_policies p
  WHERE p.schemaname='public' AND p.cmd='UPDATE'
    AND p.tablename IN ('role_requests','profile_change_requests')
    AND NOT has_table_privilege('authenticated',format('public.%I',p.tablename),'UPDATE')
)
SELECT finding, issue_count,
       CASE WHEN issue_count=0 THEN 'PASS' ELSE 'REVIEW REQUIRED' END AS status
FROM findings
ORDER BY finding;

ROLLBACK;

\echo ''
\echo '=== LOCAL FOUNDATION CATALOG AUDIT COMPLETE — READ ONLY ==='
\echo 'Review all REVIEW REQUIRED findings; this is not a Supabase platform security certification.';
