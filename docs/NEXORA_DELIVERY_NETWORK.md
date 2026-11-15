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
- No new public role is added for delivery staff. A worker may use an existing active Buyer/Seller/Porter account only after an AAL2 Admin binds the roster record through a unique verified Auth email/phone match. The worker receives only the jobs assigned to that staff record and does not inherit Provider-owner permissions.

## Important limitations
- Courier API credentials are deliberately not stored in this phase. Store secrets only in a server-side secret store when an actual partner integration is approved.
- API tracking mode is metadata only until a provider-specific adapter is implemented.
- The Phase 1 migration depends on the existing staged Transport Provider and Admin permission foundation. The hosted database currently does not contain those staged tables, so do not apply this migration by itself to production.
- Identity-bound NEXORA Team/Courier staff can sign in through the existing account and access only their own receipt-verification queue. Named-staff dispatch requires an active linked account. Full staff status updates, acceptance, photo/signature proof and other field-app workflows remain unimplemented.
- AAL2 Admin can create a Delivery Job linked to a ready Product Commerce Order; Buyer delivery-charge checkout is not implemented yet.

## Remaining phases
1. Provider, own team, and courier partner foundation.
2. Admin assignment and unified delivery jobs supporting staff, independent providers, and courier partners without forcing one vehicle.
3. Retail/wholesale delivery details, buyer-paid delivery charge snapshots, and status tracking.
4. Buyer receipt OTP, own-team/courier staff identity-bound verification, partial delivery and dispute handling.
5. Provider costs, NEXORA fees, payment records and settlement.
6. Courier API adapters and automation.

## Security notes
- Partner/staff tables have RLS enabled and no browser write grants.
- Public RPC wrappers are invoker-rights; privileged internal functions are in the private schema and check auth.uid(), active Admin membership, AAL2 and logistics.assign.
- No service-role key or external API secret is exposed to the browser.


## Phase 2 — Unified Delivery Jobs and Admin Assignment
- Delivery jobs can be created as unassigned requests (`requested`) and assigned later by an Admin / Delivery Coordinator.
- A job can be assigned to exactly one source: an approved independent transport provider, an approved NEXORA-owned team, or an approved courier company. Selecting a Team/Courier field worker requires a unique active account identity linked through verified Auth contact details.
- A vehicle is optional; when supplied for an independent provider it must be approved and belong to that provider. Courier partner jobs do not require a NEXORA vehicle record.
- Assignment history is append-only and records the Admin actor, source, provider/partner/staff/vehicle, reason, and timestamp.
- Job status vocabulary now supports request, assignment, acceptance, pickup, transit, out-for-delivery, delivered, failure, partial delivery, dispute, return, and cancellation.
- Provider self-service status updates, Buyer delivery-charge checkout and external tracking integrations remain later phases. Buyer receipt OTP is implemented as a separate guarded workflow.


## Phase 3 — Tracking and operational statuses
- Added append-only `delivery_tracking_events` and a guarded status transition RPC.
- Independent Provider owners can update only jobs assigned to their own Provider. Admin / Delivery Coordinator can update with AAL2 and `logistics.assign`.
- Status transitions are validated in the database; every transition records previous/new status, time, actor, optional location, note, and external tracking code.
- Independent Provider status updates are self-service. NEXORA Team/Courier workers have an identity-bound receipt queue and OTP verification; other operational status updates remain Admin-entered until the full staff field workflow and partner API are built.
- `delivered` is a logistics status only. It does not mark a Commerce Order completed; Buyer handover verification and completion report are a separate next phase.


## Implementation status (Development Branch, 2026-11-15)
### Staged in code
- Phase 1: partner/team roster tables, Admin UI, partner approval/status, own-team staff roster.
- Phase 2: unassigned Delivery Request creation, Admin assignment to independent Provider / NEXORA team / courier partner, append-only assignment history.
- Phase 3: tracking status history and guarded status transitions. Independent Provider owner may update only their own assigned job; Admin requires AAL2 and logistics.assign.
- Static JavaScript syntax checks passed for delivery-network-admin.js, transport-provider.js, auth.js and marketplace.js.
- HTML duplicate-ID check passed.
- Static SQL structure checks passed for transaction boundaries, dollar-quote balance, function wrappers, RLS enablement and guarded SECURITY DEFINER routines.

### Not yet implemented / tested
- Phase 4: Buyer receipt OTP is staged for Buyers, approved independent Provider owners, AAL2 Admins and identity-bound NEXORA Team/Courier staff. Partial delivery, disputes and final Order completion remain pending.
- Phase 5: Buyer delivery-charge quote/checkout, provider cost, NEXORA fee, payment collection and settlement.
- Phase 6: courier API adapters, webhooks, automated tracking and automatic provider suggestions.
- Provider/staff/courier real-browser E2E tests have not been run. Focused disposable PostgreSQL authorization tests cover Buyer OTP ownership, approved Provider ownership, AAL2 Admin order-linking, verified staff identity binding, Team/Courier dispatch, staff queue isolation and staff-only OTP verification.
- Focused migrations are exercised against disposable PostgreSQL fixtures in CI; a complete Supabase CLI migration-chain replay plus hosted Auth/PostgREST/RLS verification remains a separate release gate.
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


## 2026-11-14 — Independent Provider self-service tracking validated

- In a fresh disposable Supabase CLI v3.1.0 Native Runtime database, all 38 branch migrations applied through `20261115120000`; 41 public tables were checked and zero lacked RLS; `db lint --level warning --fail-on error` reported no schema errors.
- The local-only baseline recreated the existing Live Auth `on_auth_user_created` trigger. No Live auth identities or user rows were copied.
- Synthetic Porter signup → pending review → AAL2 Admin approval → active profile succeeded. The Porter then created a `transport_providers` application; AAL2 Admin approval changed it from pending to approved.
- Admin created a Delivery Job and assigned it to the approved independent Provider. The Provider account itself (AAL1, not Admin) successfully submitted each allowed status transition: `accepted → picked_up → in_transit → out_for_delivery → delivered`.
- The final job status was `delivered`; five append-only tracking events were stored with `actor_type='independent_provider'`. The assigned Provider could read all five events under its RLS policy.
- The separate Admin-managed NEXORA Team path was also validated in an earlier disposable run: approved team partner, staff roster, job assignment and five Admin-authored tracking transitions through delivered.
- Disposable stack and all synthetic records were stopped and destroyed. No Live database mutation, `main`, Production, DNS or paid resource was used.
- Remaining release work: approved-vehicle assignment/availability, courier-partner operational tracking, delivery receipt OTP/digital proof, delivery charge/payment/settlement, disputes/returns, external courier APIs/webhooks, PostgREST/HTTP and browser/device E2E, and concurrency/load testing.


## 2026-11-15 — Buyer-safe Order Tracking projection

- Added staged migration `20261115130000_buyer_safe_delivery_updates.sql`.
- Operational `delivery_jobs.job_status` changes now create append-only, fixed-message customer updates only for jobs linked to a Commerce Order.
- The Buyer read path is a narrow authenticated RPC. It requires an active Buyer and filters every requested Order by `commerce_orders.buyer_id = auth.uid()`.
- Buyers do not receive raw job/tracking tables, exact addresses, private contacts, provider/Admin identity, assignment history, GPS, internal notes or unverified external tracking codes.
- Buyer Dashboard now groups safe updates under each of the latest 50 orders and supports multiple delivery jobs per order. Operator-reported `delivered` does not complete the Commerce Order; Buyer receipt confirmation remains separate.
- Disposable PostgreSQL integration passed for status mapping, append-only history, Buyer A/Buyer B isolation, private-table access denial and anonymous RPC denial. Development CI [#43652641287](https://github.com/shaifrony/nexora-platform1/actions/runs/43652641287) passed 120/120 source tests and 40 active migration filename/order checks.
- Remaining: delivery charges/payment/settlement, disputes/returns, NEXORA-team/courier-worker sign-in and receipt verification, SMS/WhatsApp OTP delivery, and full Supabase/browser/device E2E.


## 2026-11-15 — Buyer receipt OTP security foundation (staged)

- Added staged migrations `20261115140000_buyer_delivery_receipt_otp.sql`, `20261115150000_receipt_otp_work_queues.sql` and `20261115160000_receipt_otp_sha256_provider_guard.sql`. The active Buyer can request a 32-hex-character (128-bit) one-time code only for their own `out_for_delivery` shipment.
- The raw code is returned only to the authenticated Buyer at request time. A 64-character SHA-256 digest is stored, bound to the code, shipment and Buyer; legacy MD5 challenges are invalidated during migration. Codes expire after 10 minutes, requests are rate-limited to one per 60 seconds per shipment, and each challenge allows at most five attempts.
- Only the active owner of the currently assigned, approved independent Provider or an active Admin with `logistics.assign` permission and JWT AAL2 may verify a code. Job/assignment, Provider and challenge locks protect the verification path. A successful verification appends the operational delivered event; Buyer Order completion remains a separate action.
- Buyer order cards can request/display the code; the approved Provider-owner workspace and Admin Delivery Network provide verification forms. The old status RPC and direct delivered transition remain guarded.
- The disposable PostgreSQL fixture now covers legacy MD5 challenge invalidation, exact SHA-256 digest, 128-bit code format, five-attempt lockout, Buyer ownership, Provider approval/account revocation and one-time verification. Current CI status must be checked before treating this increment as validated.
- Scope limitation: SMS/WhatsApp delivery is not configured. NEXORA delivery staff and courier-company workers are roster records without sign-in/field-app identities yet; they must not be given Provider-owner access. A separate scoped identity design is required before enabling their OTP verification.
- No hosted Supabase migration, Production deployment, DNS/public alias or `main` change is intended.


## 2026-11-15 — Admin Commerce Order → Delivery Job linking

- Added staged migration `20261115170000_admin_delivery_order_linking.sql`. The Admin queue exposes only Product Orders in `ready_for_confirmation`; candidate lookup requires an active Admin membership, `logistics.assign`, and JWT AAL2.
- The candidate projection returns only the operational fields needed to prepare a shipment: order reference, product name/quantity/currency, Buyer-provided fulfilment destination, Seller business display name and sales-centre pickup address, existing shipment count, and ready timestamp. It does not expose Buyer phone/contact details.
- The linked-create RPC locks the source Commerce Order and rechecks that it remains a ready Product Order before delegating to the existing Delivery Network creator with the exact `commerce_order_id`. This activates the already-staged Buyer-safe tracking and Buyer-owned Receipt OTP queue for that shipment.
- Admin Delivery Network UI now lets an AAL2 Admin choose a ready Product Order, prefill Seller pickup and Buyer destination details, manually verify missing phone/city data, and create the linked job. Selecting Manual Request clears Order-derived values to prevent stale addresses or references from being reused accidentally.
- Disposable PostgreSQL CI test denies missing `logistics.assign` and AAL2, verifies only ready Product Orders are listed, confirms the new Delivery Job is linked to the selected Order, and rejects pending and Service Orders. Development CI [#43660807743](https://github.com/shaifrony/nexora-platform1/actions/runs/43660807743) passed 122 dependency-free tests, five disposable PostgreSQL suites, JavaScript syntax and 44 migration filename/order checks.
- This is staged Development code only. Full Supabase Auth/PostgREST/RLS and browser/device E2E remain outstanding. No hosted migration or Production deployment was performed.


## 2026-11-15 — Admin Order linking and Buyer receipt queue integration

- Admin Delivery Network now loads eligible Product Order candidates through a narrow AAL2 + `logistics.assign` RPC; Admin can select an Order and prefill Seller pickup and Buyer destination details. Manual Request selection clears stale Order-derived fields.
- The linked-create RPC locks and revalidates the Order before creating the Delivery Job with `commerce_order_id`; this makes the shipment discoverable through the existing Buyer-owned receipt queue and buyer-safe tracking projection.
- The disposable PostgreSQL test now checks Admin permission/MFA enforcement, eligible Order filtering, pending/Service Order rejection, successful Order linkage and that only the owning Buyer can discover the linked Receipt OTP job.
- The browser UI has a source regression test for server-authorized Order loading and the linked-create call. Full browser/device E2E and hosted Supabase validation remain release gates.


## 2026-11-15 — Identity-bound NEXORA Team and Courier staff receipt verification

- Added staged migration `20261115180000_delivery_staff_receipt_identity.sql`. Existing roster records can be linked to an existing active Buyer/Seller/Porter account only by an AAL2 Admin with `logistics.assign`, and only when exactly one verified Auth email or phone matches the roster contact. No new public role is created and no Provider-owner permission is reused.
- Each Auth account can be linked to only one staff record. Changing the staff contact email/phone clears the link; Admin can explicitly unbind with a reason. Suspended staff, suspended partners and inactive user profiles cannot access the staff queue or verify receipts.
- Approved Courier Companies can now have managed worker records, as NEXORA teams already could. Admin assignment accepts an optional worker from either partner kind only when that worker is identity-bound and active.
- Added a separate staff receipt queue to the shared Transport & Delivery Work Center. The server returns only jobs assigned to the authenticated staff identity; the database independently rechecks the exact staff/job/partner relationship before OTP verification.
- The staff receipt verification is recorded as `actor_type='delivery_staff'`; it does not elevate the account role or permit access to another worker's jobs.
- Disposable PostgreSQL CI covers verified email/phone matching, rejection of unverified contacts, NEXORA Team and Courier assignment, unbound worker rejection, own-job queue isolation, denial of cross-worker OTP verification, and successful Team/Courier receipt verification.
- Development CI [#43662559823](https://github.com/shaifrony/nexora-platform1/actions/runs/43662559823) passed 129/129 source tests, all six focused PostgreSQL suites, JavaScript syntax and 45 active migration filename/order checks.
- Still pending: complete staff status-update/proof-of-delivery field workflow, SMS/WhatsApp OTP delivery, partial delivery/disputes, final Commerce Order completion, delivery finance/settlement, full Supabase Auth/PostgREST/RLS chain replay and browser/device E2E.


## 2026-11-15 — One Delivery Job per Commerce Order

- A Commerce Product Order may now have at most one linked Delivery Job. A partial delivery is represented by additional proof records on that same job, not by creating a second job for the same order.
- A partial unique index enforces the relationship; a trigger returns a clear duplicate-link error. The migration fails closed if pre-existing duplicate order links are detected, so data must be reviewed rather than silently deleted.
- The focused Admin Order-to-Delivery PostgreSQL fixture verifies successful linking, duplicate-link rejection, no duplicate row, Buyer receipt-queue isolation, AAL2 and pending/service order denial.
- This guard is staged on `nexora-development` only.
