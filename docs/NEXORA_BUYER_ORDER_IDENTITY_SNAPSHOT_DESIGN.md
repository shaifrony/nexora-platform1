# NEXORA — Buyer Order Identity Snapshot Design

Updated: 2026-11-14
Branch: `nexora-development`
Status: **Verified source contract; implementation blocked by Foundation/migration-history gate. This document is not SQL and is not deployable.**

## Goal

Buyer Order History must show the exact item name and the Seller's approved public Business Display Name captured when the order was created. Later listing or Business Profile edits must not rewrite the historical order identity.

## Verified source schema

### Commerce Orders

`public.commerce_orders` is created in `20261114140000_commerce_orders_and_review_completion.sql`. It has a polymorphic `listing_type/listing_id`, Buyer/Seller IDs, quantity, unit price, currency, fulfilment and lifecycle fields. It has no item-name or Seller-display-name snapshot columns.

The later `20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql` extends it for `listing_type='buyer_demand'`, with `source_demand_id`, `source_offer_id`, `delivery_charge`, `source_offer_total` and generated `grand_total`.

### Trusted name sources

- Product: `public.products.product_name`; Product has `business_id` and `seller_id`.
- Service: `public.service_listings.service_name`; Service has `business_id` and `seller_id`.
- Buyer Demand conversion: `public.buyer_demands.product_name`; Demand has the Buyer identity, while the responding Seller comes from `public.seller_offers.seller_id`.
- Approved public Seller name: `public.public_businesses.display_name`, matched by BOTH `business_id` and `seller_id`. The public projection is synchronized only for approved Business Profiles. It exposes only public Business display name and location fields; do not query `profiles.full_name`, email, phone or private addresses for Buyer presentation.

### Effective order-creation functions

1. Direct Product/Service: the latest staged `private.create_commerce_order(text,uuid,numeric,text,text)` definition is replaced in `20261114150000_product_inventory_moq_quantity_pricing.sql`. It validates the approved listing, active Seller, public Business projection, MOQ, stock and tier price, then inserts the order. This is the correct place to capture Product/Service snapshots in the same transaction.
2. Buyer Demand quotation conversion: `private.respond_to_demand_offer(uuid,text,numeric,numeric,text)` in `20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql` locks the offer and Demand, validates Buyer/Seller role and turn-taking, computes agreed quantity/price/total, then inserts a `buyer_demand` Commerce Order. It is the correct place to capture the Demand product name and responding Seller's public Business Display Name.
3. Service title is verified as `service_listings.service_name` in `20261114090000_services_marketplace.sql`.

The final Demand conversion function and all three name-source schemas have now been located and reviewed. This removes the previous source-discovery blocker.

## Proposed additive data contract

Add nullable fields to `public.commerce_orders`:

| Column | Purpose |
|---|---|
| `item_name_snapshot` | Product, Service or Demand product name at order creation |
| `seller_display_name_snapshot` | Approved Seller Business Display Name at order creation |
| `identity_snapshot_at` | Server timestamp for the paired snapshot |

Nullable fields preserve historical orders created before this feature. Never backfill the current listing or Business name into an old order and represent it as the original name.

## Required migration behavior

The future additive migration must:

1. Be generated with `supabase migration new` only after Foundation and active migration history are reconciled. Do not invent a timestamp or add a file to the active migration chain before that gate.
2. Add the three nullable snapshot fields. No browser RPC parameter may accept either name.
3. Replace the latest effective `private.create_commerce_order` body while preserving its current validations and stock/tier logic:
   - Product path: lock/read the approved Product; capture `product_name`; resolve `public_businesses.display_name` by the Product's exact `business_id + seller_id`.
   - Service path: read the approved Service; capture `service_name`; resolve the matching public Business display name by exact `business_id + seller_id`.
   - If the approved public Business row is absent or does not match the listing Seller, fail closed. Never fall back to private profile identity.
4. Replace the latest effective `private.respond_to_demand_offer` body while preserving offer locking, expiry, role checks, negotiation turn-taking, price calculations, order/event inserts and offer updates:
   - Capture `buyer_demands.product_name`.
   - Resolve `public_businesses.display_name` by the responding `seller_offers.seller_id`; ensure the public Business projection belongs to that Seller.
   - Store the snapshots in the same Commerce Order INSERT.
5. Ensure snapshots are insert-only server values. Browser roles must not gain INSERT/UPDATE on Commerce Orders. Review all existing column grants and add a narrowly scoped immutable-field guard if any trusted update path could otherwise alter snapshots. Do not break the existing transition RPCs.
6. Do not modify historical rows except leaving the new fields NULL.
7. Preserve current RLS ownership: Buyer/Seller participants may read their order row under existing policies; no additional profile or listing join is needed by the Buyer UI.

## Buyer UI contract

After the schema is safely staged and verified, extend `loadBuyerOrders()` to select only the three snapshot fields and render them using the existing `esc()` helper:

- Show the item snapshot and Seller public display-name snapshot in each order card.
- For NULL legacy snapshots, show `পুরোনো অর্ডার — নাম সংরক্ষিত হয়নি` (or separate neutral item/Seller fallback labels).
- Never join the live Product, Service, Demand or Seller profile to fill missing historical values.
- Preserve latest-50 ordering, status filters/timeline, amount breakdown, Seller update, delivery disclosure and the statement that an order request is not payment or a delivery booking.

## Required synthetic acceptance/security tests

- Product order captures exact Product name and approved public Business name.
- Service order captures exact Service name and approved public Business name.
- Buyer Demand quotation order captures original Demand product name and the responding Seller's approved public Business name.
- Renaming Product, Service, Demand text or Business display name after order creation does not change existing order snapshots.
- Client-supplied snapshot fields cannot be written or changed.
- Buyer A cannot read Buyer B's order or snapshots; Seller cannot alter snapshots.
- Anonymous access remains denied.
- No Seller legal name, personal phone, email, private address, profile fields or internal notes are exposed.
- Existing stock reservation, MOQ/tier price, Demand negotiation turn-taking, order totals, status transitions and review eligibility remain unchanged.
- Run isolated SQL, PostgREST/JWT/RLS and browser/mobile E2E using synthetic accounts only.

## Current status and blocker

**Source contract verified.** The three order-creation paths, name-source columns and approved public Business projection are now identified. The remaining blocker is not source discovery: the repository still lacks a reconciled Foundation baseline and safe complete migration history. NEXORA-TEST remains empty and must not receive partial feature migrations. Therefore this pass does not add a guessed frontend select, SQL migration, or database change. Once the Foundation/migration gate is cleared, implement the additive migration, then update the Buyer order card and run the synthetic acceptance suite.

No NEXORA-TEST, hosted database, Live/Production, `main`, DNS, paid service or deployment was changed.
