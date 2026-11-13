# NEXORA Project Structure & Delivery Plan

Last updated: 2026-11-13
Branch: `nexora-development`

## Product split

NEXORA will be delivered as two independent web applications backed by one shared Supabase project initially.

| App | Intended hostname | Vercel project root | Primary users |
|---|---|---|---|
| Marketplace | `nexora.com` / `www.nexora.com` | repository root (existing app) | Buyers, Sellers, public visitors |
| Administration | `admin.nexora.com` | `admin/` | Director, MD, Marketing, Transport, Accounts |

The correct admin subdomain is `admin.nexora.com`; not `NEXORA/AMDIN.COM`.
Do not purchase a domain, change DNS, attach domains, or deploy until explicitly authorized.

## Architecture boundaries

- Marketplace owns public discovery, Buyer/Seller dashboards, listing management, Buyer Demands, quotations, commerce orders, chat and reviews.
- Administration owns internal staff sign-in, MFA, roles, permissions, department dashboards, delivery operations, financial operations, reports, audit and governance.
- Supabase Auth and the existing database are shared initially. Each app must independently enforce server-side authorization; hiding UI is never an access-control boundary.
- Keep staff/admin pages out of the public marketplace navigation. The legacy root app still contains old Admin sections and must be migrated module-by-module before they are removed.
- Admin hostname will be connected later to a separate Vercel project configured with Root Directory `admin`. Marketplace remains a separate Vercel project rooted at repository root. Both projects may point to the same Git repository and development branch during preview testing.

## Delivery workstreams

### M0 — Foundation and separation
- [x] Record the two-app architecture.
- [x] Create a separate Admin application shell.
- [x] Add a staff-only login gate with MFA challenge and active-admin check.
- [ ] Move all admin-only UI and scripts out of the Marketplace root.
- [ ] Configure two separate Vercel projects and preview domains (requires explicit release approval).
- [ ] Browser E2E and cross-app session/redirect tests.

### M1 — Identity and governance
- [x] Define Director, MD, department head and department officer position model in governance plan.
- [x] Stage central officer provisioning endpoint and SQL migration on development branch.
- [ ] Reconcile the full Supabase migration history before any database application.
- [ ] Test invite rollback/cleanup and duplicate email/account cases in isolated DB.
- [ ] Enforce server-side department-scoped permission checks for every operational RPC.
- [ ] Complete permission change history, revocation/session refresh and staff lifecycle tests.

### M2 — Marketplace
- [x] Wholesale/Retail category model.
- [x] Product and Service listings, listing images/edit workflow.
- [x] Buyer Demand matching and seller quotations.
- [x] Commerce order and verified-purchase review workflow staged.
- [ ] Payment, refunds, disputes, inventory reservation and notifications.
- [ ] Marketplace browser E2E, mobile accessibility and performance checks.

### M3 — Transport & Logistics
- [x] Provider, Courier Partner and NEXORA Team model staged.
- [x] Unified delivery job and Admin assignment workflow staged.
- [x] Tracking and delivery status transitions staged.
- [ ] Buyer receipt OTP/confirmation and completion report.
- [ ] Buyer-paid delivery charges, provider cost and NEXORA fee settlement.
- [ ] Courier API/webhook adapters and automated tracking.
- [ ] Retail/Wholesale delivery E2E and negative authorization tests.

### M4 — Administration departments
- [ ] Director: organization chart, officer accounts, permissions, audit and oversight.
- [ ] MD: daily operations overview, cross-department coordination, escalation and reports; no constitutional/structure permissions.
- [ ] Marketing: leads, onboarding, campaigns, conversion and growth reports.
- [ ] Transport: delivery queue, partner/staff readiness, assignment, tracking, exceptions and performance.
- [ ] Accounts: ledger, reconciliation, charges, refunds and settlement with maker-checker approvals.
- [ ] Department-scoped dashboards and exports.

### M5 — Reports, quality and release
- [ ] Shared reporting definitions and filters.
- [ ] Audit-ready export and scheduled reports.
- [ ] Security review, RLS/RPC negative tests and MFA checks.
- [ ] Isolated DB migration rehearsal.
- [ ] Browser E2E, backup/restore and release checklist.
- [ ] Explicit approval before production migration, DNS or deployment.

## Current release constraints

- Development-only work on `nexora-development`.
- `main` remains unchanged by this plan.
- No Live Database migration, production deployment, DNS change or paid service activation.
- Supabase hosted migration history is behind the staged migration chain; new staged migrations must not be applied until the complete ordered chain is reconciled and tested on an isolated database.
- No isolated development database currently available for SQL integration tests.
