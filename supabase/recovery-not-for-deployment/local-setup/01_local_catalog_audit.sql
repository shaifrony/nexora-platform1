-- NEXORA local catalog audit (read-only; no application migrations are applied)
-- SAFE TARGET: local database nexora_test ONLY.
-- This audit checks the compatibility scaffold and inventories any NEXORA
-- objects already restored into this disposable database.
-- It does NOT prove Supabase Auth, Storage API, PostgREST, JWT, MFA/AAL2,
-- or production RLS behavior. It does NOT create or alter application objects.

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'Safety stop: expected nexora_test, connected to %', current_database();
  END IF;
END
$guard$;

BEGIN READ ONLY;

\echo
\echo '=== 1. Local runtime and compatibility prerequisites ==='
SELECT current_database() AS database_name,
       current_user AS connected_user,
       current_setting('server_version') AS postgres_version;

SELECT e.extname, e.extversion
FROM pg_extension e
WHERE e.extname IN ('pgcrypto', 'uuid-ossp')
ORDER BY e.extname;

SELECT r.rolname,
       r.rolcanlogin,
       r.rolbypassrls
FROM pg_roles r
WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
ORDER BY r.rolname;

SELECT n.nspname AS schema_name,
       to_regprocedure('auth.uid()') IS NOT NULL AS auth_uid_stub_present,
       to_regprocedure('auth.jwt()') IS NOT NULL AS auth_jwt_stub_present,
       to_regprocedure('auth.role()') IS NOT NULL AS auth_role_stub_present,
       to_regclass('auth.users') IS NOT NULL AS auth_users_fixture_present,
       to_regclass('storage.buckets') IS NOT NULL AS storage_buckets_fixture_present,
       to_regclass('storage.objects') IS NOT NULL AS storage_objects_fixture_present
FROM (VALUES ('auth'::text)) AS expected(nspname)
LEFT JOIN pg_namespace n ON n.nspname = expected.nspname;

\echo
\echo '=== 2. NEXORA application table inventory ==='
WITH expected(table_name) AS (
  VALUES
    ('profiles'), ('admin_staff'), ('admin_audit_logs'),
    ('business_profiles'), ('public_businesses'), ('products'),
    ('buyer_demands'), ('seller_offers'), ('porter_account_reviews'),
    ('transport_providers'), ('transport_vehicles')
)
SELECT e.table_name,
       CASE WHEN c.oid IS NULL THEN 'NOT RESTORED'
            ELSE 'PRESENT' END AS local_status,
       COALESCE(c.relrowsecurity, false) AS rls_enabled,
       COALESCE(c.relforcerowsecurity, false) AS rls_forced
FROM expected e
LEFT JOIN pg_class c
  ON c.relname = e.table_name
 AND c.relnamespace = 'public'::regnamespace
 AND c.relkind IN ('r','p','v','m')
ORDER BY e.table_name;

\echo
\echo '=== 3. Existing public-schema RLS policies ==='
SELECT schemaname, tablename, policyname, permissive,
       roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

\echo
\echo '=== 4. Existing public-schema constraints ==='
SELECT conrelid::regclass AS table_name,
       conname AS constraint_name,
       contype AS constraint_type,
       pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
ORDER BY conrelid::regclass::text, conname;

\echo
\echo '=== 5. Existing public-schema indexes ==='
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

\echo
\echo '=== 6. Existing public-schema non-system triggers ==='
SELECT event_object_table AS table_name,
       trigger_name,
       event_manipulation,
       action_timing,
       action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name, event_manipulation;

\echo
\echo '=== 7. Existing public/private application functions ==='
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer,
       p.proconfig AS function_settings
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public','private')
  AND p.prokind IN ('f','p')
ORDER BY n.nspname, p.proname, arguments;

\echo
\echo '=== Audit complete: inventory only; absent app tables mean schema has not been restored ==='
COMMIT;
