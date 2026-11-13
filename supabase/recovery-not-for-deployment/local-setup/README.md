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


## New foundation design proposal (not SQL)

No trusted schema-only export or pre-change SQL backup is available. A new design proposal has therefore been written for review:

- `05_foundation_design_proposal.md`

It is explicitly **not original, not recovered, and not deployable**. It documents the proposed identity/account lifecycle, Admin organization and permission model, Auth provisioning, Porter approval gates, privacy requirements, migration conflicts and open decisions. It is a design document only; it creates no database objects.

In particular, review the superseded Wholesale-Only / Buyer-category-gated migrations, the Porter vs Buyer/Seller transport-provider ownership conflict, and the public identity projection privacy risk before any local-only SQL fixture is authored. Do not execute active migrations or recovery drafts.


## Foundation design conflict resolution (2026-11-13)

The proposal now includes an authoritative resolution section based on the user's latest product decisions and the approved organization governance charter. See Section 7 of `05_foundation_design_proposal.md`.

Resolved target decisions:
- Public registration roles: Buyer, Seller, Porter only; Admin roles are internal.
- Porter is a user account role; Transport Provider is a separate profile linked only to an approved active Porter.
- Buyer and Seller accounts have no account-level market category. Each Product carries its own `market_category` (`wholesale` or `retail`); all users can view every approved Product. Demand matching does not gate on sale type.
- Seller business/listing visibility requires Admin approval.
- Porter account, Provider profile and each vehicle have separate approval gates.
- Public identity is a narrow approved projection; Buyer identity/contact must remain hidden on public Buyer Demands.
- Admin hierarchy: Director → MD → Department Heads → Department Officers, with explicit least-privilege permissions and separation of duties.

The older `NEXORA_PORTER_ARCHITECTURE.md` now carries a superseded-design notice. Conflicting active migrations and frontend code have **not** been edited in this design-only step. Do not replay them unchanged.


## New local Foundation baseline fixture

After resolving the design conflicts, a **new, non-historical local fixture** has been authored:

- `06_local_foundation_baseline_fixture.sql`

It creates the proposed identity/account lifecycle, role/profile-change requests, Admin departments/staff/permission catalogue/grants/audit tables, Porter account review, authorization helper functions, a limited local Auth-user trigger stub, and RLS/grants for the foundation layer.

**Safety requirements:**
- Run only after the compatibility bootstrap, only against the local database `nexora_test`.
- The script refuses to run if the database is not `nexora_test`, if the compatibility Auth helpers are absent, or if `public.profiles` already exists.
- It is a new reconstruction for local SQL testing, not the original schema and not deployable.
- It does not apply any active migration or recovery draft.
- The fixture's local Auth trigger is only a PostgreSQL test stub; it does not emulate Supabase Auth signup, sessions, OAuth, JWT validation or MFA/AAL2.
- Do not run the 36 active migrations on top of this fixture. The branch/hosted migration-history divergence remains unresolved, and known legacy migrations conflict with the current universal Wholesale/Retail visibility and Porter account decisions.
- SQL syntax and runtime behavior have **not yet been tested on the user's Android PostgreSQL instance**. After review, run the command below and share the complete output.

Run from the Termux shell (not inside the psql prompt):

```sh
curl -fL 'https://raw.githubusercontent.com/shaifrony/nexora-platform1/nexora-development/supabase/recovery-not-for-deployment/local-setup/06_local_foundation_baseline_fixture.sql' -o "$HOME/06_local_foundation_baseline_fixture.sql" && psql -d nexora_test -v ON_ERROR_STOP=1 -f "$HOME/06_local_foundation_baseline_fixture.sql"
```

Expected final lines:
`=== LOCAL FOUNDATION FIXTURE CREATED ===`
`This is a new local-only reconstruction, not original schema and not deployable.`


## Foundation fixture smoke tests

A rollback-only test script is also available:

- `07_foundation_smoke_tests.sql`

After the fixture has completed successfully, run:

```sh
curl -fL 'https://raw.githubusercontent.com/shaifrony/nexora-platform1/nexora-development/supabase/recovery-not-for-deployment/local-setup/07_foundation_smoke_tests.sql' -o "$HOME/07_foundation_smoke_tests.sql" && psql -d nexora_test -v ON_ERROR_STOP=1 -f "$HOME/07_foundation_smoke_tests.sql"
```

It checks local Buyer/Seller/Porter signup behavior, Porter pending review, OAuth Buyer-only behavior, rejection of public Admin signup, ignored legacy Buyer/Seller category metadata, and profile-role immutability. All test rows are rolled back. It does not validate real Supabase Auth, PostgREST, actual JWT/RLS session behavior, Storage, Realtime or MFA/AAL2.


## Current universal marketplace visibility decision (2026-11-13)

The older Wholesale-Only and Buyer-category-gated model above is superseded. The authoritative current model is:
- Buyer, Seller, Admin and Public Visitor can see every approved Wholesale and Retail Product.
- Seller chooses `market_category` separately for each Product.
- Buyer signup has no market-category choice; Buyer Dashboard has no market-category switch.
- `profiles.buyer_category` and `profiles.seller_categories` are not authorization controls.
- Buyer Demand routing uses Product category/subcategory and approved Business eligibility only; it does not filter on `market_category`.
- The old recovery draft at `supabase/recovery-not-for-deployment/dual-market/01_dual_market_alignment_recovery_draft.sql` is marked SUPERSEDED / DO NOT EXECUTE.
- The local visibility fixture tests the public approved-listing projection only. It does not contain the complete Demand/Inbox/Quotation schema.


## Buyer Demand quotation / Order workflow contract audit (local only)

A read-only contract audit is available at:

- `29_local_buyer_demand_order_contract_audit.sql`

It checks the installed Buyer Demand quotation and order RPC definitions, NULL-action guards, negotiation turn-taking on rejection, active-account checks, Seller acceptance state, negotiation-history RLS, one-order-per-offer uniqueness, source consistency constraint and denial of private RPC execution to `anon`.

Run it only from the Termux shell and only after the full required schema plus migration `20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql` have been installed in the local database `nexora_test`:

```sh
curl -fL 'https://raw.githubusercontent.com/shaifrony/nexora-platform1/nexora-development/supabase/recovery-not-for-deployment/local-setup/29_local_buyer_demand_order_contract_audit.sql' -o "$HOME/29_local_buyer_demand_order_contract_audit.sql" && psql -X -d nexora_test -v ON_ERROR_STOP=1 -f "$HOME/29_local_buyer_demand_order_contract_audit.sql"
```

If the workflow is not installed, the script prints `SKIP`; it does not create tables, install functions or change data. A `PASS` is a catalog/source-contract check only, not proof of all business behavior.

**Important migration-history blocker:** the current branch does not contain a trusted original foundation DDL/export for all prerequisite identity, Admin and Auth objects. The existing Android local database fixtures are explicitly reconstructed test fixtures, not the production schema. Do not replay the active migration directory on top of them or claim a full-chain rehearsal. A complete disposable rehearsal requires a trusted schema-only export (or the exact original baseline migration set) and a reconciled migration history. The audit above is safe to prepare now, but it will correctly SKIP until its prerequisites exist.

## Read-only live Foundation catalog snapshot (2026-11-14)

A metadata-only snapshot was captured from the connected live NEXORA project and stored at:

- supabase/recovery-not-for-deployment/live-schema-evidence/20261114_foundation_catalog_snapshot.json

It covers eight Foundation tables and ten selected functions, including exact columns/defaults, constraints, indexes, RLS policies, triggers and function definitions. It contains no table rows. It is evidence for reconstruction, not a full schema dump and not executable SQL.

The live project inventory at capture time showed PostgreSQL 17.11, 20 public tables plus two views, all 20 tables with RLS enabled, five non-internal public triggers, and 24 migration-history entries. Do not infer that this snapshot is a complete backup.

Full schema export is still required. Use the current Supabase CLI supabase db dump documentation or a locally installed pg_dump --schema-only against the connection string shown in the Supabase Dashboard. Keep the database password and complete connection string on the user's device; never send them in chat or commit them. Do not run a restore against the live project. A disposable local target must be confirmed before any restore or migration rehearsal.

## Full schema-only export — safe local recovery procedure

The live catalog snapshot has now also recorded:
- all 22 public relations (20 tables and 2 views);
- an inventory of 37 public/private functions (the complete definitions of ten selected foundation functions are included in the snapshot);
- 12 non-internal triggers in auth/storage and their trigger-function definitions;
- four auth/storage RLS policies.

This still does not replace a full SQL export, especially for exact grants/default privileges and all public/private function definitions.

### Do not use db pull on the live project for this recovery step

The current Supabase CLI workflow documents that db pull writes a baseline entry into the remote migration history. That would alter the live project's migration history, which is outside the current authorization. Do not run db pull, db push, db reset --linked, migration repair, or any migration command that writes to the remote project.

### Export public/private schema without table data

First check the locally installed PostgreSQL client:

```sh
pg_dump --version
```

Use pg_dump 17 or newer for the live PostgreSQL 17.11 project. If it is missing or older, stop and report the exact version/error; do not install random packages or improvise.

If pg_dump is compatible, copy the connection string from the Supabase Dashboard's Connect panel on your own device. Prefer the Session Pooler if the direct connection is unavailable on your network. Then run this from the Termux shell:

```sh
read -r -s -p "Paste the database connection string (hidden; do not send it in chat): " NEXORA_DB_URL
printf '\\n'
pg_dump --dbname="$NEXORA_DB_URL" --schema-only --no-owner --schema=public --schema=private --file="$HOME/nexora-live-public-private-schema.sql"
unset NEXORA_DB_URL
if [ -s "$HOME/nexora-live-public-private-schema.sql" ]; then
  echo "SCHEMA-ONLY EXPORT CREATED: $HOME/nexora-live-public-private-schema.sql"
else
  echo "EXPORT NOT VERIFIED — stop and share the exact error"
fi
```

This command exports schema definitions only for public/private, including table definitions, policies, functions, triggers, indexes and ACL statements emitted by pg_dump. It does not export table rows. The auth.users trigger and Storage customizations are separately preserved as catalog evidence in the JSON snapshot; do not attempt to restore Supabase-managed auth/storage schemas over a local Supabase stack.

**Do not upload the connection string, database password, data dump, auth.users rows, or production user data to GitHub or ChatGPT.** The schema-only SQL file should remain on the device until we inspect it. Do not restore it to the live project. A restore/rehearsal must target a disposable local database only, after confirming the database name and PostgreSQL major version.
