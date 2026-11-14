# NEXORA — Buyer Order History & Customer-safe Delivery Tracking Design

**Status:** Design contract v1 — documentation only. Not SQL, not deployable, not applied.
**Branch:** `nexora-development`
**Date:** 2026-11-14

## 1. Buyer Order History UI

The Buyer order panel now includes:
- A compact count summary for the currently fetched set (new, active, completed).
- Status filtering: all, pending, accepted, ready for Buyer confirmation, completed, cancelled and rejected.
- The latest 50 orders, newest first. The UI explicitly says it is showing the latest 50; it does not mislabel that subset as the lifetime total.
- Per-order status explanation, authoritative order timestamps, subtotal/delivery charge/grand total, Seller update, and Buyer next action.
- A Buyer must not confirm completion merely because a Seller or delivery operator marked a parcel delivered. Actual receipt and inspection remain the Buyer's decision.

The current order schema has no product snapshot/name field. The card therefore identifies the order by its order code and listing type rather than attempting an unverified product-name join. A future order snapshot design may store a safe title at order creation.

## 2. Current delivery schema findings

The staged design currently links `delivery_jobs.commerce_order_id` to Commerce Orders and supports multiple jobs per order (there is an index, not a uniqueness guarantee). Delivery status history is stored in `delivery_tracking_events`.

The current tracking event row contains operational fields such as `location_description`, `note`, and `external_tracking_code`. The current RLS read policies are for authorized logistics Admin staff and assigned independent Providers. There is no Buyer read policy in the staged tracking migration.

Delivery jobs also contain pickup/delivery addresses and contact names/phone numbers. Those are operationally sensitive and must not be exposed through a broad Buyer SELECT policy.

**Decision:** Do not grant Buyers SELECT on raw `delivery_jobs`, `delivery_tracking_events`, provider assignment history, or operational contact fields. Do not add a broad Buyer RLS policy to the existing raw tracking table.

## 3. Customer-safe tracking contract

When Foundation and migration-history blockers are resolved, implement an additive customer-facing projection rather than exposing raw operational records.

Recommended new append-only table: `public.delivery_customer_updates` (name provisional).

Minimum fields:
- `id`, `job_id`, `commerce_order_id`
- `customer_status`: constrained customer vocabulary such as `preparing`, `picked_up`, `in_transit`, `out_for_delivery`, `delivered`, `delivery_issue`, `returned`, `cancelled`
- `customer_message`: explicitly authored and reviewed customer-facing text; never copied automatically from internal `note`
- `customer_location_label`: optional coarse location/area only; never GPS coordinates or a private pickup/delivery address
- `public_tracking_code`: optional only when the courier/provider explicitly confirms it is customer-shareable
- `created_at`, `published_at`, `created_by`

The projection must support more than one delivery job per order, e.g. split/partial shipments. The Buyer sees the updates grouped under their own Commerce Order, with each shipment/job separately identified by a non-sensitive public reference.

## 4. Read API and authorization

Preferred interface: a narrow authenticated RPC such as `get_my_order_delivery_updates(p_order_id uuid)` that:
1. Requires a real signed-in user (`auth.uid()` not null).
2. Verifies the requested order exists and `commerce_orders.buyer_id = auth.uid()`.
3. Joins only customer-published updates for jobs linked to that exact order.
4. Returns only the customer-safe fields above, ordered by `published_at`/creation time.
5. Returns no pickup/recipient names, phone numbers, exact addresses, internal notes, Admin identity, provider personal data, assignment history, or hidden/unpublished updates.
6. Does not infer that a delivery job exists when none has been created.

Keep raw operational tables' existing Admin/Provider policies unchanged. If implemented as a SECURITY DEFINER function, place the implementation in the non-exposed `private` schema, set an empty/strict `search_path`, explicitly validate `auth.uid()` and Buyer ownership inside the function, revoke default PUBLIC/anon execution, and expose only a narrowly scoped authenticated wrapper. Review function ownership and execute grants; do not use SECURITY DEFINER merely to work around an RLS error.

## 5. Event publication and status mapping

- Operational tracking transitions remain authoritative in `delivery_tracking_events`.
- A separate publication step creates a customer update only after a trusted Admin/Provider status update succeeds.
- Never publish raw operator `note` or `location_description` automatically.
- A safe mapping layer converts operational statuses to customer statuses. Unknown/internal states remain hidden until explicitly mapped.
- `delivered` means the delivery operator reported delivery; it does **not** set Commerce Order to `completed`.
- Only the Buyer can complete the Commerce Order using the existing server-validated transition after actual receipt, subject to the order's current allowed state.
- Disputed, returned, failed, or partially delivered cases need clear Buyer instructions and a future support/dispute workflow; do not falsely mark the whole order complete.

## 6. Required security and acceptance tests

Use synthetic Buyer A, Buyer B, Seller, Provider and Admin accounts in an isolated disposable database only.

1. Buyer A can fetch updates for A's order; Buyer B cannot fetch A's order by changing the UUID.
2. Buyer cannot fetch another Buyer's job, raw tracking event, assignment history, exact address, phone or internal note.
3. Anonymous user cannot call the RPC.
4. Seller cannot read Buyer-only customer projection unless a separately approved role contract explicitly allows it.
5. Assigned Provider/Admin can continue their existing operational access; customer projection does not weaken operational policies.
6. An order with no delivery job returns an explicit “tracking not available yet” state, not a fabricated status.
7. Split shipments show separate shipment histories without exposing another order's updates.
8. Hidden/unpublished updates never appear; customer messages are length-limited and sanitized.
9. Operational `delivered` never completes the Commerce Order; Buyer completion remains a separate action.
10. Verify RLS, grants, RPC execution privileges, PostgREST response shape, negative authorization cases and mobile UI.

## 7. Current release gate

Blocked pending:
- Foundation baseline reconciliation and migration history repair/rehearsal.
- Resolution of the two active migrations sharing version `20261114180000`; do not rename manually or invent timestamps.
- A CLI-generated migration and isolated disposable database test.
- Runtime Auth/PostgREST/RLS/RPC and Buyer-vs-other-user negative tests.

No SQL, NEXORA-TEST, Live/Production, `main`, DNS, paid service or deployment was changed for this design.
