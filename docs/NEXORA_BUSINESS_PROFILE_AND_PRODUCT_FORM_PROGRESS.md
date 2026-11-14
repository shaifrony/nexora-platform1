# NEXORA Business Profile, Sales Center & Initial Product Form

Updated: 2026-11-13
Branch: `nexora-development`

## Existing Business Profile foundation (verified by source inspection)

The current marketplace schema already contains:
- `public.business_profiles` with `seller_id UNIQUE` (one Business Profile per Seller account).
- A single `sales_center_address` field on that Business Profile.
- `public.public_businesses` as a limited public projection containing only business display name, country and city; it does not expose the full sales-center address.
- A trigger that publishes the public projection only when `approval_status='approved'` and removes it when the business is not approved.
- Seller-side Business Profile creation/update logic in `marketplace.js`; product creation is gated on an approved Business Profile.
- Multiple products reference the same `business_id`, so one sales center can own multiple product listings.

Relevant existing source: `supabase/migrations/20261112050345_create_marketplace_core_schema.sql`, `marketplace.js`.

## Changes made in this workstream

### Initial Product Listing Form
The public Seller Product Listing form in `index.html` has been reduced to the approved initial fields:
1. Product Name
2. Product Category
3. Product Images
4. Product Description
5. Origin
6. Specifications & Quality
7. Price & Currency

Removed from the initial form:
- Market-category selector (new listing is always wholesale)
- Subcategory/model field
- MOQ
- Stock tracking / stock quantity
- Quantity-based price tiers

The Seller product workspace's Retail filter was removed and replaced with a disabled Wholesale-only indicator.

### Product insert logic
`marketplace.js` now:
- Inserts `market_category='wholesale'` explicitly.
- Leaves `subcategory` null for the initial listing.
- Omits MOQ, stock and price-tier values so the database defaults apply.
- Keeps the approved Business Profile gate and Admin-pending listing status workflow.

## Git commits

- Product form simplification: `f36ee403ced6ad0d14bc0bf5322e32e5aeaf4a35`
- Product insert payload alignment: `954bd5884380fe99ced076b1d5e49a69d3052625`
- Seller workspace Retail filter removal: `17e211f3488b38816ba7984821fec1036f174869`

## Important limits

- These are staged frontend changes only. They have not been deployed.
- Existing legacy Retail data, database constraints, edit-request workflow, demand matching and order creation must be checked against universal Buyer visibility; Seller sale type remains per product only.
- Existing future-dated migrations in the branch must not be replayed into hosted Supabase because migration-history mismatch is unresolved.
- No local browser test or hosted Supabase test is claimed.
- The existing business profile schema and logic were inspected, not newly recreated or migrated in this change.

## Next implementation

1. Reconcile wholesale-only constraints across database, Auth trigger, listing edit workflow, demand matching and order RPCs in a recovery-only proposal.
2. Align Buyer Demand form and public demand preview with the required-by date and identity privacy.
3. Review the seller profile form's exact fields and ensure one sales-center address only.
4. Add stable public product detail links and ensure only Admin-approved products of Admin-approved businesses are discoverable.


## Decision update — 2026-11-14 (supersedes earlier Wholesale-only note)

The latest NEXORA Marketplace decision is no Wholesale/Retail product split: every user can view all approved products; Sellers choose their own price and quantity. The earlier Wholesale-only indicator and product market-category assumptions in this document are historical and no longer current. Current `index.html` and `marketplace.js` still contain Wholesale/Retail labels, filters, insert/edit payloads and demo examples; the corresponding staged SQL adds `products.market_category` and a Retail-specific MOQ rule. A coordinated frontend + migration cleanup is required before local rehearsal. This audit did not make a partial UI/schema change.


## Unified Marketplace implementation — 2026-11-14

The later unified Marketplace decision is now implemented in the development source (superseding the earlier wholesale-only form description and the pending dual-market note above):
- Product listing has no Wholesale/Retail selector. Product taxonomy category remains separate and is used for search/discovery.
- All users can browse all Admin-approved products; no product sale-type visibility filter remains.
- Seller create/edit and listing-review payloads no longer send a sale category. Seller price, minimum order quantity, quantity-based price tiers and optional stock tracking remain governed by the existing commercial-field workflow; Retail-specific MOQ=1 enforcement has been removed.
- Buyer Demand routing uses product category/subcategory and approved Seller/business status only.
- Buyer/Seller profile sale-category fields are no longer created; Porter registration is aligned with this profile shape.

Source-only status: updated frontend and staged migrations are on `nexora-development`. No hosted migration has been executed. Browser tests, SQL runtime tests and disposable database rehearsal remain pending.


## 2026-11-14 — Latest approved separate Wholesale/Retail Listing model

**This section supersedes the later unified-single-listing assumption above.** The Marketplace remains unified for discovery and access, but Wholesale and Retail are separate listing records.

- Buyer/Seller account roles do not split by sale type. There are no Buyer Wholesale/Retail account categories and no Seller account-level sale-type permissions.
- Every approved Wholesale and Retail Listing is visible to the same public/Buyer audience, subject to the normal approval and privacy rules.
- A Seller may create two separate Listing records for the same underlying goods: one Wholesale and one Retail. Each Listing has its own Product/Listing ID, permanent URL/slug, price, currency, terms, quantity/MOQ rules, images, approval status, edit history, negotiation history and order snapshot.
- In the current legacy schema, each row in public.products is effectively a listing record. The current active migration chain removed the former per-product market-category field, so the approved separate-listing model is **not yet implemented** in the database or frontend.
- Target compatibility approach: restore the established per-listing market_category field on public.products, with explicit wholesale/retail values for all new listings. The financial calculation module may normalize this value to its internal sale_type input. Existing rows must not be guessed into either category; retain a temporary legacy_unclassified state until the Seller confirms the correct type through a reviewed update flow.
- Once a Listing is published, its market_category is identity-defining and should not be changed in-place. To switch sale type, the Seller creates a separate Listing; existing orders and history retain the original Listing ID and terms.
- Public Marketplace search defaults to both sale types; filters may narrow to wholesale or retail but never restrict a user's account visibility.
- Buyer Demand matching remains product taxonomy + approved Seller/Business eligibility. It must not filter by Buyer/Seller account category or hide one sale type.
- Order creation, product price negotiation, review eligibility and financial calculation must bind to the exact Listing ID and snapshot market_category, price, currency and applicable terms.
- Migration must preserve existing Product IDs, slugs, images, prices, reviews and historical Orders. Existing records must not be silently duplicated or assigned an invented sale type.
- This is a source/design alignment note only. No SQL migration, schema or database was changed by recording it.
