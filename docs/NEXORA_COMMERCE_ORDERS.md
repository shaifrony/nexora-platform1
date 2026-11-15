# NEXORA Commerce Order and Verified Completion Workflow

## Current staged scope

- Product orders support all approved products; the Buyer does not choose a Wholesale/Retail account category. Seller commercial terms remain product-specific.
- Product orders enforce Seller-defined MOQ, optional stock tracking/reservation and quantity-tier unit pricing. The agreed unit price and quantity are snapshotted on the order.
- Service bookings support approved services with a fixed positive `price_amount`; service quantity is one. Negotiable/unpriced services require prior discussion.
- Buyer Demand quotations support Seller initial quotes, alternating Buyer/Seller counter-offers, accept/reject, expiry checks, quantity ceilings and source-linked Commerce Order conversion.
- Buyer Demand orders preserve the agreed goods subtotal and quoted delivery charge separately; the generated grand total is the sum of those values.
- Logistics booking/consignment is not a separate customer checkout product. The current delivery workflow is linked to eligible Commerce Orders by an authorized Admin.
- No online payment gateway, escrow, payment capture, provider settlement, refund or payout ledger is implemented. A stored quote or delivery charge is not evidence of payment.

## Order lifecycle

### Product and Service orders

1. Buyer creates an order request for an approved listing. The database snapshots Seller, listing, quantity, unit price, currency and fulfilment location.
2. Seller accepts or rejects a pending request. Rejection requires a reason.
3. Seller marks an accepted order ready for Buyer confirmation.
4. Only the original Buyer can confirm completion. Buyer may cancel only a pending order.
5. Completion records an immutable event and creates a private one-time Verified Purchase eligibility record in the same transaction.
6. Buyer may then submit one Verified Review for that listing using the review RPC.

### Buyer Demand quotation orders

1. Buyer publishes a Demand with required quantity, destination and required date.
2. Seller submits a quote. The database initializes negotiation state itself and caps quoted quantity to the Buyer Demand quantity.
3. Buyer and Seller take turns countering; the party who made the latest proposal cannot accept or reject their own proposal.
4. Acceptance creates one Commerce Order linked to the source Demand and Seller Offer. The agreed quantity, unit price, goods subtotal, currency and delivery charge are snapshotted.
5. The same Buyer/Seller order lifecycle governs fulfilment and Buyer confirmation.

## Inventory and pricing rules

- MOQ is enforced at order creation.
- If stock tracking is enabled, order creation locks the Product and reserves available stock atomically.
- Pending order cancellation or Seller rejection releases the reservation; Buyer completion deducts stock and releases the reservation.
- Seller inventory changes use a guarded RPC. Stock cannot be reduced below outstanding reservations or tracking disabled while reservations remain.
- Up to 20 increasing quantity tiers may be configured; the highest qualifying tier determines the unit price.
- These controls prevent ordinary concurrent overselling through the order RPC, but full load/concurrency and browser/API integration testing remain release gates.

## Delivery, evidence and disputes

- An authorized Admin can link an eligible ready Product Order to a Delivery Job; the operation rechecks and locks the source Order.
- Assigned identity-bound delivery staff can update permitted operational statuses, submit private photo/signature evidence and record partial delivered quantities. Staff cannot mark a job delivered; Buyer receipt OTP remains the final delivery confirmation.
- Buyer/Seller order views have a scoped delivery-operations read path and can raise a delivery dispute. Assigned workers may also raise a dispute; Admin review requires the appropriate permission and AAL2.
- Evidence storage is private and scoped. Raw proof/dispute tables are not directly exposed to browser roles.
- These capabilities are staged on Development; isolated Supabase Storage signed-access, browser/device, accessibility and mobile-upload tests remain pending.

## Data access and audit

- `commerce_orders`: Buyer and Seller can read only their own orders.
- `commerce_order_events`: visible only to participants of the related order.
- Browser direct writes to protected order tables are revoked. Creation and transition use authenticated RPCs and guarded private functions.
- Review eligibility is private; browser roles cannot insert or update it.
- Order transitions lock the order row and validate actor, role, ownership and current status in the database.
- Delivery proof and dispute records are private and append-only through guarded functions.

## Remaining work before commercial launch

- Payment intent/collection, payment status verification, reconciliation and idempotent provider webhooks.
- Refund, return, chargeback and dispute-to-finance workflows.
- Double-entry ledger, maker-checker controls, provider payable, NEXORA fee/commission, delivery charge collection and settlement.
- Delivery charge calculation/approval, provider cost and settlement rules; a quoted delivery charge alone does not collect funds.
- Tax, customs, currency conversion and international trade compliance.
- Service scheduling/calendar, provider attendance and service-specific completion evidence.
- Full Supabase CLI migration-chain replay, hosted Auth/JWT/PostgREST/RLS verification, isolated Storage policy/signed-access tests, browser/device E2E, accessibility, mobile upload and concurrency/load tests.

## Release safety

All schema/UI work is staged on `nexora-development`. Do not apply migrations to hosted Supabase, mutate NEXORA-TEST, change `main`, or deploy Production without explicit user approval. The hosted migration history is not reconciled with the staged migration chain; do not apply only the latest migration.
