# NEXORA Migration Recovery Plan

**Status:** Planning document — no database changes executed  
**Target branch:** `nexora-development`  
**Repository:** `shaifrony/nexora-platform1`  
**Prepared against branch HEAD:** `3b05368cc44e2d21a5895582144a9b65c781f930`

## 1. Purpose and safety boundary

This document defines a controlled recovery path for the divergence between the SQL migration files in GitHub and the migration history recorded by the live Supabase project.

This is a planning and evidence document only. It does not authorize or perform:
- SQL execution against the live Supabase database;
- migration-history repair or insertion;
- changes to the `main` branch;
- production deployment, DNS changes, or paid services;
- deletion, renaming, or rewriting of historical migration files.

All implementation work must remain on `nexora-development` until separately reviewed and explicitly approved.

## 2. Observed baseline

The read-only audit reported:

| Evidence | Observed count |
|---|---:|
| SQL migration files in GitHub branch | 36 |
| Applied entries in live Supabase migration history | 24 |
| Migration versions present in both places | 13 |
| GitHub migration files absent from live history | 23 |
| Live migration entries with no matching SQL file in branch | 11 |

These counts describe filename/version presence, not proof that the SQL effects are equivalent. A matching timestamp/name does not prove the live database has the exact same definition, and a missing history row does not prove that the migration's effects are absent.

The read-only schema baseline also reported 20 public tables, 82 RLS policies, 37 public/private functions, 16 public/storage triggers, and 2 views. All 20 public tables had RLS enabled; none had FORCE ROW LEVEL SECURITY. These counts are a point-in-time audit snapshot and must be rechecked before any future migration.

## 3. Eleven live history entries with no matching SQL file

The following versions were present in live migration history but their original SQL files were not found in `nexora-development`, `main`, or `backup-before-changes` during the earlier repository search:

| Live version | Recorded migration name | Recovery status |
|---|---|---|
| `20261112063728` | `add_wholesale_product_pricing_fields` | Original SQL not recovered |
| `20261112092911` | `restrict_public_products_to_approved_businesses` | Original SQL not recovered |
| `20261112093024` | `limit_anonymous_product_columns` | Original SQL not recovered |
| `20261112093107` | `expose_safe_public_business_check_for_anon_policy` | Original SQL not recovered |
| `20261112094305` | `public_business_safe_anon_read` | Original SQL not recovered |
| `20261112094341` | `make_public_business_check_invoker_safe` | Original SQL not recovered |
| `20261112094441` | `revoke_postgres_default_public_api_grants` | Original SQL not recovered |
| `20261112115158` | `allow_cancelled_account_status` | Original SQL not recovered |
| `20261112145135` | `require_aal2_for_nexora_admin_access` | Original SQL not recovered |
| `20261112153453` | `publish_open_demands_without_buyer_identity` | Original SQL not recovered |
| `20261112160835` | `secure_public_buyer_demand_projection` | Original SQL not recovered |

**Important:** Do not recreate files and label them as the original historical SQL. If source recovery remains impossible, any future SQL must be clearly named and documented as a new reconciliation/baseline migration, derived from verified live definitions and intended policy. Preserve the distinction between observed current state and inferred historical intent.

## 4. GitHub migrations absent from live history

The earlier audit found 23 SQL files in the GitHub branch that did not have matching versions in live migration history. This is not, by itself, proof that all 23 are safe or pending to run. The list includes later feature work as well as migrations that may overlap with live state.

Before any execution, each file must be classified as one of:
1. **Not applied and required** — verified absent from live schema and safe to apply in dependency order.
2. **Already represented in live schema** — effects verified equivalent; do not blindly re-run.
3. **Partially represented** — requires a carefully reviewed reconciliation migration.
4. **Superseded or duplicate** — retain historical evidence; exclude from the future canonical sequence only through an approved archive strategy.
5. **Blocked** — has unresolved syntax, policy, dependency, or business-rule concerns.

No file should be run merely because its version is missing from the history table.

## 5. Duplicate migration files

Two pairs were found to have identical SQL content and identical Git blob SHA values:

- `20261112051711_update_conversation_timestamp_on_message.sql`
- `20261112051801_update_conversation_timestamp_on_message.sql`

- `20261112051906_fix_conversation_insert_returning_visibility.sql`
- `20261112052010_fix_conversation_insert_returning_visibility.sql`

Live history contains `51711` and `51906`, but not `51801` and `52010`.

**Plan:** Keep the files untouched for now. Record them as duplicate candidates. Before establishing a canonical future migration chain, inspect references and dependencies, then propose whether the later duplicate files should be moved to a clearly labelled archive directory or otherwise excluded from future migration discovery. Do not delete them without explicit approval.

## 6. Buyer Demand timestamp mismatch

Live history contains:

`20261112153453_publish_open_demands_without_buyer_identity`

The GitHub branch contains:

`20261112153000_publish_open_demands_without_buyer_identity.sql`

The branch SQL creates/replaces the anonymous open-demand read policy and grants anonymous SELECT only on the intended public columns. The earlier read-only audit observed a matching public projection and column-level access pattern in live schema, including exclusion of `buyer_id`.

This is evidence of functional correspondence, not proof that the original live SQL was byte-for-byte or semantically identical. Preserve both version identifiers in the reconciliation record; do not silently rewrite either timestamp.

## 7. Verified live-state observations to preserve

### Products and public seller visibility
The read-only audit observed:
- a public product SELECT policy limited to approved listings and businesses accepted by `is_public_business(business_id)`;
- anonymous column-level product grants for public product fields;
- `seller_id` excluded from anonymous column grants;
- product pricing fields including `price_unit`, `minimum_order_quantity`, and `price_negotiable`;
- `public.is_public_business(uuid)` is SECURITY INVOKER with an empty search path.

These definitions must be re-inspected before reconstruction. Do not assume the current policy is safe solely because the function name or policy name appears correct.

### Buyer Demand privacy
The read-only audit observed:
- `buyer_id` is not granted to anonymous users;
- anonymous access is restricted to open demands;
- the `public_buyer_demands` view exposes safe fields and omits buyer identity;
- public fields include `required_date`, quantity, budget/currency, destination and product requirement information.

The required date remains a core NEXORA demand field. Any future reconstruction must preserve privacy and the public-demand product requirements.

### Profiles and administrative MFA
The audit observed profile role values including buyer, seller, porter and admin; account status values including active, pending, suspended and cancelled; and private administrative helper functions enforcing AAL2 and active staff status. Recheck exact constraints, grants, function definitions and policy dependencies before relying on them.

## 8. Known staged migration requiring full review

`20261114120000_listing_edit_review_workflow.sql` was previously flagged for a suspected malformed currency regular expression/quote and SQL appearing after `COMMIT;`. The complete file has not yet been certified as valid.

Before it can be considered executable:
1. Read the entire file, not selected snippets.
2. Validate every quote, dollar-quoted block, statement terminator and transaction boundary.
3. Check whether statements after `COMMIT;` are intentional and valid.
4. Verify referenced tables, columns, constraints, policies, functions and grants exist in dependency order.
5. Review any `market_category` validation that permits both `wholesale` and `retail`. NEXORA is wholesale-only; retail must not be enabled accidentally.
6. Run static SQL parsing and isolated database tests before any deployment proposal.

Do not repair or execute this migration until the full review is complete.

## 9. Dependency-aware feature groups

This is a preliminary dependency map, not a verified execution order. Exact dependencies must be checked against the full SQL definitions.

| Feature group | Candidate files / versions | Key dependency or review |
|---|---|---|
| Core marketplace and communications | `20261112050345`, `20261112050854`–`20261112052010` | Profiles, core schema, RLS, conversation participants |
| Admin MFA and permissions | `20261112151344`–`20261112151504` | Admin staff, permission helpers, AAL2 |
| Buyer/Seller categories | `20261113230000`, `20261113235900` | Category constraints and product references |
| Transport provider and vehicle | `20261113180000`, `20261113200000` | Profiles, admin review, audit permissions |
| Delivery assignment | `20261113100000`, `20261113220000` | Provider approval, vehicles, assignment permissions |
| Services and listing media/editing | `20261114090000`–`20261114130000` | Business profiles, storage, listing review workflow |
| Reviews and commerce | `20261114130100`, `20261114140000` | Orders and verified purchase relationship |
| Inventory and demand quotations | `20261114150000`, `20261114160000` | Products, buyer demands, offers/quotations |
| Delivery network and tracking | `20261114170000`–`20261114190000` | Providers, assignments, delivery jobs, status history |
| Officer account management | `20261114200000` | Admin departments, grants, audit logs |
| Porter public registration/review | `20261114210000` | Profiles constraints, signup trigger, RLS, audit logs |

The order above is a planning guide only. Do not assume timestamps alone establish a safe dependency sequence.

## 10. Recovery workflow and acceptance gates

### Gate A — Evidence freeze
- Record current branch HEAD and preserve a read-only copy of the current migration directory.
- Export/read the live migration history and relevant schema definitions without changing them.
- Capture table definitions, constraints, indexes, RLS policies, grants, views, functions, triggers and storage policies relevant to each migration.
- Record source and retrieval time for each evidence item.

**Exit condition:** every one of the 24 live history entries and 36 branch SQL files is classified in a comparison ledger.

### Gate B — SQL and dependency audit
- Inspect every migration file in full.
- Detect duplicate SQL by blob/content hash.
- Build an exact dependency graph from referenced objects, not timestamps alone.
- Identify destructive operations, privilege changes, RLS changes and data backfills.
- Resolve the `14120000` syntax and wholesale-only business-rule review.

**Exit condition:** each migration has a documented classification, dependency list, risk level and reviewer decision.

### Gate C — Reconstruction design
- For the 11 missing historical SQL files, search available repository history/backup sources once more if useful.
- If originals remain unavailable, document current live definitions as observed state and write a new reconciliation design; never claim it is the original SQL.
- Separate historical migration repair from future feature migrations.
- Prepare rollback/restore considerations and data-impact notes.

**Exit condition:** a reviewed recovery proposal exists, with no ambiguous “run all pending migrations” instruction.

### Gate D — Isolated testing
- Obtain an isolated development database or local PostgreSQL/Supabase environment with no production data.
- Do not create a paid Supabase branch or incur recurring costs without the user's explicit approval.
- Test the complete proposed migration sequence from a clean baseline.
- Test the reconciliation path against a schema snapshot that reflects the observed live baseline.
- Run SQL lint/static parsing, RLS tests, permission tests, signup tests and feature integration tests.

**Exit condition:** repeatable tests pass and the exact migration plan is documented.

### Gate E — Separate production authorization
Only after Gates A–D pass should a separate change request be presented. It must list exact SQL files, exact commands, expected schema changes, data risks, rollback plan and verification steps. Live execution requires the user's explicit approval at that time.

## 11. Verification matrix

| Area | Required checks |
|---|---|
| Migration history | Version inventory, duplicate detection, missing-source tracking |
| Schema | Tables, columns, types, constraints, indexes, foreign keys |
| Security | RLS enabled/forced status, policies, grants, function security mode and search path |
| Public privacy | Anonymous product and demand access; no buyer contact/identity leakage |
| Authentication | Buyer/Seller/Porter signup; admin roles unavailable in public signup; OAuth Buyer-only |
| Porter onboarding | Pending account, approval/rejection/suspension, provider and vehicle approval gates |
| Marketplace | Wholesale-only categories, product visibility and seller approval |
| Business workflows | Demand, quotation, orders, inventory/MOQ, delivery assignment and tracking |
| Communications | Consent/invitation, chat, files, calls and history access controls |
| Operations | Audit logging, admin permissions, error handling and recovery |

## 12. Immediate next actions

1. Create and maintain a migration comparison ledger with all 36 branch files and 24 live versions.
2. Re-fetch the full source of `20261114120000_listing_edit_review_workflow.sql` and review it line by line.
3. Inspect all 11 missing-version live object definitions and record the exact observed state for each.
4. Build a verified dependency graph and classify every staged feature migration.
5. Prepare isolated test strategy using only no-cost options unless the user separately approves a paid environment.

## 13. Current decision

**Safe to proceed:** documentation, read-only inspection, static analysis, and development-branch planning.

**Not approved / not safe yet:** applying migrations to live Supabase, modifying live migration history, deploying to production, changing `main`, or creating a paid development branch.

The recovery objective is to establish one auditable, repeatable migration path without guessing at missing historical SQL or risking the live NEXORA database.


## 14. Recovery package created (2026-11-13)

A recovery package has now been added to `supabase/recovery-not-for-deployment/` on `nexora-development`. It contains 11 SQL files, but these are **not** represented as 11 original historical files:

- Ten files are clearly labelled catalog-based reconstruction drafts.
- One SQL body for open-demand publication was recovered from GitHub commit `e468347c43e9a88d17504fca7c5ed8304aaa8374`; however, the repository source is timestamped `20261112153000` while live history records `20261112153453`. The body is source-recovered, but the exact original 153453 file is not.
- The package README records source classification and the read-only catalog evidence used.

All 12 package files (README plus 11 SQL drafts) were fetched back from GitHub and verified to exist on `nexora-development`.

**Critical:** The recovery directory is outside `supabase/migrations/` and must stay there until a separate review. No draft was executed. No live migration history, schema, data, grants, policies, production branch or deployment was changed.

Package index: `supabase/recovery-not-for-deployment/README.md`.


## 15. Recovery draft audit (2026-11-13)

A per-file review is recorded in [NEXORA_MISSING_MIGRATION_DRAFT_AUDIT.md](NEXORA_MISSING_MIGRATION_DRAFT_AUDIT.md). The review rechecked the relevant Live catalog definitions, grants, policies, helper functions, default ACLs and demand view. Eight drafts were catalog-consistent under manual review, one SQL body was source-recovered with a version mismatch, and two require special privilege/security testing before any use.

The default-privilege draft was narrowed to API-facing table CRUD, sequence USAGE/SELECT and function EXECUTE grants; service_role defaults are not revoked. No parser/isolated replay test was available. No recovery draft was executed.

## 2026-11-14 — Read-only live foundation catalog evidence captured

A read-only catalog inspection was completed against the connected NEXORA Supabase project. The project is active and reports PostgreSQL 17.11. No DDL, DML, migration-history write, Auth mutation, or deployment was performed.

### Current live inventory (observed)

- Public schema: 22 relations — 20 tables and 2 views.
- All 20 public tables have RLS enabled. The two views are not tables; their view security options still require separate inspection before any restore.
- Five non-internal triggers exist on public tables: three on profiles, one on business_profiles, and one on messages.
- The public/private schemas contain 37 functions in the inspected inventory; 23 are marked SECURITY DEFINER. Every such function must be reviewed for owner, EXECUTE ACL, search_path and caller checks before reconstruction.
- Live migration history contains 24 entries. The branch contains 36 migration files; the prior filename/version ledger remains 13 matching, 23 branch-only and 11 live-only. Presence/absence is not proof of SQL effect equivalence.

### Foundation evidence artifact

The following metadata-only snapshot was captured from PostgreSQL catalogs and committed on nexora-development:

- supabase/recovery-not-for-deployment/live-schema-evidence/20261114_foundation_catalog_snapshot.json

It records exact observed columns/defaults, constraints, indexes, RLS policies, triggers and selected function definitions for eight live foundation tables: profiles, role_requests, profile_change_requests, admin_staff, admin_departments, admin_permission_catalog, admin_permission_grants, and admin_audit_logs. It also records ten related public/private function definitions. It contains catalog metadata only, not table rows or user data.

This is stronger evidence than the reconstructed fixture, but it is not a complete schema-only dump, does not capture every ACL/default privilege, every Auth/Storage object or all public/private function definitions, and is not deployable SQL. Do not treat it as the original historical migration source.

### Corrected recovery position

The previous blocker is narrowed: the live database is accessible for read-only catalog inspection, and a verified foundation metadata snapshot now exists. The exact original migration files remain unrecovered. A complete disposable rehearsal still requires a full schema-only export (including custom Auth/Storage triggers and policies), extension/role inventory, and migration-history reconciliation.

Use the Supabase CLI documented supabase db dump workflow or a locally installed pg_dump --schema-only against the dashboard-provided connection string to obtain the full SQL dump. Keep credentials on the user's device; never paste the database password or connection string into chat or commit it. Do not restore this dump to the live project. Restore only into a disposable local database, after checking the dump target and PostgreSQL major version.

### Next gates

1. Capture full schema-only SQL and role/extension metadata locally without committing secrets or data.
2. Compare the captured live definitions against every migration in the branch; update the migration comparison ledger with object-level evidence.
3. Build a disposable local baseline from the observed dump, not by replaying the reconstructed fixture as if it were original.
4. Rehearse only selected pending feature migrations on that disposable baseline, beginning with the Buyer Demand quotation/order workflow.
5. Run SQL behavior tests, then hosted JWT/PostgREST/RLS and browser tests only after an explicit, separately scoped approval.

No Live Supabase object, migration history, production data, main, DNS or deployment was changed.

### Addendum — Auth and Storage catalog coverage

The evidence JSON was subsequently extended with:
- the inventory of all 22 public relations and all 37 public/private functions;
- all 12 non-internal triggers found in auth/storage, including trigger definitions and trigger-function source;
- all four auth/storage RLS policies;
- a count of 23 SECURITY DEFINER functions in the public/private inventory.

The eight foundation tables and ten selected public/private function definitions remain the detailed Foundation snapshot. The other function definitions, grants/default privileges and a complete raw schema-only SQL export are still outstanding. The five public triggers and twelve auth/storage triggers are separate counts (17 observed non-internal triggers across these inspected scopes).


### Addendum — Android-only read-only catalog recovery (2026-11-14)

The user has only an Android/Termux device; Supabase CLI and Docker are absent. Do not ask them to install Docker CLI as a workaround: a Docker Engine is not available through that alone. Recovery is continuing through the already connected Supabase database tool using catalog-only SELECT queries. The evidence JSON now contains the 22 public relations, public/private function inventory, public/private view definitions, policy/trigger counts, and all 24 live migration version/name entries.

This is a structured catalog snapshot, not a full schema-only SQL export. Remaining evidence includes complete function bodies for non-foundation routines, grants and default privileges, extension/version metadata, and a verified local/disposable rehearsal route. Keep all queries metadata-only; never inspect user rows, chat contents, auth identities or storage object records. No remote writes, migrations, deployment or migration-history repair are authorized.


### Addendum — Expanded metadata capture

The Android-only read-only path has now captured all 37 public/private function definitions, 578 table-grant entries, 68 routine-grant entries, 136 default-privilege ACL entries, and five extension/version records. The evidence file was fetched and parsed after the update to verify these sections were committed. This remains a structured recovery snapshot rather than a complete schema-only dump; full Auth/Storage DDL, role attributes/membership, event triggers and restore-order validation remain outstanding.


### Addendum — Role, event-trigger and SECURITY DEFINER review

Read-only evidence now includes non-platform role attributes and memberships, schema ACLs, seven event-trigger registrations, and both public view definitions/options. A targeted review found 17 public/private SECURITY DEFINER functions executable by authenticated, zero executable by anon, and zero with an explicit PUBLIC EXECUTE grant. All 17 definitions are stored for review. Because they are under the private schema and contain identity/permission checks, this is not labeled a vulnerability without verifying Data API exposed schemas and call paths. No grants, roles, functions, policies or schema settings were changed.


### Addendum — API exposure, RLS privacy and advisors (2026-11-14)

Read-only review confirms the only relation with anon SELECT grant in public is `public_buyer_demands`. That view is configured `security_invoker=true` and its selected columns exclude `buyer_id`; the underlying `buyer_demands` table does contain `buyer_id`, but anon has no SELECT grant on that base table. All public tables have RLS enabled, and no RLS-enabled public table was found without policies. The `private` schema denies USAGE to anon and grants it to authenticated. This is structural evidence only, not an end-to-end HTTP security test.

The exact PostgREST Exposed Schemas list remains unverified: `current_setting('pgrst.db_schemas', true)` returned NULL and no role/database-level override was found. Verify in Dashboard > Project Settings > Data API before any conclusion about schema exposure.

Advisors report: leaked-password protection disabled (WARN); 6 unindexed foreign keys (INFO); 20 unused-index candidates (INFO); 8 multiple-permissive-policy warnings (WARN). No changes were made. Do not blindly drop unused indexes or merge permissive policies: first validate workload and logical equivalence. Evidence JSON includes this audit snapshot.


### Addendum — Profile protection and marketplace guest visibility

Captured four profile/business trigger function definitions. The profile guards structurally restrict buyer self-edits to full_name, prevent self-changing role/account_status, and require admin approval for seller/porter profile changes. Business public projection is synchronized only for approved businesses. The public profile update guard uses deprecated `auth.role()`; consider replacing with current role-check pattern in a reviewed development migration, but do not alter Live until behavior is verified.

Anon SELECT is granted only on `public_buyer_demands`; products and `public_businesses` are currently SELECT-accessible to authenticated but not anon. This could affect logged-out Marketplace browsing, but is not classified as a defect until guest browsing is confirmed as a product requirement. No grants or policies were changed.


### 2026-11-14 reconciliation correction and migration ledger

Correction: the previous anon access summary considered only table-level grants. Catalog inspection shows explicit column-level SELECT grants for anon on selected product fields and public-business fields. Product RLS allows only approved listings belonging to a public business; public_businesses is a safe projection with business_id, display_name, country, city. Sensitive product columns such as seller_id, reviewed_by, reviewed_at and admin_note are not granted to anon. Public Buyer Demand projection omits buyer_id. This is structural evidence that guest Marketplace read is enabled for selected columns; still requires HTTP/API behavior testing.

Migration inventory: branch contains 40 SQL files and 39 unique migration versions; Live history has 24 entries. Thirteen version/name pairs match; 27 branch-only files (26 unique versions); 11 Live-only entries. Two pairs are exact duplicate SQL contents: versions 20261112051711 and 20261112051801; versions 20261112051906 and 20261112052010. Two unrelated migrations share version 20261114180000, which must be resolved to unique timestamps before running the migration chain. Do not run or repair history remotely.

Current Live catalog contains evidence for several effects from Live-only migrations: product pricing columns; anon approved-product RLS; safe column-level anon grants; public-business anon projection; private SECURITY DEFINER/public SECURITY INVOKER public-business helper; cancelled account status constraint; AAL2-enforcing admin helper functions; and a security-invoker Buyer Demand projection without buyer_id. Object-level presence does not establish exact SQL equivalence or migration reproducibility.

Snapshot JSON records the complete version/name ledger, branch-only/live-only lists, duplicate version/content SHA evidence, and corrected anon column grants. No Live writes, migrations, or private user-data reads were performed.
