# NEXORA Migration Recovery Plan

**Status:** Planning document — no database changes executed  
**Target branch:** `nexora-development`  
**Repository:** `shaifrony/nexora-platform1`  
**Latest verified branch HEAD (2026-11-14):** `bc008ceb4e8f1906c3359f70bc1fccd2322bda45`

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
| SQL migration files in GitHub branch | 40 |
| Applied entries in live Supabase migration history | 24 |
| Migration versions present in both places | 13 |
| GitHub migration files absent from live history | 27 (26 unique versions) |
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

The refreshed audit found 27 SQL files in the GitHub branch that did not have matching versions in live migration history (26 unique versions because of one duplicate version collision). This is not, by itself, proof that all 23 are safe or pending to run. The list includes later feature work as well as migrations that may overlap with live state.

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

`20261114120000_listing_edit_review_workflow.sql` was previously flagged for malformed/incomplete appended fragments and a currency regex issue. A source-only repair has since been committed on `nexora-development`: the orphan duplicate tail was removed, the currency/price regex was corrected, and static checks found one BEGIN/COMMIT pair, four function definitions and balanced dollar-quote delimiters. PostgreSQL parser/runtime validation remains unavailable; do not call this SQL-runtime certified.

Before it can be considered executable:
1. Read the entire file, not selected snippets.
2. Validate every quote, dollar-quoted block, statement terminator and transaction boundary.
3. Check whether statements after `COMMIT;` are intentional and valid.
4. Verify referenced tables, columns, constraints, policies, functions and grants exist in dependency order.
5. Confirm the unified Marketplace decision: no Wholesale/Retail product sale-category split. Transport delivery modes remain separate logistics concepts.
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
| Marketplace | Unified product catalog without Wholesale/Retail sale-category split; product visibility and Seller approval |
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


## 2026-11-14 — Dependency audit and static safety fixes

Static dependency graph is consistent for the main workflow: marketplace/products and private communications precede product inquiry; transport provider/vehicle foundation precedes legacy assignment; delivery network + commerce orders + legacy delivery jobs precede unified delivery assignment; tracking follows unified assignment. However, the two separate migrations timestamped `20261114180000` collide and must not be run until a supported CLI-generated unique version is assigned.

Static source corrections on `nexora-development`:
- Officer management now rejects NULL actions and correctly accumulates whether any assigned permission is sensitive, preventing a NULL action from falling into deactivation and preventing a trailing non-sensitive permission from erasing the reason requirement.
- Unified delivery assignment now checks an assigned vehicle's `is_available` flag as well as its approval status and provider relationship.

Product model conflict: `20261113235900_product_market_category.sql` and the Retail-specific MOQ branch in `20261114150000_product_inventory_moq_quantity_pricing.sql` conflict with the current unified Marketplace decision (no separate retail/wholesale product classification; all users see all products; Sellers choose price/quantity). Remove/redesign those product category rules before rehearsal. Logistics delivery/service modes remain separate and were not modified.

The repeated `profiles_market_categories_check` in Porter registration is intentional legacy-field deprecation: it was already created in 132300 and keeps profile-level buyer/seller categories empty. It is not treated as a new defect.

CLI-based migration version repair is blocked because this workflow has no local Supabase CLI or Docker Engine. Per Supabase skill, do not hand-author a new migration filename; wait for a supported `supabase migration new` workflow. No Live writes or migration execution. Source fixes have not been SQL-runtime-tested; isolated disposable-database rehearsal is still required.


### Unified Marketplace decision alignment (2026-11-14)

The latest user decision supersedes the older dual-market and wholesale-only UI assumptions: do not split Marketplace products into Wholesale vs Retail categories; all users can view all approved products, while each Seller sets product price and quantity. Current branch source is not yet aligned: `marketplace.js` still selects/displays `market_category`, shows Wholesale/Retail badges and filters, submits `market_category` on product insert/edit, and includes Retail-specific copy; `index.html` still contains Wholesale/Retail discovery cards, seller category selectors, and market-type filters. The staged `20261113235900_product_market_category.sql` adds the product classification and `20261114150000_product_inventory_moq_quantity_pricing.sql` enforces MOQ=1 for Retail. These must be reconciled before rehearsal; no removal was made in this audit to avoid partial UI/schema changes.

The older `docs/NEXORA_BUSINESS_PROFILE_AND_PRODUCT_FORM_PROGRESS.md` statement that the form is wholesale-only is superseded by the latest decision and must be revised with the coordinated UI/schema change.


### Unified Marketplace alignment — staged source refactor completed 2026-11-14

The previous “Unified Marketplace decision alignment” section described a pending mismatch. That mismatch has now been addressed on `nexora-development` across the Frontend and staged migrations:

- `marketplace.js` and `index.html` no longer use product `market_category`, Wholesale/Retail product badges, discovery cards, seller filters, form fields or insert/edit payloads.
- Buyer/Seller profile category columns are no longer created; the migration explicitly drops obsolete columns/constraint if they exist. Porter registration no longer expects those fields.
- Listing edit/review/history SQL no longer validates, updates or snapshots product sale categories.
- Retail-only MOQ=1 validation is removed. Seller-defined MOQ, price tiers, stock tracking, reservation and order controls remain.
- Demand matching and its index/trigger now match by product category/subcategory and approved Seller/business state, not product sale type.
- Transport/logistics delivery-mode terminology is intentionally retained where it refers to delivery service modes rather than product Marketplace segmentation.

Static verification fetched the modified files from GitHub. Both frontend files have zero `market_category` references; all 40 migration files were scanned in batches and the migration directory has zero active/runtime references to `market_category`, `buyer_category` or `seller_categories`. Three explicit cleanup statements in the profile migration remain to drop obsolete fields/constraint/policy; they do not create or consume those fields.

**Verification gate remains open:** no JavaScript browser test, SQL parser/runtime test, disposable PostgreSQL rehearsal, Data API/RLS HTTP test, or Buyer/Seller E2E has been run. No Live SQL was executed. Continue next with the migration version collision/dedup plan and arrange a disposable PostgreSQL/Supabase runtime before declaring the schema refactor tested.


**Additional migration source repair during this refactor:** `20261114120000_listing_edit_review_workflow.sql` contained several appended duplicate/incomplete function fragments after its first complete transaction, plus a malformed currency regex. Kept the first complete implementation (including active Seller, approved Business Profile, Admin permission and audit checks), removed the orphaned duplicate tail, and repaired the currency/price validation lines. Re-fetched source now has one `BEGIN`/one `COMMIT`, four function definitions, balanced `$$` and `$rpc$` delimiters, and no product sale-category references. This is static source validation only; no PostgreSQL parser/runtime test has run.


**Disposable database availability check (2026-11-14):** no existing Supabase development branches are present. A new isolated Supabase development branch is available as a testing route, but the current quote is **US$0.01344 per hour**. It has not been created. Explicit user approval of this recurring cost is required before provisioning; do not use the Live project for migration rehearsal. Android/Termux still has no local Supabase CLI or Docker Engine, so CLI-generated unique migration timestamps and a local disposable PostgreSQL rehearsal remain blocked until an approved test environment is available.


## 16. Refreshed reconciliation audit — 2026-11-14

The earlier baseline counts in Sections 2, 10 and 12 are historical and are superseded by this refreshed read-only check. The current branch was verified directly from GitHub and the current Live ledger was re-read from Supabase.

### 16.1 Current inventory

| Evidence | Refreshed observation |
|---|---:|
| GitHub SQL migration files | 40 |
| Unique branch migration versions | 39 |
| Live Supabase migration history entries | 24 |
| Exact version + name matches | 13 |
| Branch-only files | 27 |
| Branch-only unique versions | 26 |
| Live-only history entries | 11 |

Verified branch HEAD: `8aba6fb3c4c827492aef5abe0bf395e73eaaa2cf`.

### 16.2 Duplicate SQL content — exact hash evidence

| Branch files | Git blob SHA | Live history |
|---|---|---|
| `20261112051711_update_conversation_timestamp_on_message.sql` and `20261112051801_update_conversation_timestamp_on_message.sql` | `2e053e7bf7b47c089e70218c2b2397686cf153dc` | 51711 present; 51801 absent |
| `20261112051906_fix_conversation_insert_returning_visibility.sql` and `20261112052010_fix_conversation_insert_returning_visibility.sql` | `bd3d3d323c81d9d265f927ffa8affca4eeb1d974` | 51906 present; 52010 absent |

The later branch-only copies are exact byte-identical Git blobs, not merely similar SQL. They are strong candidates for exclusion from the future canonical migration sequence, but they remain untouched until the archive/canonical-source approach is reviewed. Do not delete applied files or rewrite Live history.

### 16.3 Distinct migration version collision — execution blocker

Two different SQL files use version `20261114180000`:

- `20261114180000_product_linked_private_conversations.sql`
- `20261114180000_unified_delivery_jobs_assignment.sql`

The files implement separate feature groups and are not duplicate content. Both remain in `supabase/migrations/`; no timestamp was invented and no rename was performed. A supported Supabase CLI workflow is required to generate a unique version for a new migration. The current Android/Termux environment has no Supabase CLI or local PostgreSQL/Docker Engine, so this is not yet safely repairable here. Do not execute the migration directory while the collision remains.

### 16.4 Live/branch timestamp mismatch

Branch source file:
`20261112153000_publish_open_demands_without_buyer_identity.sql`

Live history entry:
`20261112153453_publish_open_demands_without_buyer_identity`

The Live catalog snapshot contains a public Buyer Demand projection without `buyer_id` and safe anonymous access evidence. This supports functional correspondence at the object level only; it does not prove the branch SQL is the exact historical SQL. Keep both identifiers documented. Do not silently rename the branch file or insert/repair migration history.

### 16.5 Live-only entries — evidence interpretation

The 11 Live-only versions remain:
- `20261112063728_add_wholesale_product_pricing_fields`
- `20261112092911_restrict_public_products_to_approved_businesses`
- `20261112093024_limit_anonymous_product_columns`
- `20261112093107_expose_safe_public_business_check_for_anon_policy`
- `20261112094305_public_business_safe_anon_read`
- `20261112094341_make_public_business_check_invoker_safe`
- `20261112094441_revoke_postgres_default_public_api_grants`
- `20261112115158_allow_cancelled_account_status`
- `20261112145135_require_aal2_for_nexora_admin_access`
- `20261112153453_publish_open_demands_without_buyer_identity`
- `20261112160835_secure_public_buyer_demand_projection`

The current metadata snapshot contains evidence for several resulting objects/policies/grants/functions, including public product pricing fields, approved-product visibility, safe anonymous product/business column grants, public-business helper wrappers, cancelled account status, AAL2 admin helpers, and the privacy-preserving Buyer Demand view. This is not a complete per-migration semantic comparison. Do not label all 11 as reconstructed, equivalent, or safe to replay. Each requires an object-by-object comparison against the complete SQL body before a future canonical baseline is designed.

### 16.6 Current safe next steps

1. Keep the two duplicate-content pairs and the version collision unchanged until a supported migration-source plan is approved.
2. Continue static inspection of each branch-only migration and compare its resulting object definitions against metadata already captured, without reading user rows.
3. Keep all recovery SQL outside `supabase/migrations/` until it is explicitly reviewed.
4. When a free local PostgreSQL/Supabase runtime and supported CLI are available, generate any new migration with `supabase migration new`, validate the unique sequence, and rehearse on a disposable database. Do not provision a paid Supabase branch without explicit approval.
5. Do not run, repair, or insert Live migration history; do not change `main`, Production, DNS or deployment.

**Actions not taken:** no SQL was executed, no Live schema/history/data was changed, no migration file was renamed/deleted, no paid branch was created, and no private user rows/messages/auth identities/storage contents were queried.


## 17. Refreshed live-schema evidence comparison — 2026-11-14

A new read-only metadata inspection was performed after verifying the current branch HEAD and re-reading the Live migration ledger. No user rows, chat messages, Auth identity records, or Storage object contents were queried.

### 17.1 Current inventory

- Branch: `nexora-development`
- Latest HEAD: `bc008ceb4e8f1906c3359f70bc1fccd2322bda45`
- Branch migration files: 40
- Unique migration versions: 39
- Live migration-history entries: 24
- Matching version/name pairs: 13
- Branch-only files: 27 (26 unique versions)
- Live-only entries: 11
- Duplicate version collision: `20261114180000` (two different migrations)
- Exact duplicate-content pairs: two pairs, each confirmed by identical Git blob SHA.

### 17.2 Live-only migration effect comparison

The following findings compare the recorded Live migration names with the *current resulting schema metadata*. They are object-level observations, not recovered original SQL and not proof of byte-for-byte or complete semantic equivalence.

| Live-only migration | Current Live evidence | Assessment |
|---|---|---|
| `20261112063728_add_wholesale_product_pricing_fields` | `products.price_unit`, `minimum_order_quantity`, and `price_negotiable` columns and constraints exist. | Resulting pricing fields are present and remain compatible with Seller-defined product terms; original SQL unavailable. |
| `20261112092911_restrict_public_products_to_approved_businesses` | Anonymous product SELECT policy requires `listing_status='approved'` and `is_public_business(business_id)`. | Intended approval gate is visible in current policy. |
| `20261112093024_limit_anonymous_product_columns` | Anonymous SELECT is granted column-by-column on a defined safe product projection; no anonymous `seller_id` grant was observed. | Column-level public projection is present; no table-level SELECT grant was observed. |
| `20261112093107_expose_safe_public_business_check_for_anon_policy` | `public.is_public_business(uuid)` exists as SECURITY INVOKER with an empty search path and reads the safe `public_businesses` projection. | Helper is present in invoker mode. |
| `20261112094305_public_business_safe_anon_read` | `public_businesses` is a table with an anonymous SELECT policy and only `business_id`, `display_name`, `country`, and `city` exposed to anon. | Safe public business projection is present at the inspected column/policy level. |
| `20261112094341_make_public_business_check_invoker_safe` | Public helper is SECURITY INVOKER; its private counterpart is SECURITY DEFINER. | Public policy helper is invoker-mode; private helper remains separately scoped. |
| `20261112094441_revoke_postgres_default_public_api_grants` | No table-level anon SELECT grant was observed on the inspected product/business relations; selected column-level grants remain. | Current grants reflect restricted column access on inspected relations. |
| `20261112115158_allow_cancelled_account_status` | `profiles_account_status_check` includes `cancelled`. | Resulting status constraint is present. |
| `20261112145135_require_aal2_for_nexora_admin_access` | Private admin helper functions check JWT AAL2 and active admin profile/staff state; public wrappers are SECURITY INVOKER. | AAL2 guard is visible in inspected helper definitions. |
| `20261112153453_publish_open_demands_without_buyer_identity` | `public_buyer_demands` omits `buyer_id`; anon has column-level SELECT on the safe projection; base `buyer_demands` has no anon SELECT grant. | Privacy projection is present. Branch source timestamp differs (`20261112153000`); keep both identifiers documented. |
| `20261112160835_secure_public_buyer_demand_projection` | `public_buyer_demands` has `security_invoker=true` and selects only open demands; its projection omits buyer identity. | Invoker-safe public view and open-demand filter are present. |

### 17.3 Important interpretation limits

- This audit verifies current catalog objects, policy expressions, column privileges, constraints and selected function definitions only. It does not recover the original 11 SQL bodies.
- `public_businesses` is a table, not a view. Its public exposure is controlled through RLS and column-level grants.
- The public Buyer Demand view is a view with `security_invoker=true`; the underlying table's Buyer identity remains excluded from the public projection.
- These observations do not prove PostgREST HTTP behavior or end-to-end RLS behavior under real user JWTs.
- Do not recreate the missing historical SQL as if it were original. Keep any catalog-based reconstruction drafts outside `supabase/migrations/` and treat them as evidence/review material only.

### 17.4 Updated safe next action

Continue by auditing the 27 branch-only migration files against the inspected Live catalog, classifying each as pending, already represented, partial, superseded/duplicate, or blocked. Keep the two duplicate-content pairs and the `20261114180000` version collision unchanged until a supported CLI-generated repair and archive plan is available. No migration runner may be used while the collision remains.

**This refresh was read-only against Live Supabase. No schema, migration history, application data, Production, or `main` was changed.**


## 18. Branch-only migration result-object comparison — 2026-11-14

A further source-to-catalog comparison inspected the current SQL bodies for the branch-only feature migrations and compared their declared tables/functions/policies with the Live public relation inventory. This remains a metadata/source audit, not a PostgreSQL rehearsal.

### 18.1 Branch-only files that are not executable candidates yet

| Migration / group | Source and Live evidence | Classification |
|---|---|---|
| `20261113100000_create_porter_delivery_workflow.sql` | File explicitly declares itself SUPERSEDED and a no-op; it describes the retired Porter-as-user/job model. | Superseded; never execute. |
| `20261112051801` and `20261112052010` | Exact byte-identical copies of Live-applied migrations `20261112051711` and `20261112051906`, respectively. | Duplicate branch-only copies; retain evidence, do not replay. |
| `20261112153000_publish_open_demands_without_buyer_identity.sql` | Current public demand projection and safe anon column grants are already present; Live history records the corresponding name at version `20261112153453`. | Timestamp mismatch / effect already represented at object level; do not replay or rename. |
| `20261113235900_product_market_category.sql` | Despite its filename, current source no longer adds a sale-category column. It creates/replaces `private.create_product_inquiry`, changes product/public-business policies and grants, and changes product update privileges. Live already has a prior `private.create_product_inquiry` implementation and similar but differently named product policies. | Overlapping and potentially additive policy/grant/function change; blocked pending line-by-line reconciliation. Do not run simply because its version is absent. |
| `20261113230000_buyer_seller_market_categories.sql` | Current source removes legacy profile category fields and changes `handle_new_user`; the current Live profile column inventory no longer contains those category fields. | Partly represented; function/trigger replacement still requires exact comparison. |
| `20261113180000_transport_provider_vehicle_model.sql` | Declares `transport_providers` and `transport_vehicles`; neither table exists in the current Live public relation inventory. | New feature schema absent; pending candidate after dependency/security review. |
| `20261113200000_transport_provider_admin_review.sql` | Adds/replaces provider and vehicle review functions; their target provider/vehicle tables are absent in Live. | Depends on the preceding transport schema; blocked until that migration is reviewed. |
| `20261113220000_delivery_assignment_system.sql` | Declares `delivery_jobs` and `delivery_job_events`; neither exists in Live. | New feature schema absent; dependency prerequisite for later delivery migrations. |
| `20261114090000_services_marketplace.sql` | Declares `service_listings`; absent in Live. | New feature schema absent; pending candidate. |
| `20261114100000_listing_image_storage.sql` and `20261114110000_seller_listing_edit.sql` | Both alter `service_listings`; the listing image bucket `nexora-listing-images` was not found in Storage bucket metadata. | Depend on Services Marketplace; storage policy/bucket effects absent from inspected metadata. |
| `20261114120000_listing_edit_review_workflow.sql` and `20261114130000_listing_edit_history.sql` | Declare `listing_edit_requests` and `listing_edit_request_events`; neither exists in Live. | New workflow schema absent; source has static repairs but no SQL runtime validation. |
| `20261114130100_verified_purchase_reviews.sql` | Declares `review_purchase_eligibility` and `listing_reviews`; neither exists in Live. | New feature schema absent; depends on commerce/order model. |
| `20261114140000_commerce_orders_and_review_completion.sql` | Declares `commerce_orders` and `commerce_order_events`; neither exists in Live. | New feature schema absent; review/commerce dependency chain required. |
| `20261114150000_product_inventory_moq_quantity_pricing.sql` | Alters existing `products` and creates validation/inventory functions. Current Live products already have `minimum_order_quantity`, `price_unit`, and `price_negotiable`; current Live schema does not yet prove all inventory/quantity-tier objects are represented. | Partly overlapping; inspect every altered column, function and trigger before classifying or applying. Retail-specific MOQ=1 rule has already been removed from staged source. |
| `20261114160000_demand_inbox_quotations_subcategories.sql` | Existing Live `buyer_demands` and `seller_offers` tables exist, but `buyer_demand_inbox` is absent. Source adds routing functions/triggers and taxonomy changes. | Partly overlapping; inbox/routing objects absent, existing table alterations require column-by-column reconciliation. |
| `20261114170000_delivery_network_management.sql` | Declares `delivery_network_partners` and `delivery_network_staff`; absent in Live. | New feature schema absent; depends on transport/provider foundation. |
| `20261114180000_product_linked_private_conversations.sql` | Existing `conversations` table is present, but the product-context columns and context guard trigger are not present in the inspected Live catalog. It also replaces `private.create_product_inquiry`. | Partial schema extension; version collision makes the entire migration sequence blocked. |
| `20261114180000_unified_delivery_jobs_assignment.sql` | Alters `delivery_jobs` and declares `delivery_job_assignment_history`; delivery job base table is absent in Live. | Depends on delivery assignment and delivery network migrations; same version collision; blocked. |
| `20261114190000_delivery_tracking_status_history.sql` | Declares `delivery_tracking_events`; absent in Live. | Depends on unified delivery assignment; pending after prerequisites. |
| `20261114200000_centralized_officer_account_management.sql` | `admin_staff` exists in Live, but the branch migration's management RPC is not yet proven present/equivalent. | Partial overlap; inspect function grants, permission checks and audit effects before any future reconciliation. |
| `20261114210000_porter_public_registration_and_review.sql` | Declares `porter_account_reviews`; absent in Live; also changes signup/profile trigger behavior. | New review schema plus sensitive signup-trigger replacement; blocked pending trigger/function and RLS audit. |
| `20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql` | Declares `seller_offer_negotiations` and alters `commerce_orders`; both are absent in Live. | New negotiation/order-conversion workflow; depends on commerce orders and Demand inbox/offer schema. |
| `20261115110000_product_price_negotiation.sql` | Declares `product_price_negotiations` and `product_price_negotiation_events`; absent in Live. | New feature schema; pending source/security review. |
| `20261115120000_multilingual_chat_foundation.sql` | Declares `user_language_preferences` and `message_translations`; absent in Live. | New feature schema; translation remains disabled in production and must not modify original messages. |

### 18.2 Key findings

- Live currently has 20 public tables and 2 views. The relation inventory confirms that core Marketplace, Buyer Demand, Seller Offers, conversations and admin foundation tables exist.
- Several later feature tables declared by branch-only migrations are absent in Live. Absence is evidence that those table effects are not currently represented; it is not, by itself, approval to run the migrations.
- Some migrations mix new objects with changes to existing Live tables/functions/policies. Those are the highest-risk replay candidates and must be reconciled object by object.
- The `20261113235900` source filename is now misleading: its current body no longer creates product `market_category`; it changes public visibility grants/policies and Product Inquiry RPC behavior. The current Live schema already has overlapping visibility controls and an older Inquiry RPC. Do not treat it as a simple new migration.
- The `20261114180000` collision remains a hard stop for any migration runner. No timestamps were invented.

### 18.3 Next source-only audit

1. Compare the full definitions of the branch-only functions and triggers that replace existing Live objects, especially `handle_new_user`, `create_product_inquiry`, listing edit/review RPCs, demand routing, admin management and Porter review.
2. For each partly overlapping migration, list exact pre-existing columns, constraints, policies, grants and functions, then mark each statement as already represented, additive, conflicting or absent.
3. Keep new feature migrations in dependency order but do not apply them.
4. Maintain all source changes on `nexora-development`; no Live writes, no paid branch, no Production or `main` changes.

**No SQL migration was applied. No user data was read.**


## 18. Product-linked private conversation migration — branch/live comparison

Read-only inspection was repeated on the current branch and Live catalog.

- Current verified branch HEAD before this documentation change: `3dc6b5be89254b978e864d23fbf16dedd11beef5`.
- Branch source `20261114180000_product_linked_private_conversations.sql` (blob `10816b40e1ca6a7352fe8cccab8be7ccabe8013c`) contains the newer product-context columns, constraints, unique active-thread index, inquiry function and immutable-context trigger.
- Live `public.conversations` currently has **zero** columns matching `context_%`, zero matching context constraints and zero product-context indexes.
- Live private `create_product_inquiry(uuid,text)` remains the earlier implementation: it creates a generic direct conversation, adds Buyer and pending Seller participants, but does not store product context or an optional first message.
- Live public wrapper is SECURITY INVOKER; execute privilege observed for authenticated and not anon. Private implementation is SECURITY DEFINER with empty search_path; execute privilege observed for authenticated and not anon.
- The branch source additionally validates an active Seller profile, snapshots product context, prevents duplicate active product threads and writes an optional first message only for a newly created thread. These behaviors are **not yet present in Live**.
- Live conversation RLS metadata currently allows authenticated conversation reads for creator/member/invited users and updates for member/creator; private membership helpers use `auth.uid()`. This is metadata inspection only, not JWT/RLS behavioral testing.

### Assessment

This migration is genuinely pending on Live at the product-context object level; it must not be classified as already applied merely because a similarly named function exists. The shared version `20261114180000` remains a hard blocker because the delivery-assignment migration also uses that version. Do not run either file, rename either file manually, or repair migration history in Live.

### Static review notes

The branch SQL includes explicit function revokes/grants, `SECURITY DEFINER SET search_path = ''`, an authenticated-only public invoker wrapper, active Buyer and Seller checks, approved product/business checks, and immutable product-context fields. Static review cannot prove PostgreSQL parser acceptance, concurrent uniqueness behavior, message RLS acceptance, or runtime transaction behavior. These require an isolated PostgreSQL/Supabase test environment.

No Live writes, schema changes, migration-history repairs, private message reads, user-row reads, or storage-content reads were performed.


## 19. Transport Provider, Delivery Network and Porter approval — Live comparison

Read-only catalog checks were performed after re-verifying branch HEAD `4ecaf5223b27338e7c2b301e3e529e8b2073ace7`.

### 19.1 Result-level findings

| Branch migration | Live catalog observation | Classification |
|---|---|---|
| `20261113100000_create_porter_delivery_workflow.sql` | File is explicitly marked SUPERSEDED and is a no-op; do not deploy. | Retired source; not a pending schema migration |
| `20261113180000_transport_provider_vehicle_model.sql` | `transport_providers` and `transport_vehicles` relations are absent from Live. | Pending |
| `20261113200000_transport_provider_admin_review.sql` | Provider/vehicle review functions are absent; dependent tables are also absent. | Pending, depends on provider/vehicle base |
| `20261113220000_delivery_assignment_system.sql` | `delivery_jobs` relation is absent. | Pending |
| `20261114170000_delivery_network_management.sql` | Delivery Network job/assignment objects are absent from Live. | Pending; depends on provider/vehicle and delivery job base |
| `20261114180000_unified_delivery_jobs_assignment.sql` | Unified assignment objects are staged in branch; Live delivery job base and network relations are absent. | Pending, but blocked by duplicate version collision |
| `20261114190000_delivery_tracking_status_history.sql` | `delivery_tracking_events` relation and status update RPCs are absent. | Pending; depends on unified delivery assignment |
| `20261114210000_porter_public_registration_and_review.sql` | Live role check already permits buyer/seller/porter/admin and role_requests requested_role permits seller/porter; however `porter_account_reviews` table and `review_porter_account` RPC are absent. | Partially represented / pending review workflow |

### 19.2 Porter registration nuance

Live metadata confirms `profiles_role_check` already includes `porter`, and `role_requests_requested_role_check` includes `porter`. However this does **not** prove that the new public-registration workflow is installed. The review table and review RPC are absent. The current Live `handle_new_user()` is SECURITY DEFINER and is not executable directly by anon/authenticated roles; its trigger behavior was not functionally tested and its complete definition was not used to assert the staged Porter review behavior.

Do not mark Porter Admin approval as complete until `porter_account_reviews`, the updated Auth trigger, account-status transition logic, and the Admin AAL2 review RPC have been safely deployed and tested in an isolated environment.

### 19.3 Important sequencing and dependency notes

- The legacy individual-Porter delivery workflow migration is intentionally a no-op. Keep it as historical source; do not revive its user-ID job assignment model.
- The transport-provider/vehicle model is the prerequisite for provider-owned vehicle dispatch.
- Provider/vehicle Admin review depends on the base transport tables and Admin logistics permissions.
- Delivery assignment base precedes unified network assignment; tracking follows the unified assignment model.
- Porter account approval is a separate account activation gate. Transport Provider and Vehicle approval are separate operational gates; approval of one must not silently imply approval of the others.
- Version `20261114180000` remains shared by the product-conversation and unified-delivery-assignment migration files. This remains a hard migration-runner blocker.

### 19.4 Limits and safety

This is an object/catalog-level comparison, not recovery of historical SQL bodies or runtime proof. No user rows, chat messages, Auth identity records, or Storage object contents were read. No Live write, schema change, migration-history repair, or migration execution occurred. PostgreSQL parser, JWT/RLS behavior, concurrency and end-to-end delivery workflow tests remain unavailable without an isolated DB/runtime.
