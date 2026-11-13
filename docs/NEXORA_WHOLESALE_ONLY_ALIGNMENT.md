# NEXORA Wholesale-Only Marketplace Alignment

Updated: 2026-11-13
Branch: `nexora-development`

## Confirmed product rule

NEXORA is a wholesale-only marketplace. Retail discovery, retail seller registration, retail product listings and single-unit retail order flows are out of scope.

## Implemented in this change

The public signup client in `auth.js` now:
- Forces Buyer signup metadata to `buyer_category: wholesale`.
- Sends Seller signup metadata with only `seller_categories: ["wholesale"]`.
- Rejects a non-wholesale Buyer category.
- Rejects a non-wholesale category change in the Buyer profile helper.
- Hides/disables Retail options in the public signup category controls when the form is initialized/refreshed.
- Keeps the public role allowlist limited to Buyer, Seller and Porter.

Commit: `5cf7d674dca7162fa07999f119c52c5f94129aa7`.

## Important scope limitation

This is a frontend/auth-metadata alignment only. It is **not** a database security boundary. Existing marketplace UI and database migrations still contain Wholesale/Retail concepts. A user can bypass browser controls if the database still accepts retail values.

Do not claim NEXORA is fully wholesale-only enforced until all of the following are reconciled and implemented in the correct ordered migration chain:
1. Profiles Buyer/Seller category constraints.
2. Product market-category and MOQ/price-tier constraints; remove retail-only behavior.
3. Product discovery filters and listing forms.
4. Existing retail rows: decide an explicit migration/archival policy; do not silently delete or rewrite user data.
5. Order/quotation policies that assume retail or single-unit quantities.
6. Buyer Demand and Seller matching must use wholesale requirements.
7. RLS/RPC and Auth trigger must reject forged retail metadata and direct writes.

## Onboarding rules to preserve

- Homepage signup offers exactly Buyer, Seller, Porter; no Admin.
- Buyer is active without Admin approval.
- Seller may register and complete business details without prior approval, but business/storefront and product listings stay unpublished until Admin approval.
- Porter registration creates a pending account; Admin/Transport approval is required before Porter work access.
- No user may self-change role, account status, verification state or protected fields.

## Next implementation sequence

1. Audit current schema/migration history and identify every Wholesale/Retail field/constraint/policy.
2. Prepare a recovery-only SQL proposal for review; do not place it in migrations or run it against hosted Supabase until migration history is reconciled.
3. Align Product Listing form with the approved initial fields only: Product Name, Category, Product Images, Product Description, Origin, Specifications & Quality, Price & Currency.
4. Enforce one Business Profile and one Sales Center per business, with multiple products under that Sales Center.
5. Keep product public visibility behind Admin approval.
6. Align Buyer Demand with required-by date and private Buyer identity/contact details.

## Safety

- Work only on `nexora-development`.
- No hosted database writes, migration replay, production deployment, DNS changes or paid services.
- Existing staged migration-chain mismatch remains a release blocker.
