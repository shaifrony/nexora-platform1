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

