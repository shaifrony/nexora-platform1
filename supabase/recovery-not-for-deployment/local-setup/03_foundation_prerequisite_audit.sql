-- NEXORA local foundation prerequisite audit
-- READ ONLY. SAFE TARGET: local database nexora_test ONLY.
-- This script does not create or modify application objects.
-- Run only after 00_bootstrap_supabase_compat.sql and 01_local_catalog_audit.sql.
\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'Safety stop: expected local database nexora_test, connected to %', current_database();
  END IF;
END
$guard$;

BEGIN READ ONLY;

SELECT
  current_database() AS database_name,
  current_setting('server_version') AS postgres_version,
  'READ ONLY — no schema changes' AS audit_mode;

WITH expected(table_name, column_name, source_note) AS (
  VALUES
    ('profiles','id','Referenced by core marketplace and Auth trigger'),
    ('profiles','full_name','Referenced by public identity projection and signup trigger'),
    ('profiles','role','Referenced by marketplace, Porter and Admin workflows'),
    ('profiles','account_status','Referenced by onboarding and approval gates'),
    ('profiles','buyer_category','Referenced by market-category and Porter registration migrations'),
    ('profiles','seller_categories','Referenced by market-category and Porter registration migrations'),
    ('profiles','updated_at','Referenced by officer and Porter review functions'),

    ('role_requests','user_id','Referenced by marketplace RLS and transport role constraints'),
    ('role_requests','requested_role','Referenced by marketplace RLS and transport role constraints'),
    ('role_requests','status','Referenced by marketplace RLS'),

    ('profile_change_requests','user_id','Referenced by marketplace RLS'),
    ('profile_change_requests','requested_full_name','Referenced by marketplace RLS'),
    ('profile_change_requests','status','Referenced by marketplace RLS'),
    ('profile_change_requests','admin_note','Referenced by marketplace RLS'),
    ('profile_change_requests','reviewed_by','Referenced by indexes and review workflow'),
    ('profile_change_requests','reviewed_at','Referenced by indexes and review workflow'),

    ('admin_staff','user_id','Referenced by Admin, Porter and transport review workflows'),
    ('admin_staff','admin_code','Referenced by Admin audit and permission workflows'),
    ('admin_staff','admin_level','Referenced by Director and officer workflows'),
    ('admin_staff','department_key','Referenced by officer management'),
    ('admin_staff','is_active','Referenced by all privileged review workflows'),
    ('admin_staff','created_by','Referenced by officer management'),
    ('admin_staff','staff_email','Added by centralized officer migration'),
    ('admin_staff','position_key','Added by centralized officer migration'),
    ('admin_staff','reports_to_user_id','Added by centralized officer migration'),

    ('admin_departments','department_key','Referenced by centralized officer management'),
    ('admin_departments','is_assignable','Referenced by centralized officer management'),
    ('admin_permission_catalog','permission_key','Referenced by permission validation'),
    ('admin_permission_catalog','department_key','Referenced by permission validation'),
    ('admin_permission_catalog','is_sensitive','Referenced by permission validation'),
    ('admin_permission_grants','admin_user_id','Referenced by permission management'),
    ('admin_permission_grants','permission_key','Referenced by permission management'),
    ('admin_permission_grants','is_allowed','Referenced by permission checks'),
    ('admin_permission_grants','granted_by','Referenced by officer management'),

    ('admin_audit_logs','actor_user_id','Referenced by Porter, transport and officer review'),
    ('admin_audit_logs','actor_admin_code','Referenced by Porter, transport and officer review'),
    ('admin_audit_logs','action_key','Referenced by Porter, transport and officer review'),
    ('admin_audit_logs','target_type','Referenced by Porter, transport and officer review'),
    ('admin_audit_logs','target_id','Referenced by Porter, transport and officer review'),
    ('admin_audit_logs','reason','Referenced by Porter, transport and officer review'),
    ('admin_audit_logs','details','Referenced by Porter, transport and officer review')
),
checks AS (
  SELECT e.table_name, e.column_name, e.source_note,
         to_regclass(format('public.%I', e.table_name)) IS NOT NULL AS table_exists,
         EXISTS (
           SELECT 1
           FROM pg_attribute a
           JOIN pg_class c ON c.oid = a.attrelid
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname='public'
             AND c.relname=e.table_name
             AND a.attname=e.column_name
             AND a.attnum > 0
             AND NOT a.attisdropped
         ) AS column_exists
  FROM expected e
)
SELECT
  table_name,
  column_name,
  CASE
    WHEN NOT table_exists THEN 'TABLE MISSING'
    WHEN NOT column_exists THEN 'COLUMN MISSING'
    ELSE 'PRESENT'
  END AS status,
  source_note
FROM checks
ORDER BY
  CASE WHEN NOT table_exists OR NOT column_exists THEN 0 ELSE 1 END,
  table_name, column_name;

WITH expected_functions(signature, source_note) AS (
  VALUES
    ('public.is_nexora_admin()','Core marketplace RLS and Admin authorization'),
    ('private.has_nexora_permission(text)','Transport, Porter and Admin permission checks'),
    ('private.is_nexora_super_admin()','Director-only officer management'),
    ('public.handle_new_user()','Supabase Auth signup trigger function')
)
SELECT
  signature,
  CASE WHEN to_regprocedure(signature) IS NULL THEN 'FUNCTION MISSING' ELSE 'PRESENT' END AS status,
  source_note
FROM expected_functions
ORDER BY signature;

SELECT
  schema_name,
  CASE WHEN EXISTS (SELECT 1 FROM pg_namespace WHERE nspname=schema_name)
       THEN 'PRESENT' ELSE 'MISSING' END AS status
FROM (VALUES ('auth'),('private'),('storage')) s(schema_name)
ORDER BY schema_name;

SELECT
  role_name,
  CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname=role_name)
       THEN 'PRESENT' ELSE 'MISSING' END AS status
FROM (VALUES ('anon'),('authenticated'),('service_role')) r(role_name)
ORDER BY role_name;

COMMIT;

\echo '=== Foundation prerequisite audit complete: inventory only; no application schema was changed ==='
