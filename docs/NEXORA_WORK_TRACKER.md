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
| Marketplace Wholesale + Retail alignment | Frontend staged; migration chain contains dual-market logic; final Auth/RLS/E2E verification pending | Buyer chooses Wholesale or Retail; Seller chooses mode per product. Existing migrations define Buyer category checks, product market_category and matching Buyer RLS/order checks. Seller signup currently sends only wholesale seller_categories, which conflicts with the per-product Seller decision and is deferred to Seller phase. Recovery draft also adds a Buyer-category check to the SECURITY DEFINER Product Inquiry RPC; still recovery-only and untested. It remains non-deployable until schema and migration history are reconciled. |
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
- [ ] Buyer department completion: see `docs/NEXORA_BUYER_COMPLETION_CHECKLIST.md`; corrected category-switch trigger/grant mismatch and Inquiry category guard in migration source. Final privacy/Auth/RLS, wallet/payment, delivery integration and E2E remain pending.
- [ ] Verify the final Auth trigger/profile constraints across the complete migration chain for Buyer wholesale/retail signup, Buyer-only OAuth and Porter compatibility. Provider lookup corrected to raw_app_meta_data; Buyer category-update trigger/grant conflict corrected in migration source. Auth trigger attachment and real signup remain untested. Earlier wholesale-only fixture is not authoritative. Do not deploy until migration history is reconciled.
- [ ] Enforce Buyer-category product visibility in database/RLS/RPC and order logic; client-side filtering is not a security boundary.
- [ ] Reconcile Seller edit-request workflow with the dual-market model and mode-specific product fields.
- [x] Remove wholesale-only Product Listing UI/insert assumptions: Seller chooses Wholesale or Retail per product; Buyer signup sends selected category and Dashboard category switching accepts both (database trigger still needs alignment).
- [x] Existing Business Profile/Sales Center foundation inspected: one profile per Seller, one sales-center address, multiple products per business.
- [x] Update Product Listing form and insert/edit paths so Seller selects Wholesale or Retail for each product; MOQ and price-tier semantics remain subject to a separate business decision.
- [x] Product/Service listing, image upload and editing foundation exists; dual-market edit and visibility alignment pending.
- [x] Buyer Demand form, submission, public-board and Seller-inbox client paths inspected; required date is included and public view is designed to omit Buyer identity (database privacy and matching security review pending).
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
