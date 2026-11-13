# NEXORA Project Structure & Delivery Plan

Last updated: 2026-11-13
Branch: `nexora-development`

## Approved architecture: one domain

NEXORA uses one website, one homepage, one login system and one shared backend. The planned production domain is `nexora.com`. Marketplace and Administration are separate protected workspaces/routes inside this single application. A separate `admin.nexora.com` is not required.

### Login and dashboard routing

- Buyer → Buyer Dashboard.
- Seller → Seller Dashboard.
- Director / MD / Marketing / Transport / Accounts officer → Administration Dashboard, only when account is active, the user has an active Admin Staff record and MFA AAL2 is verified.
- Inactive, unknown or unauthorized accounts do not receive privileged dashboard access.
- Navigation visibility is not authorization. Supabase RLS and server-side RPC/Edge Function checks remain mandatory for every protected data operation.

### Marketplace workspace

- Wholesale and Retail product discovery.
- Services Marketplace.
- Buyer Demand and Seller Quotations.
- Product/Service details, commerce orders, chat and verified reviews.
- Buyer and Seller dashboards.

### Administration workspace

- Director: governance, officer accounts, permissions, audit and oversight.
- MD: daily operations and cross-department coordination, without structural authority.
- Marketing: leads, onboarding, campaigns and growth.
- Transport & Logistics: partners, delivery assignments, tracking and exceptions.
- Accounts & Finance: ledger, reconciliation, fees, refunds and settlements.
- Permission-filtered reports and audit.

## Repository layout

- Root `index.html`, `auth.js`, `marketplace.js`: active single-domain app.
- `admin/`: earlier separate-app prototype retained temporarily as reference only. It is not part of the active user journey. Do not create a separate Vercel project or domain for it.
- Supabase Auth, Database and Storage are shared.

## Workstreams

### M0 — One-app foundation
- [x] Record single-domain architecture.
- [x] Move the existing Admin console UI into a protected Administration Dashboard section.
- [x] Add role-aware Dashboard navigation and post-login routing for Buyer/Seller/Admin.
- [x] Require active Admin Staff + MFA for the Administration route.
- [ ] Browser E2E: Buyer, Seller, Director, MD and each department; include MFA and unauthorized deep links.
- [ ] Verify Admin MFA enrollment/verification redirects into Administration Dashboard.
- [ ] Remove/archive the unused separate Admin prototype after code review.
- [ ] Configure the single production domain only after release approval.

### M1 — Identity and governance
- [x] Define Director, MD and department positions in governance plan.
- [x] Stage central officer invite endpoint and SQL permission model.
- [ ] Reconcile complete ordered Supabase migration history.
- [ ] Test on isolated database.
- [ ] Test invite rollback, duplicate identities, privilege escalation, department scope, MFA bypass and revocation.

### M2 — Marketplace
- [x] Wholesale/Retail product category model.
- [x] Product/Service listing, image and edit workflow.
- [x] Buyer Demand matching and Seller quotation.
- [x] Commerce order and verified review workflow staged.
- [ ] Payment, refunds, disputes, inventory reservation and notifications.
- [ ] Marketplace browser E2E, mobile accessibility and performance.

### M3 — Transport & Logistics
- [x] NEXORA Team, Courier Partner and Independent Provider model.
- [x] Unified delivery jobs, assignment and tracking staged.
- [ ] Buyer receipt OTP/digital confirmation and completion report.
- [ ] Buyer-paid delivery charge, fee and settlement.
- [ ] Courier API/webhooks and automated tracking.
- [ ] Retail/Wholesale E2E and negative authorization tests.

### M4 — Administration operations
- [ ] Director officer lifecycle, permissions and audit screens.
- [ ] MD daily operations, coordination and escalation.
- [ ] Marketing lead, onboarding and campaign workflows.
- [ ] Transport partner, assignment and delivery operations.
- [ ] Accounts ledger, reconciliation and maker-checker.
- [ ] Permission-filtered reports and exports.

### M5 — Quality and release
- [ ] Security review, RLS/RPC negative tests and MFA tests.
- [ ] Isolated database migration rehearsal.
- [ ] Browser E2E, mobile and accessibility tests.
- [ ] Backup/restore and release checklist.
- [ ] Explicit approval before production migration or deployment.

## Release constraints

- Work only on `nexora-development`; `main` remains untouched.
- No Live DB migration, production deployment, DNS change or paid activation without explicit approval.
- Hosted Supabase migration history is behind staged migrations. Reconcile the complete ordered chain before any migration.
- No isolated Supabase development DB is currently available for SQL integration testing.
- Previous Vercel deployment reached a rolling 24-hour cap; do not retry without approval.
