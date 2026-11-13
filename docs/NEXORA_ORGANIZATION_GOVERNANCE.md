# NEXORA Organizational Governance & Department Charter

**Status:** Approved design baseline for Development Branch planning  
**Version:** 1.0  
**Date:** 2026-11-13

This document defines NEXORA's internal governance structure. It applies to employees, officers, department heads, executives and administrators. It does not change Buyer, Seller, Transport Provider, Courier Partner or other marketplace account types.

## 1. Governance principles

1. NEXORA has one Director as the highest internal authority.
2. The Director owns the constitutional structure: core platform model, departments, executive offices, protected policies, role hierarchy and permission boundaries.
3. The Managing Director (MD) runs day-to-day operations but cannot change the constitutional structure or grant themselves protected powers.
4. Departments operate only within their assigned remit and explicit permissions.
5. A job title does not automatically grant database access. Every capability must be explicitly permissioned.
6. Privileged actions must be enforced server-side, protected by MFA where sensitive, and written to an immutable/append-only audit trail where supported.
7. Staff accounts are separate from marketplace Buyer/Seller accounts. No department officer may change a marketplace user's role, account status or verification state unless explicitly granted a narrowly scoped permission.
8. No employee may approve their own expense, refund, settlement or sensitive request. A maker-checker approval flow is required for financial actions.
9. The Director's authority is still subject to law, platform security, auditability and safe account recovery. The platform must not create an unchangeable single point of failure.

## 2. Organizational hierarchy

- **Director (NEXORA Director / Constitutional Super Admin)** — one active office-holder; highest internal authority.
  - **Managing Director (MD)** — executive operations lead.
    - **Marketing Department**
    - **Transport & Logistics Department**
    - **Accounts & Finance Department**
    - Additional departments may be created only through the Director's protected structure-change process.

The Director may appoint or remove the MD and department heads, subject to documented handover and audit. A Director succession/recovery procedure must exist; no single person should be able to permanently lock the organization out.

## 3. Office responsibilities and powers

### 3.1 Director

**Purpose:** Define, protect and amend NEXORA's constitutional and technical structure.

May:
- Create, rename, merge or retire departments and executive offices.
- Define reporting lines, job titles, role templates and department mandates.
- Define the permission catalogue and protected permission boundaries.
- Appoint, change or remove the MD and department heads.
- Approve changes to core platform rules, governance policy, security model and organization-wide workflows.
- Review all departments, audit trails, risk reports and performance reports.
- Approve exceptional overrides only where a documented policy permits them.

Must not:
- Bypass legal requirements, security controls or audit logs.
- erase audit history or silently alter historical financial records.
- use ordinary operational access to impersonate users or read private Buyer/Seller communications.

**Protected actions:** structural changes, permission-catalogue changes, top-level executive appointment, security-policy changes, and succession/recovery.

### 3.2 Managing Director (MD)

**Purpose:** Coordinate and control day-to-day NEXORA operations within the Director-approved structure.

May:
- Set operational targets, schedules and priorities for departments.
- Coordinate department heads and resolve cross-department operational blockers.
- Review operational dashboards and department reports.
- Assign work and monitor performance within approved staffing and permission limits.
- Escalate policy, security, financial and structural decisions to the Director.
- Recommend new roles, departments, staffing or policy changes to the Director.

Must not:
- Create, remove, rename or restructure departments.
- alter the protected permission catalogue or grant themselves permissions.
- appoint/remove the Director or override the Director's constitutional authority.
- directly approve their own financial claims or settlements.

### 3.3 Marketing Department

**Purpose:** Grow NEXORA's marketplace, network and brand.

May:
- Attract and onboard Buyers and Sellers.
- Identify and recruit businesses, suppliers and service providers.
- Recruit prospective independent Transport Providers, Delivery Partners and courier companies, then refer them to Transport for operational review.
- Run approved campaigns, content, partnerships and brand activities.
- Research markets, categories, regions and customer needs.
- Track acquisition, activation, retention, conversion and campaign performance.
- Collect user feedback and route complaints to the responsible department.

Must not:
- approve its own business, provider, vehicle or courier applications unless separately granted an independent review permission.
- change delivery assignments, financial balances, fees or settlements.
- access private identity/contact data beyond the minimum needed for an authorized onboarding task.

### 3.4 Transport & Logistics Department

**Purpose:** Operate all NEXORA-coordinated delivery and transport activity for Retail and Wholesale orders.

May:
- Review delivery requests and shipment details.
- Verify operational readiness of independent providers, courier partners, NEXORA teams and vehicles.
- Assign and reassign jobs to eligible approved delivery sources.
- Coordinate pickup, transit, tracking, delivery, partial delivery, failure, return and dispute workflows.
- Collect delivery completion reports and evidence.
- Monitor service levels, delivery times, failure rates and partner performance.
- Submit delivery charges, partner costs and settlement evidence to Accounts.

Must not:
- change product/order prices or financial ledger entries.
- approve or pay its own partner invoices.
- mark a commerce order financially settled merely because a parcel is marked delivered.
- bypass Buyer receipt confirmation or the approved dispute/exception workflow.

### 3.5 Accounts & Finance Department

**Purpose:** Maintain accurate financial records and control NEXORA's money flows.

May:
- Record and reconcile revenue, expenses, fees, commissions and taxes.
- Prepare invoices, statements, budgets and financial reports.
- Calculate approved delivery charges, partner costs, platform fees and amounts payable.
- Reconcile payment-provider reports and settlement records.
- Prepare refund, payout and settlement requests for approval.
- Monitor receivables, payables, cash flow and financial exceptions.

Must not:
- invent or alter commercial pricing policy without authorization.
- approve their own payment, refund, expense or settlement request.
- change delivery job status or order fulfilment evidence.
- delete or rewrite posted financial ledger entries; corrections must be compensating entries with audit history.

## 4. Departmental staffing

Each department may have:
- Department Head / Director of Department.
- Deputy / Assistant Department Head, if approved.
- Officers and operational staff.
- Read-only auditors or analysts, if approved.

The MD coordinates department heads. Department heads manage their own staff only within approved staffing limits. Only the Director may change the organizational chart and protected role templates. The MD may recommend staffing changes; appointment actions follow the Director-approved delegation policy.

## 5. Permission model

Permissions are capability-based, not title-based. Initial permission namespaces:

| Area | Example capabilities |
|---|---|
| Organization | `organization.view`, `organization.structure.manage`, `organization.executives.manage` |
| Executive operations | `operations.view`, `operations.coordinate`, `operations.staff.assign` |
| Marketing | `marketing.users.acquire`, `marketing.campaigns.manage`, `marketing.analytics.view` |
| User administration | `users.view_limited`, `users.onboarding.assist` |
| Transport | `logistics.view`, `logistics.providers.review`, `logistics.assign`, `logistics.tracking.update`, `logistics.completion.review` |
| Finance | `finance.view`, `finance.ledger.read`, `finance.reconciliation.manage`, `finance.refund.request`, `finance.payout.request`, `finance.payout.approve` |
| Audit | `audit.view`, `audit.export` |

These are proposed capability keys, not a claim that every key is already implemented. Existing permission keys must be mapped and reviewed before any migration. Protected structure/permission changes must be denied to MD and all department staff at the database/RPC layer, not merely hidden in the UI.

### Separation of duties

- Marketing may source a provider; Transport independently reviews/approves operational eligibility.
- Transport may submit a delivery cost; Accounts independently validates the amount.
- Accounts may prepare a refund/payout; an authorized independent approver must approve it.
- MD may coordinate departments but cannot alter the protected structure.
- Only Director-level protected authority can change the structure, and every such change is audited.

## 6. Internal staff account lifecycle

1. A prospective staff member must already have a verified NEXORA identity account or be invited through a controlled invitation process.
2. Director appoints MD and department heads. MD may nominate staff; final appointment follows Director-approved delegation.
3. The system assigns a staff code, office, department, reporting manager and explicit permission set.
4. Sensitive access requires MFA; privileged operations require server-side permission checks.
5. Suspension or termination immediately disables staff privileges and revokes active sessions where supported.
6. Transfer between departments removes old permissions before granting new permissions.
7. All appointments, transfers, permission changes and deactivations are audited.

Marketplace registration must never automatically create an employee/admin role.

## 7. Dashboards

- **Director Dashboard:** organization chart, executive appointments, structure/permission governance, all-department summaries, audit and risk.
- **MD Dashboard:** cross-department operational overview, targets, staffing coordination, escalations and reports; no structure editor.
- **Marketing Dashboard:** acquisition pipeline, campaigns, onboarding referrals and growth metrics.
- **Transport Dashboard:** delivery queue, provider/partner approvals, assignment, tracking, proof of delivery and exception queue.
- **Accounts Dashboard:** ledger, reconciliation, invoices, delivery-charge calculations, refunds/payout requests and settlement approvals.

Each dashboard must hide unauthorized data and actions. UI visibility is convenience only; database/RPC authorization remains authoritative.

## 8. Implementation sequence

1. Preserve and inspect the existing Admin MFA, staff, department and permission foundation.
2. Map current `super_admin` to Director and current assistant-admin permissions to the new capability model without breaking existing access.
3. Introduce explicit MD and department-head office assignments with protected database rules.
4. Seed the three initial departments: Marketing, Transport & Logistics, Accounts & Finance.
5. Build role-specific dashboards and department work queues.
6. Implement maker-checker financial approvals and organization-change audit records.
7. Run isolated-database migration tests, negative authorization tests and browser E2E tests.
8. Only after all tests and explicit authorization, consider any hosted migration or production release.

## 9. Current implementation status

This charter is a governance design document. It does **not** mean the MD role, department dashboards, new permission keys, staff invitation lifecycle or financial maker-checker controls are already implemented. The existing Development Branch contains an earlier Super Admin / Assistant Admin and permission-grant foundation. That foundation must be inspected and safely mapped before schema changes.

No hosted migration, production deployment or change to the `main` branch is authorized by this document.
