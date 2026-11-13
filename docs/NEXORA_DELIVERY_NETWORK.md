# NEXORA Delivery Network — Phase 1 Foundation

## Policy baseline
- NEXORA controls and coordinates every marketplace product delivery.
- Delivery sources: NEXORA-owned teams, approved courier/logistics partners, and approved independent providers.
- Admin / Delivery Coordinator makes assignments in the initial operating model.
- Buyer pays the approved delivery charge.
- Initial coverage: domestic retail and wholesale.
- Courier integration starts with manual booking/tracking; API integration is an adapter added later.
- Seller's own independent delivery arrangement is not a separate untracked option in this policy.

## Phase 1 scope
- `delivery_network_partners`: NEXORA-owned team records and courier/logistics company records.
- `delivery_network_staff`: Admin-managed roster for NEXORA-employed or contracted delivery workers.
- Existing `transport_providers` remains the registration model for independent people and transport businesses.
- Partner and staff reads require `logistics.view`; changes require active Admin membership, AAL2, and `logistics.assign`.
- Every privileged change is recorded in `admin_audit_logs`.
- No public role is added for delivery staff in this phase. This avoids changing Buyer/Seller/Admin role semantics. Staff login/field app is a later phase and must use a separate scoped identity design.

## Important limitations
- Courier API credentials are deliberately not stored in this phase. Store secrets only in a server-side secret store when an actual partner integration is approved.
- API tracking mode is metadata only until a provider-specific adapter is implemented.
- The Phase 1 migration depends on the existing staged Transport Provider and Admin permission foundation. The hosted database currently does not contain those staged tables, so do not apply this migration by itself to production.
- Delivery staff records are a managed roster only; they cannot yet sign in, accept assignments, or submit proof of delivery.
- Delivery jobs are not yet linked automatically to commerce orders and no buyer delivery charge checkout exists yet.

## Remaining phases
1. Provider, own team, and courier partner foundation.
2. Admin assignment and unified delivery jobs supporting staff, independent providers, and courier partners without forcing one vehicle.
3. Retail/wholesale delivery details, buyer-paid delivery charge snapshots, and status tracking.
4. Completion report, receiver OTP / alternative verification, partial delivery and dispute handling.
5. Provider costs, NEXORA fees, payment records and settlement.
6. Courier API adapters and automation.

## Security notes
- Partner/staff tables have RLS enabled and no browser write grants.
- Public RPC wrappers are invoker-rights; privileged internal functions are in the private schema and check auth.uid(), active Admin membership, AAL2 and logistics.assign.
- No service-role key or external API secret is exposed to the browser.


## Phase 2 — Unified Delivery Jobs and Admin Assignment
- Delivery jobs can be created as unassigned requests (`requested`) and assigned later by an Admin / Delivery Coordinator.
- A job can be assigned to exactly one source: an approved independent transport provider, an approved NEXORA-owned team (optionally with an active staff member), or an approved courier company.
- A vehicle is optional; when supplied for an independent provider it must be approved and belong to that provider. Courier partner jobs do not require a NEXORA vehicle record.
- Assignment history is append-only and records the Admin actor, source, provider/partner/staff/vehicle, reason, and timestamp.
- Job status vocabulary now supports request, assignment, acceptance, pickup, transit, out-for-delivery, delivered, failure, partial delivery, dispute, return, and cancellation.
- This phase does not yet implement provider self-service acceptance/status updates, buyer charge checkout, tracking integrations, or completion OTP. Those remain later phases.


## Phase 3 — Tracking and operational statuses
- Added append-only `delivery_tracking_events` and a guarded status transition RPC.
- Independent Provider owners can update only jobs assigned to their own Provider. Admin / Delivery Coordinator can update with AAL2 and `logistics.assign`.
- Status transitions are validated in the database; every transition records previous/new status, time, actor, optional location, note, and external tracking code.
- Courier Partner and NEXORA staff updates remain Admin-entered until partner API and staff field access are built.
- `delivered` is a logistics status only. It does not mark a Commerce Order completed; Buyer handover verification and completion report are a separate next phase.


## Implementation status (Development Branch, 2026-11-13)
### Staged in code
- Phase 1: partner/team roster tables, Admin UI, partner approval/status, own-team staff roster.
- Phase 2: unassigned Delivery Request creation, Admin assignment to independent Provider / NEXORA team / courier partner, append-only assignment history.
- Phase 3: tracking status history and guarded status transitions. Independent Provider owner may update only their own assigned job; Admin requires AAL2 and logistics.assign.
- Static JavaScript syntax checks passed for delivery-network-admin.js, transport-provider.js, auth.js and marketplace.js.
- HTML duplicate-ID check passed.
- Static SQL structure checks passed for transaction boundaries, dollar-quote balance, function wrappers, RLS enablement and guarded SECURITY DEFINER routines.

### Not yet implemented / tested
- Phase 4: Buyer receipt OTP / digital confirmation, Delivery Person completion report, order completion and verified-review integration.
- Phase 5: Buyer delivery-charge quote/checkout, provider cost, NEXORA fee, payment collection and settlement.
- Phase 6: courier API adapters, webhooks, automated tracking and automatic provider suggestions.
- Provider/staff/courier real-browser E2E tests and negative authorization tests have not been run.
- No local/disposable Supabase database is connected for migration execution tests.
- The hosted Supabase database currently does not contain the staged Transport/Delivery Network tables; its migration history is behind the Development Branch files. Do not apply only the latest migrations to the hosted database. First reconcile and test the complete ordered migration chain on a safe development database.
- No hosted migration has been applied, no production deployment has been made, and the main branch remains unchanged.

## Required release gate
Before any real buyer delivery is enabled:
1. Reconcile all staged migrations with the hosted database's migration history.
2. Apply the complete migration chain to an isolated development database and run SQL/RLS negative tests.
3. Complete receipt confirmation and report flow.
4. Complete delivery charge/payment and settlement model.
5. Run end-to-end tests for Retail, Wholesale partial shipments, Courier Partner manual tracking, NEXORA team, Independent Provider, disputes, failed delivery and returns.
6. Obtain explicit approval before any hosted migration or production deployment.


## 2026-11-14 — Disposable Porter and NEXORA Team workflow test

- Replayed all 38 active migrations in a fresh local Supabase CLI v3.1.0 Native Runtime database. Final local history: 38 applied through `20261115120000`; 41 public tables checked, zero without RLS; `db lint --level warning --fail-on error` reported no schema errors.
- The local-only baseline recreated the existing Live `auth.users` `on_auth_user_created` trigger because it is a Live catalog object not created by the branch migration files. No Live auth identities or user rows were copied.
- Synthetic Porter signup through that trigger created a `porter` profile in `pending` state and a pending `porter_account_reviews` record. A synthetic Super Admin with AAL2 approved it; the profile became active and review became approved. A second Porter remained pending after an AAL1 Admin approval attempt. A public signup attempt requesting role `admin` did not create an auth user.
- The approved Porter created an independent `transport_providers` application; an AAL2 Admin approved the application.
- Synthetic Super Admin created an approved `nexora_team` delivery partner, created a staff record, created a delivery job, and assigned the job to that partner/staff member.
- Admin tracking transitions succeeded in order: `accepted → picked_up → in_transit → out_for_delivery → delivered`. The job ended `delivered` and exactly five tracking events were recorded.
- This validates database registration/review and the Admin-managed NEXORA Team assignment/tracking path with synthetic data. It does not yet validate independent-provider self-service tracking, external courier APIs/webhooks, receipt OTP/digital proof, delivery payments/settlement, disputes/returns, or browser/device E2E.
- The disposable local stack and all synthetic records were stopped and destroyed. No Live schema/history/data, `main`, Production, DNS or paid resource was changed.
