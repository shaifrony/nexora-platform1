# NEXORA Android Local PostgreSQL Setup

**Target branch:** `nexora-development`  
**Database:** `nexora_test`  
**Status:** Bootstrap scaffold and read-only catalog audit executed successfully on Android (2026-11-13). Foundation source-gap review and a second read-only prerequisite audit are now added.

## Purpose

`00_bootstrap_supabase_compat.sql` creates a guarded, minimal compatibility layer for local SQL inspection and selected PostgreSQL tests.

It:
- Refuses to run unless the connected database is exactly `nexora_test`.
- Enables the locally available `pgcrypto` and `uuid-ossp` extensions.
- Creates local `anon`, `authenticated`, and `service_role` roles if absent.
- Creates minimal `auth`, `private`, and `storage` schemas.
- Adds lightweight `auth.uid()`, `auth.jwt()`, and `auth.role()` helpers.
- Adds minimal `auth.users`, `storage.buckets`, and `storage.objects` fixture tables.
- Runs one consolidated smoke check and prints a readiness row.

## Run on Android / Termux

If you are currently at the `nexora_test=#` prompt, first exit to the Termux shell:

```sql
\q
```

Then download the SQL file from this branch and run it in one step:

```sh
curl -L 'https://raw.githubusercontent.com/shaifrony/nexora-platform1/nexora-development/supabase/recovery-not-for-deployment/local-setup/00_bootstrap_supabase_compat.sql' -o "$HOME/00_bootstrap_supabase_compat.sql"
psql -d nexora_test -v ON_ERROR_STOP=1 -f "$HOME/00_bootstrap_supabase_compat.sql"
```

Expected final output includes:
`NOTICE: PASS: NEXORA local compatibility scaffold is ready in nexora_test`.

If `curl` is not installed, do not improvise another package install; report the exact error first.

## Critical limitations

This is **not** a full Supabase local stack and does not emulate:
- Supabase Auth signup, password hashing, sessions, token verification, OAuth, MFA/AAL2, or auth triggers;
- Storage API, buckets/object policies, signed URLs, or upload behavior;
- Realtime, PostgREST/Data API, Edge Functions, Vault, platform roles, or Supabase-specific extension behavior;
- Full RLS behavior under actual Supabase JWT/session context.

The `auth.uid/jwt/role` helpers read local PostgreSQL session settings only. They are test stubs, not authentication.

Do not run the active migration chain or the recovery drafts against this scaffold yet. The migration-history divergence and missing Supabase platform objects remain unresolved. The scaffold is for safe local prerequisites and future isolated SQL tests only.

## Safety

- This file is under `supabase/recovery-not-for-deployment/local-setup/`, never `supabase/migrations/`.
- It contains a database-name guard for `nexora_test`.
- It does not contain remote credentials or connect to Live Supabase.
- Never point it at Live Supabase.
- Do not move it into the active migration directory.


## Read-only catalog audit

After the bootstrap scaffold has completed, run the consolidated inventory audit from the Termux shell:

```sh
curl -fL 'https://raw.githubusercontent.com/shaifrony/nexora-platform1/nexora-development/supabase/recovery-not-for-deployment/local-setup/01_local_catalog_audit.sql' -o "$HOME/01_local_catalog_audit.sql" && psql -d nexora_test -v ON_ERROR_STOP=1 -f "$HOME/01_local_catalog_audit.sql"
```

This script is read-only (it opens a READ ONLY transaction), checks the local compatibility prerequisites, and inventories application tables, RLS policies, constraints, indexes, triggers, and functions already present. It does not apply migrations or modify application objects. Since the user has only run the compatibility scaffold so far, application tables are expected to report `NOT RESTORED`; that is a status, not a test failure.


## Foundation prerequisite audit

The branch SQL review found that the current migration directory does not contain the original DDL that creates `profiles`, `role_requests`, `profile_change_requests`, or the foundational Admin Staff/permission tables. The marketplace and later workflows already depend on these objects. Details are recorded in:

- `02_schema_dependency_assessment.md`
- `04_foundation_schema_source_gap.md`

A second read-only check is available at `03_foundation_prerequisite_audit.sql`. It checks the referenced foundation tables/columns, authorization helper functions, local schemas and roles. It does not create or modify any object.

Run from the Termux shell (not from the psql prompt):

```sh
curl -fL 'https://raw.githubusercontent.com/shaifrony/nexora-platform1/nexora-development/supabase/recovery-not-for-deployment/local-setup/03_foundation_prerequisite_audit.sql' -o "$HOME/03_foundation_prerequisite_audit.sql" && psql -d nexora_test -v ON_ERROR_STOP=1 -f "$HOME/03_foundation_prerequisite_audit.sql"
```

The expected current result is that the foundation tables/functions are missing, because no application baseline has been restored. This is an inventory result, not a migration failure.

**Do not create a guessed baseline yet.** The exact original profile, role-request, Admin permission, audit, Auth trigger and helper-function definitions were not found in the current branch tree. A trusted schema-only export or pre-change SQL backup is required to recover them exactly. If no exact source exists, any later local test fixture must be labelled as a new reconstruction, never as recovered original schema.
