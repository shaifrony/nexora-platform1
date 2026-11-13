# NEXORA Buyer Demand Inbox & Seller Quotations

This workflow is staged on `nexora-development` only. It has not been applied to the hosted database or deployed.

## Buyer flow
- Buyer posts a product Demand with category, subcategory, description, specifications, quantity, optional budget, currency, destination and required date.
- Example: category `Electronics`, subcategory `Mobile Phones`.
- Buyer identity and private contact details are not exposed to Sellers through the public Demand projection or Seller inbox.

## Seller routing
- An inbox row is created for every eligible Seller who has an approved Product listing matching the Demand category and subcategory, and an approved public Business Profile.
- **Wholesale/Retail sale type does not restrict Demand matching.** Buyer has no account-level market category; Seller's sale type belongs to each Product. Any eligible Seller with a matching approved product taxonomy can receive the Demand regardless of `market_category`.
- Matching is exact for category and case-insensitive exact for subcategory. If a legacy Demand has no subcategory, category-only matching is used.
- Routing happens when a Demand is created and when a matching Product is newly approved or updated. Existing open Demands are backfilled by the migration.
- A Seller can read only Demands routed to their own inbox; a Seller can submit an offer only for an open Demand in that inbox.
- Public Demand Board remains a privacy-safe summary. Quotation submission is available from the targeted Seller Inbox.

## Structured Seller quotation
Each Seller may submit one quotation per Demand, containing:
- Product brand and model
- Condition: new, refurbished, used, or any
- Price and currency, marked as per-unit or total
- Available quantity
- Optional delivery charge, estimated delivery date, warranty, offer validity date and additional terms

Buyer sees received quotations in the Buyer Dashboard, including price, model, condition, supply quantity, delivery details, warranty and offer validity.

## Product subcategories
- Sellers enter a Product Subcategory (e.g. Mobile Phones, Laptop, Tablet).
- Buyers select a matching Subcategory in their Demand.
- Seller can add or change subcategory on a pending listing directly.
- For an already approved Product, Seller submits subcategory, MOQ and quantity-tier price changes through the existing Admin-reviewed Listing Change Request workflow.
- The Admin approval RPC and immutable before/after snapshot are extended to retain these fields.

## Security model (staged source design; runtime verification pending)
- `buyer_demand_inbox` has RLS and Seller-owned SELECT only; browser INSERT/UPDATE/DELETE is revoked.
- Private trigger functions route Demand rows using approved Product listings, active Seller account, approved public Business Profile and Product category/subcategory.
- Routing does not use Buyer/Seller account categories or the Product Wholesale/Retail `market_category`.
- Buyer Demand SELECT for authenticated Sellers is limited to a row in their own inbox and open Demand status.
- Seller offer INSERT is limited to the matching active Seller, approved public Business Profile and open Demand in that Seller's own inbox.
- The public Demand projection is a SECURITY INVOKER view that omits Buyer ID and contact information; its underlying RLS and limited anonymous column grants remain in effect.
- Anonymous access is intended to be limited to the open public projection; Buyer ID, private inbox and Seller offers are not public.

## Lifecycle and limitations
- Buyer can close or cancel their own open Demand. Seller quotation insertion is allowed only while the Demand is open.
- One quotation per Seller per Demand is enforced by a unique constraint.
- Buyer quotation acceptance, counter-offers, negotiation chat linking and quotation-to-order conversion are not implemented yet.
- No push notification, SMS or email alert is sent yet; new inbox items appear when Seller Dashboard refreshes/loads.
- Matching depends on Sellers maintaining accurate Product Category and Subcategory fields.
- No browser end-to-end test or hosted migration execution has been performed.


## Local Demand fixture validation path (not hosted)
- For a focused local test only, use fixtures 06 + 21 followed by local Demand fixture 25, read-only audit 24 and transactional behavior tests 26 via runner 27.
- This is a reconstructed minimum test schema. It is not the complete app schema or a recovered migration. Do not deploy or move it into `supabase/migrations/`.
- Local tests cannot establish actual hosted Supabase Auth/JWT/PostgREST/RLS behavior. Buyer quotation acceptance/counter-offer/order conversion remain future work.
