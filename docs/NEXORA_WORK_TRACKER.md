# NEXORA Work Tracker

Updated: 2026-11-13

Latest marketplace progress: [Business Profile & Product Form Progress](NEXORA_BUSINESS_PROFILE_AND_PRODUCT_FORM_PROGRESS.md). Buyer Demand review: [NEXORA Buyer Demand Progress](NEXORA_BUYER_DEMAND_PROGRESS.md). Buyer phase checklist: [NEXORA Buyer Completion Checklist](NEXORA_BUYER_COMPLETION_CHECKLIST.md).

Review RPC local validation closeout: [NEXORA_REVIEW_RPC_LOCAL_VALIDATION_CLOSEOUT.md](NEXORA_REVIEW_RPC_LOCAL_VALIDATION_CLOSEOUT.md). Repeated local logic testing is closed; two-session concurrency remains unverified and is not a blocker for continuing product implementation. Hosted deployment remains blocked.

Status definitions: **Done (staged)** = committed to Development, not necessarily deployed; **Partial** = foundation exists; **Pending** = not implemented; **Blocked** = prerequisite or release approval missing.

| Workstream | Status | Notes |
|---|---|---|
| Single-domain architecture | Done (staged) | One root app, shared auth/backend, role-based workspaces |
| Admin console moved into Administration route | Done (staged) | Existing Admin console moved from Login section into protected route; E2E pending |
| Role-aware dashboard routing | Partial | Buyer/Seller/Admin/Porter routes staged; browser E2E and hosted migration pending |
| Public registration roles | Decision confirmed | Homepage must show exactly Buyer, Seller and Porter; no administrative roles |
| Porter registration approval | Done (staged) | Signup, pending profile, review table, MFA + logistics.assign RPC, audit log and admin queue staged; migration/E2E pending |
| Admin sign-in + MFA | Partial | Existing Auth MFA AAL2 flow; browser E2E pending |
| Officer account management | Partial | Form/Edge Function/SQL migration staged; DB not migrated or integration-tested |
| Marketplace Wholesale + Retail alignment | Frontend and migration sources updated; Auth/RLS/E2E verification pending | Buyer account category removed; all active Buyers can see and order both Wholesale and Retail approved listings. Seller chooses sale type per product; account-level seller_categories is deprecated. Demand routing uses product taxonomy and approved Business Profile only. Not deployed; migration history remains unreconciled. |
| Services Marketplace | Partial | Listing flow staged; security/E2E remain |
| Buyer Demands & quotations | Partial | Existing form captures product, category/subcategory, specs, quantity, optional budget, currency, destination and required date; submission and public-board/Seller-inbox paths inspected. Underlying view/RLS/matching privacy review still pending; see NEXORA_BUYER_DEMAND_PROGRESS.md |
| Commerce orders | Partial | Order lifecycle staged; payments/disputes/refunds absent |
| Verified reviews | Partial | Verified-purchase workflow staged; E2E pending |
| Delivery Network | Partial | Partner/team, assignment and tracking staged; receipt, finance and API integration pending |
| Marketing Department | Pending | Lead, campaign and onboarding modules not complete |
| Accounts & Finance | Pending | Ledger, reconciliation, refunds/payouts and maker-checker incomplete |
| Reports & audit | Partial | Some audit records exist; unified reporting pending |
| Review RPC local logic validation | Done (local only) | Base and extended local suites passed; local superuser caveat documented; concurrency not yet verified; hosted deployment not approved |
| Separate Admin domain | Not required | Earlier prototype retained temporarily; do not deploy as a second app |
| Production release | Blocked | Migration history mismatch, isolated DB and E2E missing; no approval |

## M0 — Single-domain foundation
- [x] One-domain architecture documented.
- [x] Protected Administration Dashboard route added.
- [x] Existing Admin console moved out of Login section.
- [x] Header Dashboard navigation and Buyer/Seller/Admin post-login routing added.
- [x] Administration route checks active Admin Staff and MFA AAL2.
- [ ] Browser E2E: Buyer, Seller, pending/approved/rejected Porter, Director, MD, Marketing, Transport, Accounts.
- [ ] Test Admin MFA verification redirect, unauthorized deep links, inactive account, refresh and back/forward.
- [ ] Remove/archive separate Admin prototype after code review.

## M1 — Identity / governance
- [x] Local Review RPC base and extended logic-test cycle closed; see closeout document. No more repetitive local tests unless code changes materially.
- [ ] Optional focused two-session concurrency check before any hosted Review RPC release.
- [x] Director, MD and department governance defined.
- [x] Officer invite and permission backend staged.
- [ ] Reconcile all migrations in order.
- [x] Add Porter to profile role model and Auth signup trigger; public metadata cannot create Admin identities.
- [x] Ensure Porter starts pending; only audited Admin/Transport approval activates the account.
- [x] Route only approved active Porter accounts to Porter Dashboard and Transport Provider Center; block pending/rejected/suspended access.
- [ ] Run migration-chain checks and browser E2E for signup, approval, rejection, suspension and re-approval.
- [ ] Test migration on isolated DB.
- [ ] Negative tests for privilege escalation, MFA bypass, department scope, revocation and invite rollback.

## M2 — Marketplace
- [ ] Buyer department completion: see `docs/NEXORA_BUYER_COMPLETION_CHECKLIST.md`; universal product visibility, safe public columns, category-independent Inquiry/Order and Demand routing have been staged. The final inventory Order RPC's legacy Buyer-category gate has now been removed. Limited local visibility fixture/read-only catalog checks ran successfully: 7 PASS; no active Buyer/Seller fixture profiles, so account-level visibility comparisons SKIP. This does not test full Marketplace schema, RPCs, JWT/PostgREST or hosted RLS. Buyer quotation acceptance workflow remains unimplemented. Final privacy/Auth/RLS, wallet/payment, delivery integration and E2E remain pending.
- [x] Review and harden the final staged Auth trigger source: Buyer/Seller legacy market metadata ignored; every OAuth provider except email/phone forced to Buyer; public role allowlist blocks Admin/Director; Porter remains pending; trigger function has empty search_path and no Data API EXECUTE. Frontend role/OAuth/status gates reviewed. [x] Local B-01 regression SQL run PASS on nexora_test; hosted Auth/JWT/RLS and browser E2E remain untested. Do not deploy until migration history is reconciled.
- [x] Remove Buyer-category product visibility restrictions from database/RLS/RPC and order logic; verify that sale type remains per product.
- [x] Final Seller listing edit/review RPCs use per-product `market_category` and mode-specific MOQ/price-tier validation; no account-level `seller_categories` authorization gate remains in the final effective definitions. The read-only verification script checks both RPC definitions.
- [x] Remove account-level Buyer/Seller category assumptions: Buyer sees all approved listings; Seller chooses Wholesale or Retail per product.
- [x] Existing Business Profile/Sales Center foundation inspected: one profile per Seller, one sales-center address, multiple products per business.
- [x] Update Product Listing form and insert/edit paths so Seller selects Wholesale or Retail for each product; MOQ and price-tier semantics remain subject to a separate business decision.
- [x] Product/Service listing, image upload and editing foundation exists; dual-market edit and visibility alignment pending.
- [x] Buyer Demand form, submission, public-board and Seller-inbox client paths inspected. Staged source review confirms SECURITY INVOKER public projection omits Buyer identity, anon column grants omit buyer_id, Buyer ownership/Seller inbox RLS and offer-inbox gate, required date, and category/subcategory matching without sale-type gates. Read-only catalog audit 24 added but not run; full Demand schema absent from local fixture; JWT/PostgREST/E2E and quotation acceptance remain pending.
- [x] Commerce order and verified review workflow staged.
- [ ] Payments, inventory, dispute/refund and notifications.
- [ ] E2E, mobile and accessibility.

## M3 — Transport & Logistics
- [x] Partner/team/provider model, delivery jobs, assignment and tracking staged.
- [ ] Buyer receipt confirmation and completion report.
- [ ] Delivery charge and financial settlement.
- [ ] Courier API/webhooks.
- [ ] Retail/Wholesale E2E and negative authorization tests.

## M4 — Administration departments
- [ ] Director: staff lifecycle, permission catalogue, audit.
- [ ] MD: daily operations, escalation and coordination.
- [ ] Marketing: lead, acquisition, campaign and growth reports.
- [ ] Transport: delivery operations and provider performance.
- [ ] Accounts: ledger, reconciliation and maker-checker.
- [ ] Department-scoped reports and exports.

## M5 — Release
- [ ] Security/RLS/RPC review.
- [ ] Isolated DB migration rehearsal.
- [ ] Browser E2E and mobile tests.
- [ ] Backup/restore and release checklist.
- [ ] Explicit production approval.

## Blockers
1. Hosted Supabase migration history is behind staged migrations; do not apply only the latest migration.
2. No isolated development DB for integration testing; hosted JWT/PostgREST/RLS verification remains unavailable.
3. Previous Vercel deploy hit a rolling 24-hour cap; no deploy retry without approval.
4. Separate Admin prototype is reference only and must not be deployed.


## 2026-11-13 — Universal Buyer Marketplace visibility
- Decision updated: Buyer no longer selects Wholesale/Retail account category; all active Buyers can see both kinds of approved listing.
- Seller still chooses Wholesale or Retail per Product Listing. The chosen type is descriptive/business data, not a visibility entitlement.
- Frontend signup/dashboard/category filters and product detail/query restrictions removed.
- Auth/profile migration sources changed to clear legacy account-level category fields; product read/inquiry/order policies no longer category-gate Buyers; product insert no longer requires Seller account category.
- Buyer Demand routing now matches approved product taxonomy (category/subcategory) and approved Seller business, not account sale-type categories.
- Removed the remaining legacy Buyer-category comparison from the final `private.create_commerce_order` definition in `20261114150000_product_inventory_moq_quantity_pricing.sql`; the per-product sale type still controls Seller-side MOQ/retail rules only.
- Added `supabase/recovery-not-for-deployment/local-setup/20_dual_market_visibility_read_only_verification.sql` and `21_local_marketplace_visibility_fixture.sql`. The fixture creates only a limited local product/business visibility schema on `nexora_test`; it is not the full Marketplace schema and does not represent Demand, Inquiry, Order or listing-edit RPC behavior. The read-only script checks the visibility policy/catalog and safe anon column grants; RPC workflow checks explicitly SKIP in this limited fixture.
- Fixture is guarded against any database other than `nexora_test` and refuses to overwrite existing Marketplace objects. It inserts no sample records. The verification script is read-only and makes no data/schema changes.
- Added `22_run_local_visibility_fixture_termux.sh`, a single Termux runner that downloads cleanup/fixture/verification SQL, checks that only the runner's own connection is open, verifies the local foundation and confirms Marketplace objects are absent before cleanup, then runs cleanup 19, fixture 21 and read-only verification 20 in order. It stops without cleanup if another DB session remains or preflight fails.
- All work is on nexora-development. No migration applied, no hosted DB changed, and no local/browser tests run. The user must run the local fixture and verification script and share the outputs before any PASS can be recorded.


## 2026-11-13 — B-01 Auth trigger hardening
- Updated `20261114210000_porter_public_registration_and_review.sql`: all OAuth identity providers other than email/phone are forced to Buyer, regardless of editable user metadata. Email/phone role metadata is allowlisted to Buyer/Seller/Porter only.
- Trigger always stores `buyer_category = NULL` and `seller_categories = '{}'`; legacy signup metadata is ignored. Buyer/Seller profile is active; Porter profile and review row start pending.
- Revoked `PUBLIC`, `anon`, and `authenticated` EXECUTE on the SECURITY DEFINER Auth trigger function; empty search_path retained.
- Aligned the local-only foundation fixture and smoke tests with universal Buyer visibility/per-product Seller sale type.
- Added local-only patch + regression test: `supabase/recovery-not-for-deployment/local-setup/23_local_buyer_auth_trigger_alignment_tests.sql`. It patches only `nexora_test` fixture and rolls back test users. User has not run it yet; no local test PASS claimed.
- Frontend source review confirms Buyer/Seller/Porter signup choices, Google/Facebook Buyer-only controls, and inactive/suspended account sign-out; pending Porter is shown as pending without dashboard access.
- No migration was applied; no Live Supabase, Production or `main` changed.


## 2026-11-13 — B-03 Buyer Demand source review
- Completed source review of `20261112153000_publish_open_demands_without_buyer_identity.sql`, reconstructed secure-view recovery draft, and final `20261114160000_demand_inbox_quotations_subcategories.sql`.
- Updated `docs/NEXORA_DEMAND_INBOX_QUOTATIONS.md` to remove obsolete Buyer/Seller account-channel matching language; Demand routing is taxonomy + approved business only, irrespective of Wholesale/Retail sale type.
- Added `supabase/recovery-not-for-deployment/local-setup/24_local_buyer_demand_privacy_audit.sql`: read-only, nexora_test-only catalog audit for view privacy, grants, RLS, inbox ownership, quotation insertion, required date and category/subcategory matching. Not run yet; it will SKIP if full Demand schema is absent.
- Source review confirms public Demand view omits Buyer identity/contact, Buyer owner-scoped policies, Seller inbox-only open Demand access, direct inbox writes revoked, quotation insert restricted to own open inbox Demand, and required_date NOT NULL/non-past.
- Buyer quotation acceptance/counter-offer/order conversion remain unimplemented. Real JWT/PostgREST/RLS and browser E2E remain pending.
- No migration applied; no Hosted Supabase, Production or `main` changed.
