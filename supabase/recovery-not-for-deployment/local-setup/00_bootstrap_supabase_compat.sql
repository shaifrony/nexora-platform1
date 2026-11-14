-- NEXORA local Supabase-compatibility scaffold
-- SAFE TARGET: local database named nexora_test ONLY.
-- NOT a migration. NEVER copy into supabase/migrations/.
-- Does not connect to Supabase or modify any hosted database.
-- This is a limited PostgreSQL test scaffold, NOT a full Supabase emulator.

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'Safety stop: expected local database nexora_test, connected to %', current_database();
  END IF;
END
$guard$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS storage;

-- Minimal auth.users fixture. This is deliberately not the complete
-- Supabase Auth schema and must not be used as a production replacement.
CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE,
  phone text,
  role text,
  aud text,
  raw_app_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Supabase-compatible test helpers. Claims are injected only by local tests
-- using SET LOCAL; no real authentication/session validation is implemented.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $fn$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid,
    NULLIF(
      NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
      ''
    )::uuid
  );
$fn$;

CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $fn$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
$fn$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    current_user
  );
$fn$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.jwt() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role;

-- Minimal Storage-shaped fixtures for SQL that only references these objects.
-- Storage API behavior, policies, object lifecycle and signed URLs are NOT emulated.
CREATE TABLE IF NOT EXISTS storage.buckets (
  id text PRIMARY KEY,
  name text NOT NULL,
  public boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  file_size_limit bigint,
  allowed_mime_types text[]
);


-- Minimal Storage path helper used by the active NEXORA migration policies.
-- This mirrors folder-segment extraction only; it does not emulate the Supabase Storage API.
CREATE OR REPLACE FUNCTION storage.foldername(name text)
RETURNS text[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $function$
  WITH path_parts AS (
    SELECT string_to_array(coalesce(name,''), '/') AS parts
  )
  SELECT CASE
    WHEN cardinality(parts) <= 1 THEN ARRAY[]::text[]
    ELSE parts[1:cardinality(parts)-1]
  END
  FROM path_parts;
$function$;

CREATE TABLE IF NOT EXISTS storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text REFERENCES storage.buckets(id),
  name text NOT NULL,
  owner uuid,
  owner_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb
);

-- One consolidated smoke check; fail loudly if any prerequisite is absent.
DO $check$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'Wrong database';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    RAISE EXCEPTION 'pgcrypto extension missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp') THEN
    RAISE EXCEPTION 'uuid-ossp extension missing';
  END IF;
  IF to_regprocedure('auth.uid()') IS NULL
     OR to_regprocedure('auth.jwt()') IS NULL
     OR to_regprocedure('auth.role()') IS NULL THEN
    RAISE EXCEPTION 'Auth compatibility helpers missing';
  END IF;
  IF to_regclass('auth.users') IS NULL
     OR to_regclass('storage.buckets') IS NULL
     OR to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'Expected local fixture tables missing';
  END IF;
  RAISE NOTICE 'PASS: NEXORA local compatibility scaffold is ready in nexora_test';
END
$check$;

SELECT
  current_database() AS database,
  current_user AS connected_user,
  (SELECT extversion FROM pg_extension WHERE extname = 'pgcrypto') AS pgcrypto,
  (SELECT extversion FROM pg_extension WHERE extname = 'uuid-ossp') AS uuid_ossp,
  to_regprocedure('auth.uid()') IS NOT NULL AS auth_uid_ready,
  to_regclass('auth.users') IS NOT NULL AS auth_users_fixture_ready,
  to_regclass('storage.objects') IS NOT NULL AS storage_objects_fixture_ready;
