# NEXORA Buyer Demand Inbox & Seller Quotations

This workflow is staged on `nexora-development` only. It has not been applied to the hosted database or deployed.

## Buyer flow
- Buyer posts a product Demand with category, subcategory, description, specifications, quantity, optional budget, currency, destination and required date.
- Example: category `Electronics`, subcategory `Mobile Phones`.
- Buyer identity and private contact details are not exposed to Sellers through the public Demand projection or Seller inbox.

## Seller routing
- An inbox row is created for every eligible Seller who has an approved Product listing matching the Demand category and subcategory.
- The Seller's product sales channel must match the Buyer's active `buyer_category` (Wholesale or Retail), and the Seller must be active, registered for that channel, and have an approved Business Profile.
- Matching is exact for category and case-insensitive exact for subcategory. If a legacy Demand has no subcategory, category-only matching is used.
- Routing happens when a Demand is created and when a matching Product is newly approved or updated. Existing open Demands are backfilled at migration time.
- A Seller can read only Demands routed to their own inbox; a Seller can submit an offer only for a Demand in that inbox.
- Public Demand Board remains a privacy-safe summary. Quotation submission is available from the targeted Seller Inbox.

## Structured Seller quotation
Each Seller may submit one quotation per Demand, containing:
- Product brand and model
- Condition: new, refurbished, used, or any
- Price and currency, marked as per-unit or total
- Available quantity
- Optional delivery charge, estimated delivery date, warranty, offer validity date and additional terms

Buyer sees all received quotations in the Buyer Dashboard, including price, model, condition, supply quantity, delivery details, warranty and offer validity.

## Product subcategories
- Sellers enter a Product Subcategory (e.g. Mobile Phones, Laptop, Tablet).
- Buyers select a matching Subcategory in their Demand.
- Seller can add or change subcategory on a pending listing directly.
- For an already approved Product, Seller submits subcategory, MOQ and quantity-tier price changes through the existing Admin-reviewed Listing Change Request workflow.
- The Admin approval RPC and immutable before/after snapshot are extended to retain these fields.

## Security model
- `buyer_demand_inbox` has RLS and seller-owned SELECT only; browser INSERT/UPDATE/DELETE is revoked.
- Database trigger functions route Demand rows using approved Product listings and account/category eligibility.
- Buyer Demand SELECT for authenticated Sellers is limited to a row in their own inbox.
- Seller offer INSERT is limited to the matching Seller, an active Seller account, approved Business Profile, and open inbox Demand.
- The public Demand projection omits buyer ID and contact information and uses a security-invoker view so underlying RLS remains effective.

## Limitations / not production-tested
- No push notification, SMS or email alert is sent yet; new inbox items appear when Seller Dashboard refreshes/loads.
- Buyer quotation acceptance, counter-offers, negotiation chat linking and quotation-to-order conversion are future work.
- Matching depends on Sellers maintaining accurate Product Category and Subcategory fields.
- No browser end-to-end test or hosted migration execution has been performed.
