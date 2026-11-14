# NEXORA — Missing Migration Recovery Package

**Branch:** `nexora-development`  
**Repository:** `shaifrony/nexora-platform1`  
**Purpose:** Preserve recovery work for 11 migration-history entries whose original SQL files were not present in the repository.  
**Execution status:** Selected recovery-only candidates have been executed in disposable local test environments only; none are authorized or applied to hosted Supabase.

## Critical warning

This directory is deliberately named `recovery-not-for-deployment` and is outside `supabase/migrations/`. These files must not be moved into the active migration directory or run against Live Supabase.

The package does **not** claim that 11 original historical SQL files have been recovered byte-for-byte. The original sources were not found in the checked GitHub branches/commit paths. Ten files are catalog-based reconstruction drafts; one SQL body was recovered from a GitHub commit but its live migration timestamp differs from the repository file timestamp.

A reconstruction is a new representation of the observed final database state, not proof of the exact historical statements, ordering, intent, or intermediate state.

## Recovery inventory

| Live history version | Package file | Source classification |
|---|---|---|
| `20261112063728` | `20261112063728_add_wholesale_product_pricing_fields.sql` | Reconstructed from current products columns/defaults/constraints |
| `20261112092911` | `20261112092911_restrict_public_products_to_approved_businesses.sql` | Reconstructed from current products RLS policy |
| `20261112093024` | `20261112093024_limit_anonymous_product_columns.sql` | Reconstructed from current anon column privileges |
| `20261112093107` | `20261112093107_expose_safe_public_business_check_for_anon_policy.sql` | Reconstructed from current function body, security mode and ACL |
| `20261112094305` | `20261112094305_public_business_safe_anon_read.sql` | Reconstructed from current public-business policy and anon column grants |
| `20261112094341` | `20261112094341_make_public_business_check_invoker_safe.sql` | Reconstructed from current SECURITY INVOKER function configuration |
| `20261112094441` | `20261112094441_revoke_postgres_default_public_api_grants.sql` | Reconstructed from current postgres-owned default ACL snapshot; exact historical scope not proven |
| `20261112115158` | `20261112115158_allow_cancelled_account_status.sql` | Reconstructed from current profiles account-status CHECK constraint |
| `20261112145135` | `20261112145135_require_aal2_for_nexora_admin_access.sql` | Reconstructed from current private super-admin function and ACL |
| `20261112153453` | `20261112153453_publish_open_demands_without_buyer_identity.sql` | SQL body source-recovered from commit `e468347c43e9a88d17504fca7c5ed8304aaa8374`; live version is 153453 but repo source is 153000 |
| `20261112160835` | `20261112160835_secure_public_buyer_demand_projection.sql` | Reconstructed from current view definition, reloptions and grants |

## GitHub source recovery notes

- Branch inventory showed `main` and `backup-before-changes` at the same older commit; the backup branch did not contain the migrations directory at the requested path.
- The `nexora-development` history was inspected, including commits related to public demand publication, admin AAL2, product pricing and security.
- Commit `e468347c43e9a88d17504fca7c5ed8304aaa8374` contains the SQL body that corresponds to the open public-demand policy/grant behavior. Its repository migration file is timestamped `20261112153000`, while live history records `20261112153453`.
- Existing migrations `20261112151344`, `20261112151436`, and `20261112151504` were inspected to understand the later AAL2 policy evolution. They do not prove the exact content of the earlier live-only version `20261112145135`.
- No claim is made that the remaining ten original SQL bodies were found.

## Live catalog evidence inspected (read-only)

The recovery drafts were based on read-only catalog inspection of:
- `products` columns, defaults, constraints, RLS policies and anonymous column grants;
- `public_businesses` columns, anonymous read policy and anonymous column grants;
- `public.is_public_business(uuid)` definition, SECURITY INVOKER setting and function ACL;
- `profiles_account_status_check`;
- `private.is_nexora_super_admin()` definition and function ACL;
- `buyer_demands` anonymous policy and column grants;
- `public.public_buyer_demands` view definition, `security_invoker=true` reloption and grants;
- `pg_default_acl` entries for objects owned by `postgres` in schema `public`.

These are point-in-time observations. They do not reveal the original SQL text or historical sequence.

## Required review before any use

1. Compare every draft with the complete current Live definitions again immediately before any future change.
2. Review privilege and RLS behavior in an isolated PostgreSQL/Supabase environment.
3. Resolve whether the default-privilege draft precisely matches the original intent; its scope is especially sensitive.
4. Test the security-definer functions and all anonymous access paths with both anon and authenticated roles.
5. Verify the demand view preserves buyer privacy and the required-date field.
6. Verify product price unit, MOQ and negotiability constraints against the approved wholesale-only business model.
7. Obtain explicit authorization for any Live database operation in a separate request.

## Current safety state

- No Live SQL executed.
- No migration-history rows inserted, deleted or updated.
- No existing migration file overwritten or deleted.
- No `main` branch or Production deployment changed.
- Recovery drafts are stored outside `supabase/migrations/` so normal migration discovery will not pick them up.


## Draft audit completed

See [NEXORA Missing Migration Draft Audit](../../docs/NEXORA_MISSING_MIGRATION_DRAFT_AUDIT.md) for per-file catalog evidence, dependency relationships, manual SQL review, security test requirements, and current Supabase Advisor findings.

The default-privilege draft was narrowed during review to Data API-facing grants only (table CRUD, sequence USAGE/SELECT, function EXECUTE); it does not revoke service_role defaults. This remains a reconstructed proposal, not verified original SQL.

Some candidates have narrow local PostgreSQL/Supabase rehearsal evidence, but that does not certify the complete recovery package or the current 39-migration chain. No draft is certified for hosted execution.


## Current NEXORA-TEST Foundation Design

- Current authoritative Test-only foundation contract: [`local-setup/09_nexora_test_foundation_baseline_spec.md`](local-setup/09_nexora_test_foundation_baseline_spec.md).
- [`local-setup/05_foundation_design_proposal.md`](local-setup/05_foundation_design_proposal.md) is retained as superseded historical proposal; its Wholesale-Only Buyer/Seller category model is no longer current.
- [`local-setup/06_local_foundation_baseline_fixture.sql`](local-setup/06_local_foundation_baseline_fixture.sql) is a legacy local PostgreSQL compatibility fixture and is explicitly superseded. Do not apply it as the current NEXORA baseline or to hosted Supabase.
- The new specification is design only: no SQL has been generated or executed against NEXORA-TEST. Do not replay feature migrations until the compatibility matrix and runtime gates are complete.


## 39-Migration and Frontend Compatibility Matrix

- Current static audit: [`local-setup/10_migration_frontend_compatibility_matrix.md`](local-setup/10_migration_frontend_compatibility_matrix.md).
- It maps all 39 active migration files, required Foundation/platform/earlier-migration dependencies, Admin permission functions, Auth trigger prerequisites, and current frontend RPC/table call mismatches.
- Audit conclusion is BLOCKED for a clean empty Test DB: the feature migrations assume a pre-existing Foundation; the legacy Porter frontend still references table/RPC names absent from the active migration set.
- Source audit plus a limited PGlite PostgreSQL 18.6 rehearsal: Foundation candidate #13 + all 39 active migrations + candidate #14 executed; 8/8 synthetic security assertions passed. This is not a full Supabase runtime. No SQL was executed against NEXORA-TEST or any hosted database.


## 2026-11-15 inventory correction

- The current active migration inventory is 39 files / 39 unique versions. The prior 38-file matrix omitted `20261114175118_add_dual_listing_market_category.sql`; the matrix v2 now includes it at timestamp-order position #32 and includes migration #39 `20261115120000_multilingual_chat_foundation.sql`.
- Earlier 38/38 replay statements are not proof of the current 39-file chain. The current isolated runtime gate remains open; do not apply recovery-only SQL to hosted Supabase.
- NEXORA-TEST was rechecked read-only: `ACTIVE_HEALTHY`, no application migration history and no public application tables. No schema was applied.
- The current baseline spec clarifies that Wholesale/Retail is per Listing, not a Buyer/Seller account category or visibility restriction.


## 2026-11-15 PGlite rehearsal update

- A fresh isolated Vercel sandbox ran PGlite 0.5.16 / PostgreSQL 18.6 WASM. Foundation candidate #13, all 39 active migrations and recovery candidate #14 executed successfully in this limited runtime; 9/9 Foundation tables, 5/5 helper functions, 41/41 public-table RLS, 96 public policies and 45 SECURITY DEFINER functions with explicit search_path were observed. Eight synthetic privacy/authorization assertions passed.
- PGlite does not provide the full Supabase Auth/PostgREST/Storage/Realtime stack or PostgreSQL event triggers. For this rehearsal only, unavailable extension installs were omitted and `rls_auto_enable()` was a no-op stub; therefore this is not full Supabase validation and does not authorize hosted execution.
- Native PostgreSQL event-trigger candidate #12 has a separate earlier standalone semantic rehearsal. It was not installed into PGlite.
- The native Supabase CLI stack could not be started in this sandbox: Docker/Podman/Supabase CLI were unavailable and Ubuntu package repository DNS resolution failed. The full Supabase runtime gate remains open.
- NEXORA-TEST remains read-only and unchanged. Do not apply recovery-only candidates #12/#13/#14 to hosted projects. A separately reviewed Test-only baseline may be considered only after the full isolated Supabase runtime and remaining permission/RPC contracts pass.
