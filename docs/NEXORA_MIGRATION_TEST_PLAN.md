# NEXORA Migration Recovery — Test Plan

**Branch:** `nexora-development`  
**Status:** Test harness prepared; execution blocked by missing local database runtime.

## Objective

Establish a repeatable verification gate for the 11 missing-history recovery drafts without touching Live Supabase or the active migration directory.

## Environment decision

The current workspace has no `psql`, `postgres`, `docker`, `supabase`, or `pg_prove` executable. A zero-cost local PostgreSQL runtime is therefore not presently available. A Supabase Branch is not selected because it incurs recurring cost and has not been authorized.

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
| Check for local PostgreSQL / Docker / Supabase CLI | BLOCKED — none installed |
| Create pgTAP catalog/privilege suite | PREPARED — not executed |
| Fixture-based RLS tests | NOT RUN |
| AAL2/JWT context tests | NOT RUN |
| Default-privilege object-creation test | NOT RUN |
| Full migration replay | BLOCKED — history divergence |
| Live DB changes | NOT AUTHORIZED / NONE |

## Important Supabase CLI note

Supabase CLI v3 changes database command defaults to local-first and uses `--remote` for hosted targets. Any future CLI workflow must inspect the installed version and its `--help` output first. Never rely on old command assumptions or target Live by accident.
