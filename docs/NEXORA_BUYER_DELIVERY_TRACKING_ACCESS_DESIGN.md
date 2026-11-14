# NEXORA — Buyer Order History & Customer-safe Delivery Tracking

**Status:** Customer-safe tracking projection implemented on `nexora-development`; staged only, not deployed.
**Updated:** 2026-11-15

## 1. Buyer Order History

The Buyer dashboard now:
- Shows the latest 50 orders, newest first, with status filters and an explicit latest-50 label.
- Shows order subtotal, delivery charge, grand total, status timeline, Seller update and next action.
- Fetches customer-safe delivery updates for the visible order IDs through one narrow RPC call.
- Groups multiple shipment/job updates under the owning Commerce Order by non-sensitive job reference.
- Keeps Buyer completion separate from delivery-reported status. A Buyer must receive and inspect the goods before confirming the order complete.

The card continues to use order code and listing type; it does not infer a product name from an unverified join.

## 2. Privacy boundary

Raw operational tables remain private to the existing logistics roles:
- No Buyer SELECT policy was added to `delivery_jobs`, `delivery_tracking_events`, or assignment history.
- Pickup/delivery names, phone numbers, exact addresses, GPS, provider identity, Admin identity, assignment history, internal notes and raw external tracking codes are not returned to Buyers.
- The projection lives in `private.delivery_customer_updates`, has no browser table grants, and rejects UPDATE/DELETE.
- The authenticated RPC checks that the caller is an active Buyer and returns updates only when `commerce_orders.buyer_id = auth.uid()`.

## 3. Implemented migration

Staged migration: `supabase/migrations/20261115130000_buyer_safe_delivery_updates.sql`.

An AFTER UPDATE trigger on `delivery_jobs.job_status` maps trusted operational states to a fixed customer vocabulary and authored Bangla message. It never copies operational `note`, `location_description`, address or contact fields.

| Operational state | Buyer-facing state |
|---|---|
| assigned / accepted | preparing |
| picked_up | picked_up |
| in_transit | in_transit |
| out_for_delivery | out_for_delivery |
| partially_delivered | partially_delivered |
| delivered | delivered |
| delivery_failed / disputed | delivery_issue |
| returned | returned |
| cancelled | cancelled |

Only jobs linked to a Commerce Order create customer-facing updates. Multiple jobs per order are supported. An order with no published update returns no fabricated tracking event; the UI says that no customer update is available yet.

**Important:** `delivered` means the delivery operator reported delivery. It does not transition the Commerce Order to `completed`, release review eligibility, or bypass the Buyer confirmation action.

## 4. Validation

Development CI run [#43652641287](https://github.com/shaifrony/nexora-platform1/actions/runs/43652641287), commit `14969619faa85d105d8ea9d08fb31b98d5a955fd`:
- JavaScript syntax passed.
- 120/120 dependency-free regression tests passed.
- Buyer Demand PostgreSQL integration passed.
- Product Price Negotiation PostgreSQL integration passed.
- Buyer-safe delivery projection migration executed against an isolated disposable PostgreSQL database.
- SQL assertions passed for status mapping, append-only records, Buyer A/Buyer B isolation, no direct private-table access, and no anonymous RPC execution.
- 40 active migration filenames/order checks passed.

The delivery projection test uses a minimal PostgreSQL fixture. It is not a full migration-chain replay or full Supabase Auth/PostgREST/browser E2E test.

## 5. Remaining B-04 delivery work

Not yet implemented in this increment:
1. Buyer receipt OTP / alternative proof-of-delivery and secure one-time verification.
2. Admin/Delivery Coordinator order-to-job creation and assignment UX completion.
3. Provider/NEXORA Team/Courier operational end-to-end flows from the Buyer Order card through receipt.
4. Delivery charge quote, Buyer checkout, payment ledger and settlement.
5. Partial shipment quantity reconciliation, disputes, failed delivery and returns.
6. Full isolated migration-chain rehearsal, Supabase Auth/JWT/PostgREST/RLS negative tests and browser/mobile E2E.

Do not expose raw delivery tables to Buyers to complete these items. Keep customer-safe projections additive and narrowly scoped.

## 6. Release safety

All changes remain staged on `nexora-development`. No hosted Supabase migration, NEXORA-TEST/live database mutation, Production deployment, DNS/public alias change or `main` change was made. Do not apply the migration or deploy without explicit user approval.
