# NEXORA Android Local PostgreSQL Setup

**Target branch:** `nexora-development`  
**Database:** `nexora_test`  
**Status:** Scaffold authored; not yet executed on the user's phone.

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

Start PostgreSQL if it is not already running, then enter the local test database:

```sh
psql -d nexora_test
```

At the `nexora_test=#` prompt, exit psql to return to the Termux shell:

```sql
\\q
```

Download the SQL file from this branch and run it:

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
