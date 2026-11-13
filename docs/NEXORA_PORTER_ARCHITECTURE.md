> **SUPERSEDED DESIGN NOTICE — 2026-11-13:** The earlier statements below that Porter is not a person-level account role and that Buyer/Seller may own Transport Provider profiles are superseded by the user's later approved NEXORA decision. Current target model: homepage registration roles are exactly Buyer, Seller and Porter; Porter registration creates a pending `profiles.role='porter'` account; only an approved active Porter may submit a linked Transport Provider profile and vehicles; Provider and each vehicle require separate Admin approval. Dispatch requires approved Porter account + approved Provider + approved/available vehicle. Admin roles are never public signup roles. For the current authoritative design, see [Foundation Design Proposal — Section 7](../supabase/recovery-not-for-deployment/local-setup/05_foundation_design_proposal.md#7-authoritative-design-resolutions-2026-11-13). The remainder of this file is retained as historical design context and must not be implemented where it conflicts with this notice.

# NEXORA Transport Provider & Vehicle Architecture

Status: Design specification for the Development branch only.
Scope: Replace the legacy assumption that Porter is a person-level account role.
No hosted database changes are made by this document.

## 1. Product decision

- Porter is NEXORA's transport/delivery service system, not a person or account role.
- A person or business that owns a vehicle or has lawful authority to operate it may apply to become a Transport Provider (Porter Provider).
- One provider may register multiple vehicles. This is an approved product decision.
- Admin review is required before a provider and its vehicles can receive delivery assignments.
- The provider's owner/operator remains a normal authenticated NEXORA user. Do not add `porter` to `profiles.role`.

## 2. Account and service model

Base account roles remain:
- `buyer`
- `seller`
- `admin`

A Buyer or Seller account can submit a separate Transport Provider application. The provider enrollment is not a role upgrade and must not replace the user's existing account role. If a future standalone transport-only signup is needed, it should still create a normal base user account and a linked provider record.

Recommended entities:

### `transport_providers`
- `id` UUID primary key
- `owner_user_id` UUID -> `profiles.id`
- `provider_type` (individual / business)
- `display_name`
- private contact and business details as required
- `application_status` (draft / pending / approved / rejected / suspended)
- admin review metadata: reviewer, reviewed_at, reason
- created_at, updated_at

Enforce ownership and prevent a user from changing approval/review fields directly. Define whether one user may have multiple provider profiles before implementing that rule; do not silently assume it.

### `transport_vehicles`
- `id` UUID primary key
- `provider_id` UUID -> `transport_providers.id`
- `vehicle_type`
- `registration_number` (private; never expose publicly by default)
- `capacity_value` and `capacity_unit`
- optional make/model/year and notes
- vehicle images and required document references
- `approval_status` (pending / approved / rejected / suspended)
- admin review metadata and timestamps

A provider can own multiple vehicle rows. Each vehicle is reviewed independently. A vehicle is eligible for dispatch only when both its provider and the vehicle itself are approved and active.

### Delivery assignment linkage
The delivery job must be assigned to a provider and a specific vehicle, not a Porter user:
- `assigned_provider_id` -> `transport_providers.id`
- `assigned_vehicle_id` -> `transport_vehicles.id`
- `assigned_by` -> admin user
- delivery status and append-only event history

Validate that the selected vehicle belongs to the selected provider and both are approved/active. Store the human operator/driver separately only after the driver model is decided. Do not assume the vehicle owner is always the driver.

## 3. Access and privacy rules

- Provider owner can view and manage only their own application and vehicle submissions.
- Owner cannot set approval status, reviewer, verification result, or protected identifiers.
- Admin access is permission-gated and MFA/AAL2-gated according to the existing NEXORA admin security model.
- Public marketplace must not expose private phone numbers, full documents, registration numbers, or full provider profiles.
- Delivery pickup/drop-off contact details are visible only to the authorized logistics staff and the provider/vehicle operator assigned to that job, for the duration and purpose of the job.
- Use RLS on every exposed table; use narrowly scoped RPCs for privileged review, approval, assignment, reassignment, and cancellation.

## 4. UI implications

Replace the old Porter role application with a separate section:
- "Transport Provider আবেদন"
- Provider/business details
- Add Vehicle (repeatable; multiple vehicles per provider)
- Document/image upload
- Application and per-vehicle review status
- Delivery work area shown to the authenticated provider owner/operator, not to a `porter` role

Admin Console should have separate queues for:
- Provider applications
- Vehicle reviews
- Delivery assignment and monitoring

## 5. Legacy code that must be refactored

The current Development branch still contains role-based Porter assumptions in:
- `index.html`: signup role option, role-request form option, test-account role option, Porter Center copy and job workspace, Admin assignment selector.
- `auth.js`: Porter role request submission/labels, Porter workspace navigation, role request moderation labels, user role filters.
- `marketplace.js`: `role === "porter"` access checks, Porter dashboard queries by `assigned_porter_id = auth.uid()`, and admin assignment/reassignment using Porter profile IDs.
- `supabase/migrations/20261113100000_create_porter_delivery_workflow.sql`: foreign key and policies require `profiles.role = 'porter'`; delivery assignments point directly to a profile.

These legacy pieces must not be treated as production-ready or applied to the hosted database. The migration must be redesigned before any application.

## 6. Safe implementation sequence

1. Audit existing profile role constraints, role-request policies, admin RPCs, and storage policies.
2. Refactor signup and role-request UI so Porter is not an account role.
3. Design provider and vehicle tables, constraints, indexes, RLS, storage access, and admin RPCs.
4. Redesign delivery jobs to reference provider + vehicle; preserve append-only event history.
5. Build provider application, multi-vehicle management, admin review, and dispatch UI.
6. Run static checks and SQL tests in a disposable/local environment; verify RLS and negative access cases.
7. Only after explicit user approval, consider applying a reviewed migration to a development database. Do not create a paid Supabase branch or deploy without approval.

## 7. Decisions intentionally left open

Do not invent answers for:
- Whether one user may own multiple provider profiles.
- Which exact vehicle documents are mandatory by vehicle type and country.
- Whether drivers need their own NEXORA login or may be managed as provider staff.
- Whether a vehicle can be temporarily unavailable, and the availability scheduling rules.
- Pricing, route optimization, GPS tracking, insurance, customs, or settlement integrations.

These require product/legal/operational decisions before implementation.

## 8. Implementation progress (2026-11-13)

Completed on `nexora-development`:
- Removed Porter from public signup and test-account role selectors.
- Added client-side allowlists so signup/test-account requests accept only Buyer or Seller.
- Removed Porter from role-request submission and active workspace navigation.
- Blocked access to the legacy Porter dashboard.
- Hid the legacy Admin Porter assignment panel and paused its legacy data loading.
- Replaced the old un-applied Porter-as-profile migration with an explicit no-op warning.
- Added staged migration `supabase/migrations/20261113180000_transport_provider_vehicle_model.sql`:
  - narrows profile roles to Buyer/Seller/Admin;
  - narrows role requests to Seller only;
  - creates private `transport_providers` and `transport_vehicles` tables;
  - allows one provider to register multiple vehicles;
  - adds owner/admin RLS policies and protected review fields.
- Added `transport-provider.js` and a Transport Provider Center entry point:
  - active Buyer/Seller accounts can open a separate provider workspace;
  - provider enrollment captures individual/business type, display/legal name, phone, country, city and operating address;
  - each provider record can have multiple independently registered vehicles;
  - each vehicle captures type, make/model, registration number/country, capacity and availability;
  - provider and vehicle review statuses are shown separately;
  - private registration data is not rendered in public marketplace cards.

Verification:
- Staged SQL executed inside a transaction and rolled back successfully.
- Follow-up check confirmed the new tables do not exist in the hosted database.
- Hosted database still has zero Porter-role profiles and the existing pending Seller request remains intact.
- New frontend JavaScript passed a JavaScript syntax compilation check.
- No live migration, deployment, paid resource, or production-branch change was performed.

Still pending:
- Apply the staged migration only after explicit approval and a safe test environment is available.
- Admin provider/vehicle review interface and audited review RPCs.
- New delivery-job schema referencing provider + vehicle.
- Private document/image Storage policies and upload flow.
- End-to-end browser and RLS negative-case tests.



## 9. Admin Transport Provider / Vehicle review (2026-11-13)

Completed on `nexora-development`:
- Added Admin Console queue for Transport Provider applications and their registered Vehicles.
- Queue shows the Provider's submitted business/contact/operating details to authorized Admins and lists each linked Vehicle independently.
- Added review actions:
  - Pending: approve, reject, suspend
  - Approved: suspend
  - Rejected or suspended: re-approve
- Reject and suspend require a reason of at least five characters; reasons are capped at 1,000 characters.
- Added staged migration `supabase/migrations/20261113200000_transport_provider_admin_review.sql`:
  - private `SECURITY DEFINER` review functions with empty search path;
  - explicit authenticated-user, active Admin membership, AAL2 and `logistics.assign` checks;
  - public invoker-rights RPC wrappers for PostgREST;
  - atomic status update plus `admin_audit_logs` insertion;
  - restricted execution grants (authenticated only);
  - Provider and Vehicle status-transition validation;
  - Vehicle approval is blocked until its parent Provider is approved.
- Admin review queue reads use existing `logistics.view` permission helper; review RPCs require `logistics.assign`. The currently configured Super Admin path is supported. Assistant Admin logistics grants are not yet present in the live permission catalog.

Verification:
- Full `auth.js` and `transport-provider.js` passed JavaScript syntax compilation.
- The new SQL functions and grants were executed inside a transaction and rolled back; no migration was applied.
- Read-only hosted DB check confirms `transport_providers`, `transport_vehicles`, and both review RPCs are still absent.
- No production deployment, paid resource, or `main` branch change.

Still pending:
- Browser/UI test with an Admin AAL2 session and real Provider/Vehicle test records.
- Apply both staged Transport migrations only after explicit approval and a safe test environment.
- Add Logistics permission catalog entries and assignable department policy before enabling Assistant Admin logistics review.
- Enforce both Provider and Vehicle approved statuses in the eventual delivery-assignment workflow.
- Private document/image Storage policies and upload flow.


## 10. Delivery Assignment System (2026-11-13)

Completed on `nexora-development`:
- Added staged migration `supabase/migrations/20261113220000_delivery_assignment_system.sql`.
- Added `delivery_jobs` with a generated NEXORA job reference, optional external order/shipment reference, package details, pickup and delivery contacts/addresses, requested pickup time, deadline and special instructions.
- Every job is created already assigned to a selected Transport Provider and Vehicle; no unassigned/unknown Porter account is used.
- Assignment validates inside the database that:
  - the Provider is approved;
  - the Vehicle is approved and currently available;
  - the Vehicle belongs to the selected Provider.
- Added `delivery_job_events` for assignment, reassignment and cancellation history.
- Added private SECURITY DEFINER functions plus public invoker-rights RPC wrappers:
  - `create_delivery_assignment`
  - `reassign_delivery_job`
  - `cancel_delivery_job`
- All write operations require an authenticated active Admin, AAL2 and `logistics.assign`.
- Reassignment is allowed only while a job is in `assigned` status and requires a reason.
- Cancellation requires a reason and is blocked for delivered/already-cancelled jobs.
- Delivery job and event tables are read-only to browser clients; no direct insert/update/delete grants are given.
- RLS limits job/event reads to Logistics Admins with `logistics.view` and the owner of the assigned Provider.
- Added assignable Logistics Admin department and sensitive permissions `logistics.view` / `logistics.assign`; no Assistant Admin receives these grants automatically.
- Added Admin Console form and queue for creating, viewing, reassigning and cancelling Delivery Jobs. Provider and Vehicle choices are restricted to approved Provider and approved/available Vehicle records.

Verification:
- Provider + Delivery staged migrations were executed together inside one transaction and rolled back successfully.
- `auth.js` passed JavaScript syntax compilation.
- Admin Delivery form and queue markup are present in `index.html`.
- No live migration, data insert, production deployment, paid resource, or `main` branch change was performed.

Scope / pending:
- Delivery jobs currently use an optional external reference; they are not yet automatically linked to a marketplace order because an approved order-to-logistics handoff model has not been implemented.
- Provider-side job acceptance, pickup/in-transit/delivered status updates, proof of delivery, notifications, pricing, route planning and vehicle capacity scheduling remain future work.
- The schema currently permits more than one active job to be assigned to a vehicle; concurrency/capacity scheduling policy is not yet defined.
- Confirm the project's Data API exposure settings for the new public tables before applying migrations; Supabase changed new-table exposure defaults in 2026.
- Add real browser tests and negative RLS/RPC tests with Admin MFA and Provider accounts before enabling in production.


## 11. Buyer and Seller market-category registration (2026-11-13)

Approved product decision:
- Buyer creates one account and selects exactly one active marketplace category at registration: `wholesale` or `retail`.
- A Buyer can switch their active category at any time from Buyer Center without creating another account. Account identity, orders, messages, demands and history remain attached to the same user.
- Seller creates one account and may select Wholesale, Retail, or both categories during registration.
- A Seller who selects both categories uses one Seller account and one Business Profile; category access is represented as a set, not separate user roles or duplicate accounts.
- Category values are controlled profile fields; users cannot self-change account role, account status, approval state or Seller category entitlements.
- Transport Provider enrollment remains separate from account roles and does not affect these categories.

Implementation staging:
- Registration UI captures Buyer category or one/both Seller categories.
- Buyer Center includes a category switch control.
- A staged database migration is required to persist `profiles.buyer_category` and `profiles.seller_categories`, validate registration metadata in `handle_new_user()`, and permit only the active Buyer to update their own Buyer category.
- Marketplace visibility filtering and product listing sale-mode are intentionally a separate follow-up: each product's wholesale/retail listing representation and price model must be finalized before filtering product rows. Do not assume one listing has dual prices.
- No hosted migration or deployment is performed as part of this design stage.
