# NEXORA Verified Purchase Review System

## Purpose

Reviews are available for Product and Service listings only when the signed-in Buyer has a trusted completed-purchase eligibility record. The Buyer account that completed the transaction is the only account allowed to submit the review.

## Supported listing types

- `product`: covers both Wholesale and Retail products. The listing's `market_category` remains the source of the sale channel.
- `service`: covers completed service bookings/jobs.
- `logistics`: reserved in the eligibility schema, but submission remains disabled until the logistics consignment/job completion model is implemented.

## Trust boundary

The browser cannot create or modify purchase eligibility. Eligibility records live in the non-exposed `private.review_purchase_eligibility` table. Only a trusted backend using the Supabase `service_role` can insert these records after independently confirming a completed order/service job. Never let a browser-supplied order ID, screenshot, or client-side status create eligibility.

The current NEXORA database does not yet have `orders` or `order_items` tables. Therefore the migration creates the secure review foundation and detail-page UI, but no Buyer can yet receive verified eligibility until the future order/service completion workflow writes the eligibility record.

## Database objects

- `private.review_purchase_eligibility`: trusted one-time review grants keyed by listing, Buyer, and purchase reference; includes purchased quantity and completion time.
- `public.listing_reviews`: published reviews; stores listing type/ID, Buyer ID, 1–5 rating, optional title, review body, purchased quantity, and moderation fields.
- `public.get_my_review_eligibility(type,id)`: authenticated Buyer checks whether they can review.
- `public.submit_verified_listing_review(...)`: validates active Buyer, approved listing, seller exclusion, one-review-per-Buyer/listing, and unconsumed purchase eligibility; consumes the grant atomically.

## Privacy and abuse controls

- Public review cards display the generic `Verified Buyer` label; no Buyer name, email, phone, or profile ID is exposed.
- Review reads are limited to published reviews, the author, or an AAL2 Admin.
- Browser direct INSERT/UPDATE/DELETE privileges are revoked. Submission happens through a restricted RPC.
- A unique index prevents duplicate reviews for the same Buyer/listing even under concurrent requests.
- Eligibility is consumed atomically with review creation.
- Review text is bounded to 10–2,000 characters; title to 2–100 characters; rating to 1–5.

## UI

Product Details and Service Details pages contain a Review & Rating section. It displays published reviews and summary rating. The form appears only when the authenticated Buyer has a valid eligibility grant. Otherwise it explains that a completed verified purchase is required.

## Required future integration

When an order becomes `delivered/completed` (and after any dispute/cancellation rules), the trusted order-completion backend should insert one eligibility row per purchased listing line. For services, create eligibility only after the service job is confirmed completed. Use the original Buyer ID from the order, exact listing ID, a stable purchase reference, purchased quantity, and completion timestamp. Do not trust the client to submit these values.

Before production:
1. Implement Orders/Order Items and service booking/completion lifecycle.
2. Add server-side eligibility issuance to the trusted completion transaction.
3. Define a dispute window and review moderation workflow.
4. Run database tests and browser E2E for ownership, replay, concurrency, and privacy.
5. Apply migrations only after explicit approval; no live migration or deployment is included in this staged work.
