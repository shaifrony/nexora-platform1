# NEXORA Buyer Demand Progress

Updated: 2026-11-13

## Scope

This document records the current Buyer Demand implementation inspected on the `nexora-development` branch. It is a code review snapshot, not a hosted deployment or runtime test report.

## Current Buyer Demand form

The existing `index.html` form with ID `demandForm` currently collects:

1. Product name (required)
2. Category (required)
3. Product subcategory / specific type (required)
4. Description (required)
5. Specifications and quality requirements (required)
6. Required quantity (required)
7. Budget (optional)
8. Currency (required)
9. Destination country (required)
10. Destination city / destination (required)
11. Required date (required)

The form includes a date input whose minimum is set client-side to the user's local current date during page initialization.

## Current submission behavior

The initial marketplace core migration (`20261112050345_create_marketplace_core_schema.sql`) defines `buyer_demands` without a `subcategory` column. The later migration `20261114160000_demand_inbox_quotations_subcategories.sql` adds the column and updates the public Demand view and grants. The final migration chain still requires local rehearsal because the repository migration history is not reconciled with Hosted Supabase.

The `marketplace.js` submit handler:
- Requires an active Buyer session.
- Validates optional budget as a non-negative number.
- Inserts the Buyer ID from the authenticated session, not from a form field.
- Sends product/category/subcategory, description, specifications, required quantity, optional budget, currency, destination country/city and required date to `buyer_demands`.
- Shows a success message and returns the Buyer to the dashboard after successful insert.

The public demand board reads from `public_buyer_demands`, not directly from `buyer_demands`. Its client query selects demand fields such as product name, category, description, specifications, quantity, budget, currency, destination and required date. It does not request Buyer ID, name, email, phone or other direct contact fields.

The Seller Demand Inbox reads from `buyer_demand_inbox` and filters by the logged-in Seller ID; it requires an Admin-approved Business Profile before showing matched demands or accepting quotations.

## Important verification boundary

The frontend query shape is not sufficient proof of database privacy. The underlying view definition, grants, RLS policies, matching trigger/function and seller inbox access rules still need a schema-level review. Do not treat hidden UI fields or selected-column lists as the security boundary.

No database schema, migration, hosted Supabase project, production deployment or live data was changed during this review. No browser or hosted integration test was run.

## Next implementation/review steps

1. Inspect the exact `public_buyer_demands` view definition and grants to confirm it exposes only approved public demand fields and no Buyer identity/contact data.
2. Inspect `buyer_demands` RLS and INSERT/SELECT/UPDATE policies, including ownership and allowed status transitions.
3. Inspect demand matching logic and `buyer_demand_inbox` access to confirm only eligible approved Sellers receive relevant demand records.
4. Confirm Seller quotations cannot reveal Buyer contact data before an accepted communication/consent flow.
5. Align Demand matching with the universal visibility model: route a Buyer Demand to every eligible Seller with an approved product matching category/subcategory, regardless of Wholesale/Retail sale type; keep Buyer identity/contact private.
6. Add focused tests for privacy, ownership, unauthorized Seller access, closed/cancelled demands, required-date validation and quotation eligibility.
