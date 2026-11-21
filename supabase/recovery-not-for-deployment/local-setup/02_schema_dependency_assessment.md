# NEXORA Android Local Schema Audit — Findings and Safe Next Step

**Date:** 2026-11-13  
**Repository:** `shaifrony/nexora-platform1`  
**Branch:** `nexora-development`  
**Local database:** `nexora_test` (Android Termux, PostgreSQL 18.6)  
**Scope:** Read-only review of the local catalog audit and branch SQL sources.  
**Execution status:** No application migration or reconstructed schema has been applied.

## 1. Observed local audit result

The user successfully ran:

- `00_bootstrap_supabase_compat.sql` — bootstrap completed; local compatibility helpers and minimal auth/storage fixture tables reported ready.
- `01_local_catalog_audit.sql` — completed in a READ ONLY transaction.

The audit found:
- All 11 selected application tables reported `NOT RESTORED`.
- No public-schema RLS policies, constraints, indexes or triggers were present.
- The public/private function inventory showed the expected pgcrypto functions; no NEXORA application function was evidenced in the captured output.
- Available extensions include `pgcrypto` 1.4 and `uuid-ossp` 1.1; Termux package search did not find pgTAP.

This is an expected empty application-schema baseline, not a failed migration. The audit only inventories selected table names and catalog objects; it is not a complete repository-vs-database schema diff.

## 2. Key migration dependency observations

The branch contains 36 SQL migration files (see `docs/NEXORA_MIGRATION_COMPARISON_LEDGER.md`). The following dependencies are visible directly in the SQL sources:

### Core marketplace migration
`20261112050345_create_marketplace_core_schema.sql` creates:
- `business_profiles`
- `public_businesses`
- `products`
- `buyer_demands`
- `seller_offers`

But it assumes pre-existing objects:
- `public.profiles` (foreign keys and role/account status checks)
- `public.is_nexora_admin()` (RLS policies)
- `auth.uid()` (Supabase identity context)

Therefore it is NOT a standalone schema bootstrap.

### RLS/index follow-up
`20261112050553_optimize_marketplace_rls_and_fk_indexes.sql` references pre-existing tables and functions including `profiles`, `role_requests`, `profile_change_requests`, `seller_offers`, `buyer_demands`, `public.is_nexora_admin()`, and auth helpers. It cannot be run against the empty local database.

### Communications
`20261112050854_create_private_communications.sql` references `public.profiles` and the Supabase publication `supabase_realtime`. The publication is platform-specific and absent from this compatibility scaffold. Later communications migrations also rely on the initial communications tables.

### Transport and Porter
- `20261113100000_create_porter_delivery_workflow.sql` is explicitly marked SUPERSEDED and is an intentional no-op; do not apply it as a live Porter schema.
- `20261113180000_transport_provider_vehicle_model.sql` depends on `profiles`, `role_requests`, private permission helpers and auth context.
- `20261113200000_transport_provider_admin_review.sql`, `20261113220000_delivery_assignment_system.sql`, and later delivery migrations depend on provider, vehicle, profile and permission objects created earlier.
- `20261114210000_porter_public_registration_and_review.sql` changes the profile role constraint and creates Porter review structures; it assumes a complete profiles/admin permission foundation.

### Later commerce and workflow migrations
Commerce orders, inventory/MOQ, quotations, delivery network, unified assignments, tracking, and officer management all ALTER or reference earlier application tables/functions. They are feature migrations, not clean-baseline bootstrap scripts.

## 3. Why a one-shot replay is currently unsafe

1. The GitHub branch has 36 migration files, while the hosted migration history has 24 entries; 11 live history versions have no exact source file in the branch, and 23 branch files are absent from live history. See the comparison ledger.
2. Two duplicate-content migration pairs exist (51711/51801 and 51906/52010).
3. Buyer-demand publication source uses version 153000 while Live history records 153453.
4. The local scaffold only supplies minimal compatibility roles/schemas/helpers. It does not recreate the complete Supabase platform, actual auth users/session/JWT/AAL2, Realtime publication, Storage API, PostgREST, or platform role behavior.
5. The current local database has no application baseline tables. A later migration cannot safely run until all of its prerequisites have been reconstructed and validated.

Consequently, do not concatenate and execute all 36 migration files, do not run recovery drafts, and do not modify the hosted migration history.

## 4. Safe next step — staged baseline reconstruction

The next deliverable should be a NEW, clearly labelled, local-only baseline reconstruction in this folder, not a historical migration and not a deployable migration. It should be authored only after extracting and reviewing the exact definitions of the missing foundational objects and their dependencies.

Required foundation inventory before authoring:
- `profiles` columns, role/account-status checks, defaults, indexes, and user foreign key to `auth.users`
- `role_requests` and `profile_change_requests`
- `admin_staff`, department/permission tables and audit tables
- `private` permission helpers and `public.is_nexora_admin()`
- all functions/triggers referenced by the core marketplace migration
- exact grants and RLS policies, separated from the table-creation layer

Then create a disposable local baseline in dependency order and test it with a single consolidated script. Any Supabase-only SQL (Realtime publication, Storage policies, actual Auth triggers/AAL2) must be classified as platform-only and tested later using a real isolated Supabase local stack on a computer, not represented as passed by Android PostgreSQL.

## 5. Safety record

- This assessment is documentation only.
- No file in `supabase/migrations/` was changed.
- No recovery SQL draft was executed.
- No Live Supabase SQL, schema, data, migration history, production deployment, DNS, or `main` branch was changed.
- Keep all future local-only scripts in `supabase/recovery-not-for-deployment/local-setup/`.
