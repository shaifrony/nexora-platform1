# NEXORA Commerce Order and Verified Completion Workflow

## Scope in this staged MVP

- Product orders support both Wholesale and Retail products.
- Service bookings support approved services with a fixed positive `price_amount`.
- Logistics booking/consignment is intentionally not included; the current logistics workflow is Admin-assigned and does not represent customer checkout.
- No online payment, escrow, refund, inventory/stock, shipping label, courier booking, MOQ enforcement, tax, or international customs calculation is implemented.

## Order lifecycle

1. Buyer creates an order request for an approved listing. The database snapshots seller, listing, unit price, currency and quantity. Product quantity is selected by Buyer; service quantity is fixed at one.
2. Seller accepts or rejects a pending request. Rejection requires a reason.
3. After accepted order fulfilment, Seller marks it ready for Buyer confirmation (product dispatched / service completed).
4. Only the original Buyer may confirm completion.
5. In the same database transaction, completion records an immutable event and creates a private one-time Verified Purchase eligibility record for the exact Buyer, listing, order reference, quantity and completion timestamp.
6. Buyer may then submit one Verified Review for that listing using the review RPC.

Buyer can cancel only a pending order. The Seller cannot mark an order completed on the Buyer's behalf. Status changes are locked and validated in database functions.

## Data access

- `commerce_orders`: Buyer and Seller can read only their own orders.
- `commerce_order_events`: visible only to participants of the related order.
- Browser direct writes are revoked. Create and transition operations use authenticated RPCs that call guarded private functions.
- Purchase eligibility remains in `private.review_purchase_eligibility`; browser roles cannot insert or update it.
- The order completion function runs in the same transaction as eligibility issuance, so a partial completion cannot grant a review.

## User interface

- Product detail page: Buyer can send an order request with quantity, fulfilment location and optional note.
- Service detail page: Buyer can request a booking when a positive fixed service price is listed; negotiable/unpriced services require prior discussion.
- Buyer Dashboard: lists orders and allows cancellation of pending orders or confirmation when ready.
- Seller Dashboard: lists incoming orders and allows accept/reject and fulfilment-ready actions.

## Known limitations / next stages

- Wholesale MOQ and quantity-tier pricing are not yet part of product schema; this MVP accepts positive quantity only.
- Product stock reservation and overselling protection are not implemented.
- Payment is offline/arranged separately; this workflow does not claim payment verification.
- Buyer confirmation is the trust signal for completed purchase; add dispute window, evidence, refund/return, and Admin dispute resolution before commercial launch.
- Service scheduling/calendar, provider attendance, and customer confirmation evidence remain future work.
- Logistics orders require a separate consignment/transport contract model.
- The Review Eligibility schema currently allows the logistics type, but the review submission RPC deliberately rejects logistics until a customer logistics job lifecycle exists.

## Release safety

All schema/UI work is staged on `nexora-development`. Do not apply migrations to the hosted database or deploy production without explicit user approval. Run SQL integration tests and browser E2E before launch.
