# NEXORA Migration Comparison Ledger

**Audit date:** 2026-11-13  
**Repository:** `shaifrony/nexora-platform1`  
**Branch:** `nexora-development`  
**Branch HEAD audited:** `3b05368cc44e2d21a5895582144a9b65c781f930`  
**Supabase project:** `qsjdeqljpnjumceewsjq`  
**Method:** Read-only GitHub migration directory + Supabase migration history comparison  
**Safety:** No SQL executed; no live schema or migration history changed.

## 1. Executive result

| Comparison | Count |
|---|---:|
| GitHub SQL migration files | 36 |
| Supabase migration history entries | 24 |
| Same version and same migration name | 13 |
| GitHub files whose version is absent from live history | 23 |
| Live history entries with no same-version GitHub file | 11 |
| Version/name mismatches | 0 |

**Interpretation:** This is a filename/version ledger only. A version present in history does not prove the corresponding SQL file is identical to what was applied. A file absent from history does not prove its effects are absent from the current schema. None of the 23 files absent from history is labelled “safe to run” by this comparison.

## 2. GitHub migration file ledger (36)

Statuses:
- `MATCHED_VERSION_AND_NAME`: same version and name appears in live migration history; SQL effect equivalence still unverified.
- `FILE_NOT_IN_LIVE_HISTORY`: no same-version entry in live migration history; inspect live schema before deciding whether to apply, reconcile, or retire.

| # | Version | Migration file | Ledger status | Notes |
|---:|---|---|---|---|
| 1 | `20261112045441` | `revoke_public_rls_auto_enable_execute` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 2 | `20261112050241` | `secure_public_profile_identity_projection` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 3 | `20261112050345` | `create_marketplace_core_schema` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 4 | `20261112050553` | `optimize_marketplace_rls_and_fk_indexes` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 5 | `20261112050854` | `create_private_communications` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 6 | `20261112050951` | `harden_private_communications_rls` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 7 | `20261112051022` | `allow_invitees_to_view_chat_invitation` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 8 | `20261112051711` | `update_conversation_timestamp_on_message` | MATCHED_VERSION_AND_NAME | Duplicate content pair A; live has this version |
| 9 | `20261112051801` | `update_conversation_timestamp_on_message` | FILE_NOT_IN_LIVE_HISTORY | Duplicate content pair A; same blob as 51711 |
| 10 | `20261112051906` | `fix_conversation_insert_returning_visibility` | MATCHED_VERSION_AND_NAME | Duplicate content pair B; live has this version |
| 11 | `20261112052010` | `fix_conversation_insert_returning_visibility` | FILE_NOT_IN_LIVE_HISTORY | Duplicate content pair B; same blob as 51906 |
| 12 | `20261112151344` | `enforce_aal2_on_admin_metadata_reads` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 13 | `20261112151436` | `optimize_aal2_policy_initplans` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 14 | `20261112151504` | `centralize_admin_mfa_rls_check` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 15 | `20261112153000` | `publish_open_demands_without_buyer_identity` | FILE_NOT_IN_LIVE_HISTORY | Related live entry uses version 153453 |
| 16 | `20261112162234` | `create_product_inquiry_request` | MATCHED_VERSION_AND_NAME | SQL equivalence not verified |
| 17 | `20261113100000` | `create_porter_delivery_workflow` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 18 | `20261113180000` | `transport_provider_vehicle_model` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 19 | `20261113200000` | `transport_provider_admin_review` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 20 | `20261113220000` | `delivery_assignment_system` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 21 | `20261113230000` | `buyer_seller_market_categories` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 22 | `20261113235900` | `product_market_category` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 23 | `20261114090000` | `services_marketplace` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 24 | `20261114100000` | `listing_image_storage` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 25 | `20261114110000` | `seller_listing_edit` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 26 | `20261114120000` | `listing_edit_review_workflow` | FILE_NOT_IN_LIVE_HISTORY | Full SQL syntax/business-rule review required |
| 27 | `20261114130000` | `listing_edit_history` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 28 | `20261114130100` | `verified_purchase_reviews` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 29 | `20261114140000` | `commerce_orders_and_review_completion` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 30 | `20261114150000` | `product_inventory_moq_quantity_pricing` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 31 | `20261114160000` | `demand_inbox_quotations_subcategories` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 32 | `20261114170000` | `delivery_network_management` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 33 | `20261114180000` | `unified_delivery_jobs_assignment` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 34 | `20261114190000` | `delivery_tracking_status_history` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 35 | `20261114200000` | `centralized_officer_account_management` | FILE_NOT_IN_LIVE_HISTORY | Schema/dependency audit required |
| 36 | `20261114210000` | `porter_public_registration_and_review` | FILE_NOT_IN_LIVE_HISTORY | Staged only; never executed on live DB |

## 3. Live migration history entries without a same-version GitHub file (11)

| # | Live version | Live migration name | Finding |
|---:|---|---|---|
| 1 | `20261112063728` | `add_wholesale_product_pricing_fields` | Original SQL file not found |
| 2 | `20261112092911` | `restrict_public_products_to_approved_businesses` | Original SQL file not found |
| 3 | `20261112093024` | `limit_anonymous_product_columns` | Original SQL file not found |
| 4 | `20261112093107` | `expose_safe_public_business_check_for_anon_policy` | Original SQL file not found |
| 5 | `20261112094305` | `public_business_safe_anon_read` | Original SQL file not found |
| 6 | `20261112094341` | `make_public_business_check_invoker_safe` | Original SQL file not found |
| 7 | `20261112094441` | `revoke_postgres_default_public_api_grants` | Original SQL file not found |
| 8 | `20261112115158` | `allow_cancelled_account_status` | Original SQL file not found |
| 9 | `20261112145135` | `require_aal2_for_nexora_admin_access` | Original SQL file not found |
| 10 | `20261112153453` | `publish_open_demands_without_buyer_identity` | Similar-name GitHub file exists at 153000; version differs |
| 11 | `20261112160835` | `secure_public_buyer_demand_projection` | Original SQL file not found |

The original SQL for these 11 versions was not recovered in the prior repository/backup search. Do not fabricate historical files or claim reconstructed SQL is original.

## 4. Duplicate-content findings

| Pair | File A | File B | Shared Git blob SHA | Live history |
|---|---|---|---|---|
| A | `20261112051711_update_conversation_timestamp_on_message.sql` | `20261112051801_update_conversation_timestamp_on_message.sql` | `2e053e7bf7b47c089e70218c2b2397686cf153dc` | 51711 present; 51801 absent |
| B | `20261112051906_fix_conversation_insert_returning_visibility.sql` | `20261112052010_fix_conversation_insert_returning_visibility.sql` | `bd3d3d323c81d9d265f927ffa8affca4eeb1d974` | 51906 present; 52010 absent |

**Decision:** no files deleted, renamed or moved. Treat the later versions as duplicate candidates pending a reviewed archive/canonicalization proposal.

## 5. Buyer Demand timestamp mismatch

- GitHub file: `20261112153000_publish_open_demands_without_buyer_identity.sql`
- Live history entry: `20261112153453_publish_open_demands_without_buyer_identity`

Earlier read-only schema inspection observed a public open-demand policy and safe column grants excluding `buyer_id`, consistent with the intended behavior of the GitHub file. This does not prove exact SQL identity or explain the four-minute version difference. Preserve both identifiers in all future records.

## 6. Classification and next review queue

| Priority | Scope | Current classification | Next required evidence |
|---|---|---|---|
| P0 | 11 live-only migration versions | Missing historical source | Exact live object definitions, grants, policies, functions, triggers and constraints related to each change |
| P0 | 23 files absent from history | Unclassified; not safe-to-run | Compare every file's intended effects with current live schema |
| P0 | `14120000` listing edit review | Blocked pending full review | Entire SQL file, parser result, transaction boundary and wholesale-only category validation |
| P1 | Duplicate pairs | Duplicate candidates | Full content/hash evidence and reference/dependency review |
| P1 | Buyer Demand version mismatch | Functionally similar, not proven identical | Full SQL diff against observed live policy/view/grants |
| P1 | Feature dependency graph | Preliminary only | Extract referenced objects and verify exact creation order |

### Classification rules

Each migration must ultimately receive one reviewed decision:
- **APPLIED_EQUIVALENT** — effects verified in live schema; do not rerun.
- **NOT_APPLIED_REQUIRED** — effects absent and migration is safe after dependency/test review.
- **PARTIALLY_APPLIED** — some effects exist; requires a dedicated reconciliation plan.
- **SUPERSEDED_DUPLICATE** — duplicate or superseded; preserve historical file and document canonical path.
- **BLOCKED** — syntax, security, dependency, data, or business-rule concern remains.
- **SOURCE_MISSING** — live history entry exists but original source cannot be recovered.

No classification in this ledger authorizes SQL execution.

## 7. Immediate next audit

1. Inspect all 11 live-only migrations by identifying their exact object effects from the live catalog and schema definitions.
2. Read every one of the 23 not-in-history SQL files in full and map every referenced object.
3. Fully review `20261114120000_listing_edit_review_workflow.sql`.
4. Build the dependency graph from actual SQL references.
5. Prepare a reconciliation proposal only after the above evidence is complete.

## 8. Safety and audit record

- Supabase migration history was read only.
- GitHub migration directory was read only for this comparison.
- This ledger is a new documentation file; it does not modify any SQL migration.
- No live SQL, migration history, RLS, grants, schema, data, production deployment, `main` branch, or paid resource was changed.


## 9. Recovery package status (2026-11-13)

A recovery package now exists at `supabase/recovery-not-for-deployment/` on `nexora-development`. It includes one SQL file for each of the 11 live-only history entries.

| Classification | Count | Meaning |
|---|---:|---|
| SQL body source-recovered from a GitHub commit, but version differs | 1 | Open-demand publication body; GitHub source is 153000, Live history is 153453 |
| Catalog-based reconstruction drafts | 10 | Recreated from current Live catalog definitions/ACLs; not original SQL text |
| Original historical SQL files recovered byte-for-byte | 0 | No original file was found in checked branches/commit history |

The recovery package README documents the exact source status and evidence for each file. All 12 package files (README plus 11 SQL drafts) were fetched back from GitHub to verify they exist.

**Do not treat the package as a runnable migration sequence.** It is outside `supabase/migrations/`, has not been statically certified or tested against an isolated database, and has not been executed. In particular, the default-privilege draft requires extra scope review.

The prior statement “original SQL not recovered” remains true for all 11 exact historical files. One migration body has a related GitHub source with a timestamp mismatch; the other ten are new reconstructions.


## 10. Draft audit result (2026-11-13)

See [NEXORA_MISSING_MIGRATION_DRAFT_AUDIT.md](NEXORA_MISSING_MIGRATION_DRAFT_AUDIT.md) for the detailed 11-file review and inferred dependency map.

The current live catalog supports the public product/business allowlists, wholesale price columns/constraints, AAL2 helper definition, cancelled status constraint and safe buyer-demand view represented in the drafts. The default-privilege draft was narrowed during audit to API-facing grants and preserves service_role defaults. These are catalog-consistency findings, not proof of original SQL.

No PostgreSQL parser or isolated migration replay was available. No draft was executed, and none is approved for Live deployment.
