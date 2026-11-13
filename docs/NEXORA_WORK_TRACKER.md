# NEXORA Work Tracker

Updated: 2026-11-13

Status definitions:
- **Done (staged):** committed to development; not necessarily deployed.
- **Partial:** foundation exists; important behavior/testing remains.
- **Pending:** not implemented.
- **Blocked:** prerequisite/environment/approval missing.

| Workstream | Status | Notes |
|---|---|---|
| Two-app architecture | Done (staged) | Marketplace at repository root; Administration under `admin/` |
| Admin app shell | Done (staged) | Separate HTML/CSS/JS entry point |
| Admin sign-in + MFA | Partial | Password sign-in, TOTP challenge, aal2 gate; browser test pending |
| Active Admin identity | Partial | Checks active `admin_staff`; extended fields fallback for pre-migration schema |
| Permission visibility | Partial | Reads allowed grants; operational enforcement still must be tested per RPC |
| Director central account management | Partial | UI/Edge Function/SQL migration staged; DB migration not applied or integration-tested |
| Marketplace Wholesale/Retail | Done (staged) | Category entitlements and Product market category staged |
| Services Marketplace | Partial | Listings staged; security and E2E tests remain |
| Buyer Demands & quotations | Partial | Matching and quotations staged; acceptance/conversion/notifications pending |
| Commerce orders | Partial | Order lifecycle staged; payments, disputes and refunds absent |
| Verified reviews | Partial | Eligibility and submission staged; E2E pending |
| Delivery Network | Partial | Partner/team, assignment, tracking staged; receipt, finance, API integration pending |
| Marketing operations | Pending | Dedicated lead/campaign workflows not yet built |
| Accounts & Finance | Pending | Ledger, reconciliation, refunds/payouts and maker-checker not complete |
| Reports & audit | Partial | Some audit events exist; unified departmental reporting pending |
| Separate Vercel projects/domains | Pending | Requires second Vercel project, Root Directory configuration and domain/DNS approval |
| Production release | Blocked | Migration history mismatch, isolated DB and E2E missing; no release approval |

## Workstreams and remaining tasks

### M0 — Foundation / app separation
- [x] Record two-app architecture.
- [x] Create independent Admin app entry point.
- [x] Add password sign-in, TOTP MFA gate and active Admin lookup.
- [ ] Move Admin-only UI and scripts out of Marketplace root.
- [ ] Configure independent Vercel projects and preview URLs.
- [ ] Browser E2E, mobile layout and cross-app session tests.

### M1 — Identity and governance
- [x] Define Director, MD, department head and officer positions in governance plan.
- [x] Stage officer invite endpoint and SQL permission model.
- [ ] Reconcile full ordered Supabase migration chain.
- [ ] Apply/test on isolated database.
- [ ] Test invitation rollback, duplicate identities, privilege escalation, MFA bypass, department scope and revocation.
- [ ] Complete permission-change audit and session refresh.

### M2 — Marketplace
- [x] Wholesale/Retail product category model.
- [x] Product/Service listing, images and edit workflow.
- [x] Buyer Demand matching and Seller quotation.
- [x] Commerce order and verified review workflow staged.
- [ ] Payments, inventory reservation, disputes, notifications and refunds.
- [ ] Marketplace browser E2E and accessibility/performance checks.

### M3 — Transport & Logistics
- [x] NEXORA Team, Courier Partner and Independent Provider model.
- [x] Unified delivery jobs and Admin assignment.
- [x] Tracking and status transitions.
- [ ] Buyer receipt confirmation / completion report.
- [ ] Buyer-paid delivery charge and settlement.
- [ ] Courier API/webhooks.
- [ ] Retail/Wholesale E2E and negative authorization tests.

### M4 — Department administration
- [ ] Director: structure, appointments, permissions, audit and oversight.
- [ ] MD: daily operations and cross-department coordination; no structural authority.
- [ ] Marketing: leads, onboarding, campaigns and growth reporting.
- [ ] Transport: delivery queue, partners, assignments, tracking and exceptions.
- [ ] Accounts: ledger, reconciliation, refund/payout/settlement maker-checker.
- [ ] Reports, exports and departmental dashboards.

### M5 — Quality and release
- [ ] Security/RLS/RPC negative tests.
- [ ] Isolated database migration rehearsal.
- [ ] Browser E2E and mobile tests.
- [ ] Backup/restore and release checklist.
- [ ] Explicit approval before production migration, DNS or deployment.

## Release blockers
1. Hosted Supabase migration history is behind the staged migration chain. Never apply only the latest migration.
2. No isolated Supabase development database is currently available for integration tests.
3. Prior Vercel deployment hit a rolling 24-hour cap; do not retry without approval.
4. Existing root Marketplace files still contain legacy Admin sections. Move them gradually; do not remove until parity and E2E are verified.
5. Officer provisioning must be security-reviewed and tested before live staff invitations.