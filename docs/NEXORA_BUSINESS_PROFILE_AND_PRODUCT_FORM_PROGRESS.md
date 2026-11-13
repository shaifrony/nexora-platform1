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
