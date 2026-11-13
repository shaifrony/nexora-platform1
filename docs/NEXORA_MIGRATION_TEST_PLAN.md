# NEXORA Migration Recovery — Test Plan

**Branch:** `nexora-development`  
**Status:** Android local PostgreSQL runtime available; guarded compatibility scaffold executed successfully; consolidated read-only catalog audit committed and awaiting execution.

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
| Local PostgreSQL runtime | PASS — PostgreSQL 18.6 in Termux; `nexora_test` created |\n| Supabase compatibility scaffold | PASS — user executed on Android; readiness checks all true |\n| Available extensions | `pgcrypto`, `uuid-ossp` available; `pgtap` not found in Termux package search |
| pgTAP catalog/privilege suite | PREPARED — not executed; pgTAP unavailable locally |
| Read-only local catalog audit | PREPARED — committed; awaiting execution on device |
| Fixture-based RLS tests | NOT RUN |
| AAL2/JWT context tests | NOT RUN |
| Default-privilege object-creation test | NOT RUN |
| Full migration replay | BLOCKED — history divergence |
| Live DB changes | NOT AUTHORIZED / NONE |

## Important Supabase CLI note

Supabase CLI v3 changes database command defaults to local-first and uses `--remote` for hosted targets. Any future CLI workflow must inspect the installed version and its `--help` output first. Never rely on old command assumptions or target Live by accident.


## Android local PostgreSQL update (2026-11-13)

The user has installed PostgreSQL 18.6 in Termux on Android 16 and created the local database `nexora_test`. A consolidated readiness query confirmed the connection and version. Termux package search did not return a `pgtap` package. The local database reports `pgcrypto` 1.4 and `uuid-ossp` 1.1 as available extensions. On 2026-11-13 the user successfully executed the guarded compatibility bootstrap; output confirmed the local auth helpers and auth/storage fixture tables are present.

A guarded compatibility scaffold has been committed at:
`supabase/recovery-not-for-deployment/local-setup/00_bootstrap_supabase_compat.sql`

It refuses to run unless the current database is exactly `nexora_test`. It creates local test roles, minimal auth/storage schemas and fixtures, and stub `auth.uid()`, `auth.jwt()`, and `auth.role()` helpers. The user ran it successfully on their device. It is deliberately not a Supabase emulator.

The companion instructions are in:
`supabase/recovery-not-for-deployment/local-setup/README.md`

A read-only catalog inventory script has been added at `supabase/recovery-not-for-deployment/local-setup/01_local_catalog_audit.sql`; it is committed but has not yet been executed on the phone. Do not claim migration replay, pgTAP execution, or Supabase RLS/Auth verification until separately evidenced. The active migration chain remains blocked by history divergence.


## Android local catalog audit result (2026-11-13)

The user executed the read-only audit in `nexora_test`. All 11 selected application tables were reported `NOT RESTORED`; no public-schema RLS policies, constraints, indexes, or triggers were present. This is the expected empty application-schema baseline because no application migration has been applied. The captured function inventory showed pgcrypto functions, not an evidenced NEXORA application function inventory. No migration failure occurred.

A source-based dependency assessment is recorded in:
`supabase/recovery-not-for-deployment/local-setup/02_schema_dependency_assessment.md`

Key blocker: the core marketplace migration depends on `public.profiles`, `public.is_nexora_admin()`, and `auth.uid()`; the follow-up RLS migration additionally references `role_requests`, `profile_change_requests`, and admin helpers. Communications/delivery migrations also depend on Supabase Realtime publication and platform-specific objects. The Android scaffold does not supply a full Supabase environment.

**Decision:** do not replay all 36 migrations or execute recovery drafts. Next work is a separately labelled local-only baseline reconstruction after exact foundational definitions/dependencies are reviewed. Keep all local-only scripts under `supabase/recovery-not-for-deployment/local-setup/`. No Live Supabase changes were made.


## Foundation schema source-gap review (2026-11-13)

A repository-tree review found no current-branch migration that creates the original `profiles`, `role_requests`, `profile_change_requests`, or foundational Admin Staff/permission tables. The first available migrations already reference these objects. The later centralized officer migration only alters/seeds existing Admin tables; it is not their initial schema definition.

The exact source gap and referenced columns/functions are recorded in:
`supabase/recovery-not-for-deployment/local-setup/04_foundation_schema_source_gap.md`

A guarded, read-only local check was added:
`supabase/recovery-not-for-deployment/local-setup/03_foundation_prerequisite_audit.sql`

No foundational CREATE TABLE script has been invented. Exact types, defaults, constraints, RLS policies, grants, Auth trigger behavior and helper-function bodies are security-critical and cannot be recovered from column references alone. Obtain a trusted schema-only export or pre-change SQL backup before claiming exact recovery. If none exists, a separately reviewed local-only fixture may be designed, explicitly labelled as a new reconstruction rather than original schema.

No Live Supabase SQL was executed and no active migration or recovery draft was applied.
