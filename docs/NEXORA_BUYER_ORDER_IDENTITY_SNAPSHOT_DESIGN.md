# NEXORA — Buyer Order Identity Snapshot Design

Updated: 2026-11-14  
Branch: `nexora-development`  
Status: **Design only — not SQL, not deployable, not applied**

## Goal

Buyer Order History should show the ordered item's name and the Seller's approved public Business Display Name without exposing private profile data. The names must represent what the Buyer ordered at the time the order was created, not whatever a listing or business is renamed to later.

## Verified current source facts

- `public.commerce_orders` currently stores `listing_type`, polymorphic `listing_id`, Buyer/Seller IDs, quantity, unit price, currency and order lifecycle fields. The base order table does not define an item-name or Seller-display-name snapshot column.
- The current Buyer order query selects order and price/status fields only. It does not join a listing or Seller profile to invent a historical label.
- The direct Product/Service order creation function is `private.create_commerce_order`; its latest staged definition inserts into `commerce_orders` using validated listing data. It is the correct server-side place to capture snapshots for direct Product/Service orders.
- Buyer Demand quotation conversion also creates Commerce Orders through a separate quotation-response workflow. Its final effective function definition and exact source migration still need to be located and reviewed before a schema change is designed for that path.
- Seller public identity must come from the approved public Business projection (`public.public_businesses`), never from a direct Buyer-facing read of `profiles.full_name`, email, phone, private address or the full Seller profile.
- Existing Commerce Order listing IDs are polymorphic. A client-side lookup against a guessed table or an unverified join is not safe.

## Proposed additive data contract

Add nullable, immutable snapshots to `public.commerce_orders`:

| Column | Purpose |
|---|---|
| `item_name_snapshot` | Product, Service or Demand-derived item name captured at order creation |
| `seller_display_name_snapshot` | Approved public Business Display Name captured at order creation |
| `identity_snapshot_at` | Timestamp when the server captured both names |

The exact SQL types, constraints, index needs and migration dependency must be validated against the reconciled Foundation and current migration chain before generating a migration.

## Server-side snapshot rules

1. Only the trusted order-creation RPC sets these fields. Never accept either snapshot value from browser parameters.
2. For direct Product orders, load the approved Product row under the same transaction/locking and use its current `product_name`.
3. For Service orders, use the validated public Service listing title only after the Service schema is confirmed.
4. For Buyer Demand quotation conversions, use the original Demand's product name and the responding Seller's approved public Business Display Name; verify the exact conversion RPC and source relationship first.
5. Resolve the Seller name through the approved public Business projection with matching Seller/business ownership. Do not use `profiles.full_name` as a fallback.
6. Store both names once. Later Product/Service/Demand edits or Business Display Name changes must not update historical order snapshots.
7. Protect snapshots from browser INSERT/UPDATE. Keep order creation and transition under the existing guarded RPC model; add explicit column privileges/trigger protection as appropriate after reviewing all existing grants and RPCs.
8. For historical orders where the true creation-time name was never stored, do not backfill the current listing/business name and pretend it is historical. Keep the snapshot NULL and display a neutral fallback such as “পুরোনো অর্ডার — নাম সংরক্ষিত হয়নি”.
9. A missing/unapproved public Business projection must fail order creation rather than leak private profile identity or write a guessed Seller name.

## Buyer UI contract

- Select only the new snapshot fields after the migration is safely staged and the schema is available.
- Render values through the existing `esc()` HTML-escaping helper.
- Show item name and public Seller display name above the order totals.
- For legacy NULL snapshots, show the explicit neutral fallback; do not query the live listing name and imply it is historical.
- Preserve order filters, status timeline, delivery/total breakdown, Seller update, and “order request is not payment/delivery booking” disclosure.

## Required validation before calling it complete

- Direct Product order captures Product name + approved Business Display Name.
- Service order captures the correct Service title + approved Business Display Name.
- Buyer Demand accepted quotation captures Demand product name + responding Seller public Business Display Name.
- Product rename and Business Display Name change after order creation do not alter existing order cards.
- Client-supplied snapshot values are rejected/ignored.
- Buyer A cannot read Buyer B's orders or snapshots; Seller cannot alter Buyer-facing snapshots.
- Anonymous users cannot read Commerce Orders.
- No Seller email, phone, legal name, private address, profile fields or internal notes are exposed.
- Existing status transitions, inventory reservation, totals, review eligibility and Demand quotation turn-taking remain unchanged.
- Run isolated SQL tests, authenticated PostgREST/RLS tests and browser/mobile E2E after the migration history and Foundation are reconciled.

## Current blocker / safe next action

The staged order table demonstrably lacks snapshot columns, and the final Buyer Demand conversion RPC plus exact public projection schema still require source-level verification. Therefore no frontend query, guessed join, SQL migration, or NEXORA-TEST mutation is made in this pass. First reconcile and inspect the final effective Demand conversion function and public projection, then create a natural-timestamp migration with the Supabase CLI only after the Foundation/migration-chain gate is cleared.

No hosted database, NEXORA-TEST, Live/Production, `main`, DNS, paid service or deployment was changed.
