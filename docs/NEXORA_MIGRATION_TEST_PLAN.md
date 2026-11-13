# NEXORA Migration Recovery — Test Plan

**Branch:** `nexora-development`  
**Status:** Android local PostgreSQL runtime available; guarded Supabase-compatibility scaffold authored; scaffold execution and migration tests pending.

## Objective

Establish a repeatable verification gate for the 11 missing-history recovery drafts without touching Live Supabase or the active migration directory.

## Environment decision

The user has PostgreSQL 18.6 running in Termux on Android 16, with a local `nexora_test` database. `pgcrypto` and `uuid-ossp` are available; `pgtap` is not listed in the selected Termux repository. This is a PostgreSQL-only environment, not a full Supabase stack. A Supabase Branch is not selected because it incurs recurring cost and has not been authorized.

## Safe test sequence

1. Preserve the 11 SQL drafts under `supabase/recovery-not-for-deployment/`.
2. Reconcile the migration baseline before attempting a full local Supabase reset; the repository and hosted histories diverge.
3. Restore a disposable schema snapshot or build an explicit fixture schema.
4. Apply candidate SQL only to that disposable database, in dependency order from the Recovery Plan.
5. Run the pgTAP catalog/privilege suite in `supabase/recovery-not-for-deployment/tests/`.
6. Run separate fixture-based RLS tests and AAL2/JWT tests; catalog checks alone are insufficient.
7. Test default privileges by creating temporary objects under the intended owner and checking grants, including confirmation that service_role defaults remain intact.
8. Record each result as PASS, FAIL, BLOCKED, or NOT RUN. Do not promote any draft based on manual review alone.

## Acceptance gates

- No unexpected privilege expansion.
- Anonymous users cannot read seller IDs, buyer IDs, or private business/contact fields.
- Public product access is limited to approved products for public/approved businesses.
- Public demand access is limited to open demands and excludes buyer identity.
- Required demand date remains public.
- AAL2 admin helper rejects anon, non-admin, inactive admin, and AAL1; permits only the intended active admin AAL2 identity.
- Default privilege tests demonstrate that service_role access is not accidentally removed.
- No test depends on production data or modifies a hosted database.

## Current status

| Work item | Status |
|---|---|
| Local PostgreSQL runtime | PASS — PostgreSQL 18.6 in Termux; `nexora_test` created |\n| Supabase compatibility scaffold | PREPARED — committed; not yet executed on device |\n| Available extensions | `pgcrypto`, `uuid-ossp` available; `pgtap` not found in Termux package search |
| Create pgTAP catalog/privilege suite | PREPARED — not executed; pgTAP unavailable locally |
| Fixture-based RLS tests | NOT RUN |
| AAL2/JWT context tests | NOT RUN |
| Default-privilege object-creation test | NOT RUN |
| Full migration replay | BLOCKED — history divergence |
| Live DB changes | NOT AUTHORIZED / NONE |

## Important Supabase CLI note

Supabase CLI v3 changes database command defaults to local-first and uses `--remote` for hosted targets. Any future CLI workflow must inspect the installed version and its `--help` output first. Never rely on old command assumptions or target Live by accident.


## Android local PostgreSQL update (2026-11-13)

The user has installed PostgreSQL 18.6 in Termux on Android 16 and created the local database `nexora_test`. A consolidated readiness query confirmed the connection and version. Termux package search did not return a `pgtap` package. The local database reports `pgcrypto` 1.4 and `uuid-ossp` 1.1 as available extensions.

A guarded compatibility scaffold has been committed at:
`supabase/recovery-not-for-deployment/local-setup/00_bootstrap_supabase_compat.sql`

It refuses to run unless the current database is exactly `nexora_test`. It creates local test roles, minimal auth/storage schemas and fixtures, and stub `auth.uid()`, `auth.jwt()`, and `auth.role()` helpers. It is deliberately not a Supabase emulator and has not yet been run on the user's device.

The companion instructions are in:
`supabase/recovery-not-for-deployment/local-setup/README.md`

Do not claim scaffold execution, migration replay, pgTAP execution, or Supabase RLS/Auth verification until separately evidenced. The active migration chain remains blocked by history divergence.
