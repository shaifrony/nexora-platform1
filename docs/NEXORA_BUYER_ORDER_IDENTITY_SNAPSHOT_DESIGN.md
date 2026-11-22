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

### Effective order writers and source paths

There are **three distinct Commerce Order INSERT paths**. All three must capture the paired snapshots in the same transaction; replacing only the shared direct-order RPC is insufficient.

1. **Direct Product/Service order:** the latest staged `private.create_commerce_order(text,uuid,numeric,text,text)` definition is in `20261114150000_product_inventory_moq_quantity_pricing.sql`. Its Product branch locks `public.products` and already holds `product_name`, `business_id` and `seller_id`; its Service branch reads `service_listings` and must be extended to retain `service_name`, `business_id` and `seller_id`. It inserts both Product and Service orders. Preserve MOQ, stock reservation, price-tier and active-account behavior.
2. **Product Price Negotiation acceptance:** `private.respond_to_product_price_negotiation(uuid,text,numeric,numeric,text,text)` in `20261115110000_product_price_negotiation.sql` independently inserts a `listing_type='product'` Commerce Order after mutual acceptance. It locks the negotiation and Product in `v_n`/`v_p`, then reserves stock and inserts the order directly; it does **not** call `private.create_commerce_order`. This writer must be explicitly replaced or refactored in the future migration. The current acceptance body checks that the Product remains approved but does not revalidate the approved `public_businesses` projection at order creation. The earlier negotiation-start function checks that projection by `business_id` only. Future acceptance must fail closed unless the current public row matches both `v_p.business_id` and `v_p.seller_id`.
3. **Buyer Demand quotation conversion:** `private.respond_to_demand_offer(uuid,text,numeric,numeric,text)` in `20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql` locks the Demand and Offer, validates active Buyer/Seller participation and negotiation turn-taking, computes agreed quantity/price/total, then inserts a `listing_type='buyer_demand'` order directly. Capture `buyer_demands.product_name` and the responding Seller's approved public Business Display Name, resolved from `public.public_businesses` by `seller_id=v_offer.seller_id` (the Demand has no Product/business foreign key).

### Public Business projection and identity boundary

`public.public_businesses` exposes `business_id`, `seller_id`, `display_name`, country and city only. The `business_profiles` synchronization trigger inserts/updates the projection only while `approval_status='approved'` and deletes it when approval is withdrawn. Product and Service listings carry both `business_id` and `seller_id`; their snapshot lookup must match both. Buyer Demand has no Business ID, so its snapshot lookup is by the responding Offer's Seller ID. Never use `profiles.full_name`, email, phone, private address, Business admin note or any other private identity as a fallback.

All three effective order writers and the Product, Service, Demand and public Business source schemas have now been located and reviewed. The source-discovery blocker is closed, but the additional Product Price Negotiation writer and its missing acceptance-time public-Business revalidation are now explicit implementation requirements.

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
4. Replace `private.respond_to_product_price_negotiation` in `20261115110000_product_price_negotiation.sql` as a separate order writer. Preserve negotiation locking/turn-taking, Product lock, MOQ, stock reservation, agreed price and event updates; at acceptance, resolve `public_businesses.display_name` by exact `v_p.business_id + v_p.seller_id` and fail closed if the approved projection is missing or mismatched. Store the Product and Seller snapshots in this function's own Commerce Order INSERT; do not assume it calls `create_commerce_order`.
5. Replace the latest effective `private.respond_to_demand_offer` body while preserving offer locking, expiry, role checks, negotiation turn-taking, price calculations, order/event inserts and offer updates:
   - Capture `buyer_demands.product_name`.
   - Resolve `public_businesses.display_name` by the responding `seller_offers.seller_id`; ensure the approved public Business projection belongs to that Seller.
   - Store the snapshots in the same Commerce Order INSERT.
6. Ensure snapshots are insert-only server values across **all three writers**. Browser roles must not gain INSERT/UPDATE on Commerce Orders. Review all existing column grants and add a narrowly scoped immutable-field guard if any trusted update path could otherwise alter snapshots. Do not break the existing transition RPCs.
7. Do not modify historical rows except leaving the new fields NULL.
8. Preserve current RLS ownership: Buyer/Seller participants may read their order row under existing policies; no additional profile or listing join is needed by the Buyer UI.

## Buyer UI contract

After the schema is safely staged and verified, extend `loadBuyerOrders()` to select only the three snapshot fields and render them using the existing `esc()` helper:

- Show the item snapshot and Seller public display-name snapshot in each order card.
- For NULL legacy snapshots, show `পুরোনো অর্ডার — নাম সংরক্ষিত হয়নি` (or separate neutral item/Seller fallback labels).
- Never join the live Product, Service, Demand or Seller profile to fill missing historical values.
- Preserve latest-50 ordering, status filters/timeline, amount breakdown, Seller update, delivery disclosure and the statement that an order request is not payment or a delivery booking.

## Required synthetic acceptance/security tests

- Direct Product order captures exact Product name and approved public Business name.
- Direct Service order captures exact Service name and approved public Business name.
- Mutually accepted Product Price Negotiation order captures the Product and approved public Business name, including a test where Business approval is withdrawn after negotiation starts but before acceptance.
- Buyer Demand quotation order captures original Demand product name and the responding Seller's approved public Business name.
- Renaming Product, Service, Demand text or Business display name after order creation does not change existing order snapshots.
- Client-supplied snapshot fields cannot be written or changed.
- Buyer A cannot read Buyer B's order or snapshots; Seller cannot alter snapshots.
- Anonymous access remains denied.
- No Seller legal name, personal phone, email, private address, profile fields or internal notes are exposed.
- Existing stock reservation, MOQ/tier price, Demand negotiation turn-taking, order totals, status transitions and review eligibility remain unchanged.
- Run isolated SQL, PostgREST/JWT/RLS and browser/mobile E2E using synthetic accounts only.

## Current status and blocker

**Source contract verified and corrected (2026-11-22).** All three actual Commerce Order INSERT writers are identified: direct Product/Service via `private.create_commerce_order`, Product Price Negotiation via `private.respond_to_product_price_negotiation`, and Buyer Demand quotation conversion via `private.respond_to_demand_offer`. The Product Price Negotiation writer bypasses the shared order RPC and currently does not revalidate the approved public Business projection at acceptance; the future migration must explicitly replace it and enforce the exact Product Business + Seller match. The remaining blocker is the unreconciled Foundation baseline and complete migration history. NEXORA-TEST remains empty and must not receive partial feature migrations. Therefore this pass does not add a guessed frontend select, SQL migration, or database change. Once the Foundation/migration gate is cleared, implement the additive migration across all three writers, then update the Buyer order card and run the synthetic acceptance suite.

No NEXORA-TEST, hosted database, Live/Production, `main`, DNS, paid service or deployment was changed.
