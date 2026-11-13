# NEXORA Buyer Demand Progress

Updated: 2026-11-13

## Current status (2026-11-14)

- Buyer Demand → Seller quotation → Buyer/Seller counter-offer → acceptance/rejection → source-linked Commerce Order → order status transitions is implemented in staged frontend and migration source.
- Server-side source checks include active Buyer/Seller role, Demand ownership / assigned Seller, latest-proposal turn-taking, positive quantity and price, offer expiry, open Demand status, and role/state-guarded order transitions.
- Buyer acceptance creates a pending order for Seller confirmation. Seller acceptance of the Buyer’s latest counter-offer creates an accepted order and records an accepted event.
- Buyer and Seller order cards display delivery-inclusive `grand_total`, with a delivery-charge breakdown when non-zero.
- Syntax-only JavaScript checks and isolated required-date/order-total logic checks are documented as passed. No SQL runtime, full-schema isolated migration rehearsal, hosted JWT/PostgREST/RLS, concurrency, or browser E2E test has passed for this workflow. The local installed-contract audit is staged but cannot yet run against the current limited reconstructed fixture.
- Therefore this is **source implementation complete for the core Demand negotiation path, integration verification pending**; it is not a completed/released Buyer module.

## Scope

This document records the current Buyer Demand implementation inspected on the `nexora-development` branch. It is a code review snapshot, not a hosted deployment or runtime test report.

## Current Buyer Demand form

The existing `index.html` form with ID `demandForm` currently collects:

1. Product name (required)
2. Category (required)
3. Product subcategory / specific type (required)
4. Description (required)
5. Specifications and quality requirements (required)
6. Required quantity (required)
7. Budget (optional)
8. Currency (required)
9. Destination country (required)
10. Destination city / destination (required)
11. Required date (required)

The form includes a date input whose minimum is set client-side to the user's local current date during page initialization.

## Current submission behavior

The initial marketplace core migration (`20261112050345_create_marketplace_core_schema.sql`) defines `buyer_demands` without a `subcategory` column. The later migration `20261114160000_demand_inbox_quotations_subcategories.sql` adds the column and updates the public Demand view and grants. The final migration chain still requires local rehearsal because the repository migration history is not reconciled with Hosted Supabase.

The `marketplace.js` submit handler:
- Requires an active Buyer session.
- Validates optional budget as a non-negative number.
- Inserts the Buyer ID from the authenticated session, not from a form field.
- Sends product/category/subcategory, description, specifications, required quantity, optional budget, currency, destination country/city and required date to `buyer_demands`.
- Shows a success message and returns the Buyer to the dashboard after successful insert.

The public demand board reads from `public_buyer_demands`, not directly from `buyer_demands`. Its client query selects demand fields such as product name, category, description, specifications, quantity, budget, currency, destination and required date. It does not request Buyer ID, name, email, phone or other direct contact fields.

The Seller Demand Inbox reads from `buyer_demand_inbox` and filters by the logged-in Seller ID; it requires an Admin-approved Business Profile before showing matched demands or accepting quotations.

## Important verification boundary

The frontend query shape is not sufficient proof of database privacy. The underlying view definition, grants, RLS policies, matching trigger/function and seller inbox access rules still need a schema-level review. Do not treat hidden UI fields or selected-column lists as the security boundary.

No database schema, migration, hosted Supabase project, production deployment or live data was changed during this review. No browser or hosted integration test was run.

## Next implementation/review steps

1. Inspect the exact `public_buyer_demands` view definition and grants to confirm it exposes only approved public demand fields and no Buyer identity/contact data.
2. Inspect `buyer_demands` RLS and INSERT/SELECT/UPDATE policies, including ownership and allowed status transitions.
3. Inspect demand matching logic and `buyer_demand_inbox` access to confirm only eligible approved Sellers receive relevant demand records.
4. Confirm Seller quotations cannot reveal Buyer contact data before an accepted communication/consent flow.
5. Align Demand matching with the universal visibility model: route a Buyer Demand to every eligible Seller with an approved product matching category/subcategory, regardless of Wholesale/Retail sale type; keep Buyer identity/contact private.
6. Add focused tests for privacy, ownership, unauthorized Seller access, closed/cancelled demands, required-date validation and quotation eligibility.


## 2026-11-13 — B-03 Demand privacy and routing source review

### Findings from staged migration and frontend source
- `public.public_buyer_demands` is defined as a SECURITY INVOKER view. Its intended projection includes only public Demand fields and omits `buyer_id`, Buyer name, email, phone and profile/contact fields.
- The anonymous open-Demand policy grants a limited column set on `buyer_demands`; the Buyer foreign key is not part of that grant. The later subcategory migration adds only the public subcategory column to the anon grant.
- Authenticated Buyer Demand reads are owner-scoped. The final Seller read policy allows open Demands only when the logged-in active Seller has a matching row in their own `buyer_demand_inbox`; Admin access remains separate.
- Demand INSERT policy requires an active Buyer and `buyer_id = auth.uid()`. The owner UPDATE policy only applies while the Demand is open and preserves the owner ID; the UI offers only close/cancel actions.
- `buyer_demand_inbox` has RLS, Seller-owned SELECT, and no authenticated direct INSERT/UPDATE/DELETE grant. Routing is done by private SECURITY DEFINER trigger functions.
- Seller quotation INSERT requires the active Seller's own inbox row for an open Demand. A unique constraint permits one quotation per Seller per Demand.
- Demand matching uses exact Product category and case-insensitive exact subcategory (category-only fallback for legacy Demands), approved Product listing, active Seller and the approved public-business projection. No Buyer/Seller account category or Wholesale/Retail `market_category` gate is used.
- Required date is NOT NULL and constrained to current_date or later in the core schema. Frontend demand form sends it and the public board/Seller inbox display it.
- Buyer can close or cancel only their own open Demand in the frontend. New quotation insertion is blocked when Demand is not open.
- Frontend Buyer Dashboard reads only the current Buyer's own Demands and associated Seller offers; Seller Inbox query selects only Demand fields needed to prepare a quotation and does not request Buyer identity/contact data.

### Remaining gaps / cautions
- Buyer quotation acceptance, counter-offer, negotiation chat linking and quotation-to-order conversion are not implemented.
- Seller Inbox routing and Demand SELECT policies have been source-reviewed, not exercised under real JWT/PostgREST sessions.
- The local database currently has only the limited product/business visibility fixture, not the full Demand/offer/inbox schema. No full local Demand workflow test has run.
- Added and ran read-only catalog audit: `supabase/recovery-not-for-deployment/local-setup/24_local_buyer_demand_privacy_audit.sql`. User output: `SKIP: full Marketplace Demand schema is not installed in this local database`; script completed with ROLLBACK and made no changes. This is neither PASS nor FAIL; the existing local fixture intentionally contains only business/product visibility objects.
- No migration was applied; Live Supabase, Production and `main` remain untouched.


## 2026-11-13 — Local B-03 Demand fixture authored

- Added `supabase/recovery-not-for-deployment/local-setup/25_local_buyer_demand_fixture.sql`: a guarded, reconstructed local-only schema for Buyer Demands, Seller Offers, Seller Inbox, safe public Demand projection, RLS and category/subcategory routing triggers. Requires local fixtures 06 and 21. It refuses any database except `nexora_test` and refuses existing Demand objects.
- Added `26_local_buyer_demand_behavior_tests.sql`: transactional test data is rolled back. Covers anonymous safe projection and denial of Buyer ID/private tables; Buyer ownership; Seller Inbox scoping; Wholesale + Retail matching; late product-match routing; offer submission and buyer read; unmatched Seller denial; direct inbox write denial; duplicate quotation; spoofed Buyer ID; past required date.
- Added `27_run_local_buyer_demand_tests_termux.sh`: one-command runner with local DB/schema/session preflight. Runs fixture 25, read-only audit 24, then behavior tests 26. It performs no cleanup and no migration replay.
- Fixture is a deliberately limited reconstruction, not the original complete production schema. It tests local PostgreSQL policy/trigger logic only; not actual Supabase Auth, JWT validation, PostgREST, Storage, Realtime, Edge Functions, MFA/AAL2 or browser E2E.
- User has not run the new runner yet; no B-03 local test PASS claimed. No active migration executed, no Hosted Supabase/Production/main changed.



## 2026-11-13 — B-03 local Demand behavior tests PASSED

- User ran the latest immutable Termux runner (runner commit `f202a630dc4e2503daada8ef2130cab90f3b88a6`) on local `nexora_test`; preflight passed and the existing complete Demand fixture was reused.
- Policy dependency patch applied successfully. It replaced policy subqueries that attempted direct access to private `public_businesses.seller_id` and Buyer Demand ownership with private boolean SECURITY DEFINER helpers. Authenticated has narrowly scoped EXECUTE; anon is denied; Seller ID is not exposed through a public projection.
- Read-only catalog audit: all 8 checks PASS, including RLS, SECURITY INVOKER safe view projection, public/private grants, Buyer ownership, Seller Inbox isolation, quotation constraints, required date and category/subcategory routing without a Wholesale/Retail gate.
- Behavior tests: all 12 PASS. Covered approved taxonomy routing and late product match, anonymous projection and private-data denial, Buyer ownership and cross-Buyer isolation, Wholesale and Retail Seller routing, unmatched Seller denial, direct Inbox write denial, duplicate quotation prevention, Buyer quotation read/isolation, Buyer-ID spoof denial, past required-date rejection and RLS/private ACL boundaries.
- Final output confirms test transaction ROLLBACK and all test data rolled back. Runner completed without SQL errors.
- Result: local reconstructed B-03 PostgreSQL logic test PASS. This does not establish production migration correctness or hosted Supabase Auth/JWT/PostgREST/RLS behavior. Browser E2E, Data API exposure and actual hosted role tests remain pending.
- No migration/deployment was performed; Live Supabase, Production and `main` remain untouched.


## 2026-11-14 — Buyer quotation negotiation and order workflow source review

- Reviewed the staged migration `20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql` and the Buyer/Seller frontend handlers in `marketplace.js`.
- Confirmed the Buyer Dashboard exposes accept/counter/reject actions for Seller quotations; the Seller Demand Inbox exposes accept/counter/reject actions after a Buyer counter-offer. Both call the same guarded RPC. This is source inspection only, not browser/runtime verification.
- Fixed negotiation RPC validation so a NULL action is rejected explicitly.
- Hardened Buyer Demand order transitions: only the active Buyer who owns the order or the active Seller assigned to it may change its status; NULL actions are explicitly rejected.
- Corrected order conversion when the Seller accepts a Buyer counter-offer: the new order is created as accepted with `accepted_at`, and an accepted order event is recorded. When the Buyer accepts a Seller proposal, the order remains pending for Seller confirmation.
- Re-fetched the migration after each change. Latest source checks confirm the new guards and balanced SQL function delimiters.
- Remaining verification: isolated full-schema migration rehearsal, SQL behavior tests for both acceptance paths and inactive-account denial, Supabase JWT/PostgREST/RLS checks, and browser E2E. No SQL was executed; no Live Supabase, Production, `main`, DNS or deployment was changed.


## 2026-11-14 — Negotiation turn-taking and local installed-contract audit

- Added a server-side rejection turn check: Buyer can reject only after the Seller's latest proposal; Seller can reject only after the Buyer's latest counter. A participant can no longer reject their own latest proposal by bypassing the UI.
- Added `supabase/recovery-not-for-deployment/local-setup/29_local_buyer_demand_order_contract_audit.sql`. It is guarded to `nexora_test`, runs in a read-only transaction, and checks the installed RPC source contract, active-account checks, acceptance state, negotiation-history RLS, unique source-offer order index, source consistency constraint and anon EXECUTE denial.
- Re-fetched the active migration and local audit script from GitHub. Source inspection confirms the new rejection guard, NULL-action validation, active-account checks and Seller-accepted Order state. The audit script's safety guard and key assertions are present.
- The audit script has not been executed because the local reconstructed fixtures do not include the complete commerce-order/negotiation schema and functions. No PostgreSQL client/runtime is available in this execution environment.
- Full-chain rehearsal is blocked safely: the branch lacks a trusted original foundation DDL/schema-only export for prerequisite profiles, Admin/Auth and related objects, and existing local fixtures are explicitly reconstructed, not production-equivalent. Replaying active migrations on those fixtures would create misleading results. Do not run the active migration chain until a trusted baseline and migration-history reconciliation are available.
- No migration SQL was executed; no Live Supabase, Production, `main`, DNS or deployment changed.


## 2026-11-14 — Unified product matching alignment

- Removed product Wholesale/Retail sale-type dependency from the Buyer Demand inbox workflow. New approved-product routing, open-demand backfill, matching index and trigger now use product category/subcategory plus active Seller and approved public-business status.
- Listing change request payload validation, Admin approval updates and before/after snapshots no longer require or store product `market_category`.
- This preserves universal product visibility and Seller-specific pricing/quantity terms; demand matching is based on product taxonomy, not a retail/wholesale channel.
- Static source review only. No SQL was run, and no local/hosted E2E tests are claimed.


## 2026-11-14 — Buyer Demand flow focused source audit

- Rechecked the Buyer Demand UI path from the required-by date form through Buyer Dashboard, public Demand Board, Seller Demand Inbox, Seller quotation submission, Buyer/Seller counter-offers, quotation acceptance and Buyer Demand order status transitions.
- Confirmed the form maps `requiredDate` to `buyer_demands.required_date`; Buyer and Seller views display the same required date. Public Demand projection selects no Buyer identity/contact fields.
- Confirmed Buyer and Seller quotation actions call the same guarded `respond_to_demand_offer` RPC; the SQL contract checks active account role, Demand ownership / assigned Seller, latest-proposal turn, positive quantity and unit price, offer expiry and open Demand state.
- Confirmed acceptance creates one source-linked `buyer_demand` Commerce Order. Buyer acceptance creates a pending order for Seller confirmation; Seller acceptance of a Buyer counter-offer creates an accepted order and event. Order transition RPC restricts accept/ready/reject to assigned Seller and complete/cancel to the owning Buyer in the allowed prior state.
- Improved the Buyer Demand date input: it now sets the local current date as the minimum and rejects a missing/past required date before insert. Database validation remains authoritative.
- This is source inspection only. No browser, SQL runtime, disposable DB, hosted Supabase JWT/PostgREST or E2E test was run. The Commerce Order migration remains staged and blocked by migration-history/version reconciliation.

- Follow-up order-total review found both Buyer and Seller order cards displayed the legacy item subtotal (`total_price`) instead of the staged delivery-inclusive `grand_total`. Updated both views to show the final total and, when non-zero, a separate delivery-charge breakdown. Code commit: `5b64818391d022688c85cdd17c5d3c0092191d62`.

- After the order-card markup update, parsed the complete `marketplace.js` source with a JavaScript V8 compiler check (syntax-only; code not executed): PASS. Separately compiled both Buyer and Seller order-card render expressions: PASS. This does not replace browser/runtime or Supabase integration testing. Final order-card markup repair commit: `d839546f4a8cf602ab2da350f3989e5e8a8848ca`.
- Ran small synthetic logic checks for the required-date rule (today/future accepted; past/empty rejected) and delivery-inclusive totals (including zero delivery and fractional quantities): all cases passed. These are isolated logic checks, not browser or database integration tests.


## 2026-11-14 — Current negotiation and order implementation status

- This section supersedes earlier statements in this document that described quotation acceptance/counter-offer/order conversion as unimplemented. The staged UI and migration now include these actions and guarded RPC paths.
- Reconciled Buyer Completion Checklist and Work Tracker to match the current source. No database changes were made.


## 2026-11-14 — Buyer order workflow verification review

### Static source review
- Reviewed the full Buyer/Seller quotation UI paths and the negotiation/order migration sections.
- Confirmed staged server-side checks for active Buyer/Seller role, Buyer Demand ownership, assigned Seller identity, open Demand, offer expiry, latest-proposal turn-taking, positive quantity/price, Seller availability ceiling, unique Commerce Order per source offer, and role/status-guarded order transitions.
- Confirmed `seller_offer_negotiations` is RLS-enabled, authenticated SELECT is participant-scoped, and direct table privileges are limited to SELECT; mutation is routed through RPCs.
- Confirmed `commerce_orders.grand_total` is generated from quantity × unit price + delivery charge.
- Found and fixed a misleading Buyer success message: Buyer acceptance creates a pending order awaiting Seller confirmation (not an immediately accepted order). Code commit: `db377422c117cab4bf9acf851da9e1407e21cb08`.

### Verification limits / NOT PASS
- No SQL execution, migration replay, Disposable Database, live JWT/PostgREST/RLS, concurrency, or browser E2E test was run. These remain BLOCKED by the known migration version collision and lack of a complete trusted local schema/runtime; no hosted writes permitted.
- Latest GitHub Actions run available at review time was GitHub Pages build/deployment for earlier commit `77a31085e01746ec6fcd4030dd3b07c9e8c64bd2` (success); it is not a Buyer test suite and does not cover the later Buyer message fix.
- Do not label the Buyer module fully tested or complete. Static source review only.


### 2026-11-14 — Preserve exact total-price quotations during Order conversion

- Static financial-flow review found a rounding defect: a Seller's total-price quotation (for example, BDT 100 for 3 units) was divided into a two-decimal unit price (BDT 33.33), so converting the full quote could create an Order subtotal of BDT 99.99.
- Updated the staged Buyer Demand quotation/order migration to store the exact agreed goods subtotal in `commerce_orders.source_offer_total`; generated `grand_total` now uses that exact subtotal plus delivery charge. Product/service orders continue to fall back to quantity × unit price.
- For an original total-price quotation, the accepted subtotal is prorated from the original total against the quoted available quantity and rounded once to currency precision. Counter-offers continue to use quantity × negotiated unit price.
- Updated Buyer and Seller order queries and delivery-charge breakdowns to display `source_offer_total` when present, falling back to the legacy generated `total_price` for other orders.
- Development-branch commits: migration `84d97644765dbcc08b63f3309a0d193f6d2f3826`; frontend `db24dec3314dee3b5b26f9b25e8bd229009ba1ec`. Both files were fetched back; source-column, generated-total, proportional-calculation, INSERT and both UI query/display references were verified.
- Arithmetic spot-check by formula: BDT 100 / 3 units → 3 units = BDT 100.00; 2 units = BDT 66.67; adding BDT 5 delivery charge to the full quote gives BDT 105.00.
- This is static source and arithmetic verification only. No SQL parser/runtime, migration replay, disposable DB, browser, or order E2E test was run. Keep the Buyer module marked NOT PASS until those tests are available.
