# NEXORA Business-Level Verified Review — Design & Security Gate

**Status:** Design only; not an active migration and not applied to any database.  
**Branch:** `nexora-development`  
**Scope:** Buyer Demand quotation orders only. Existing Product and Service reviews remain unchanged.

## 1. Why a separate Business review is required

A Buyer Demand order is created with `commerce_orders.listing_type = 'buyer_demand'`, and it stores the Demand and Seller through `source_demand_id`, `source_offer_id`, and `seller_id`. It does not guarantee a Seller Product ID. A Demand order must therefore never be represented as a Product review or be assigned a fabricated Product ID.

The Seller has one Business Profile per Seller account: `business_profiles.seller_id` is unique. The stable review subject is consequently `business_profiles.id`, with `listing_type = 'business'`.

## 2. Confirmed existing contracts

- `private.review_purchase_eligibility` currently allows `product`, `service`, and `logistics`; it is private and inaccessible to anon/authenticated.
- `public.listing_reviews` currently allows the same three subject types and already has a unique index on `(listing_type, listing_id, buyer_id)`. This naturally enforces one review per Buyer per Business once `business` is admitted.
- `public.get_my_review_eligibility(text, uuid)` and `public.submit_verified_listing_review(text, uuid, smallint, text, text)` are the existing RPC contract used by the generic review UI helpers in `marketplace.js`.
- The existing submit RPC validates active Buyer, approved Product/Service listing, verified eligibility, one-review rule and consumes eligibility transactionally. It must be extended without weakening those checks.
- `commerce_orders` already carries `listing_type`, `buyer_id`, `seller_id`, `quantity`, `completed_at`, and `order_status`. Demand-order conversion sets `listing_type='buyer_demand'`.
- `business_profiles.seller_id` is unique; the Business subject ID is the profile's primary key.

## 3. Critical pre-existing privacy finding — must fix before expanding reviews

The current review migration grants table-level `SELECT` on `public.listing_reviews` to `anon, authenticated`. RLS policies restrict which *rows* can be read, but table-level SELECT also permits selecting every column of a published review, including `buyer_id`, `reviewed_by`, and `moderation_note`. The current frontend happens to select a limited column list, but that is not a security boundary: a caller can request those columns directly through PostgREST.

**Required hardening in the next genuine forward migration:**

1. Revoke table-level SELECT from `anon, authenticated`.
2. Grant column-level SELECT only for the public review fields actually required by the UI and summary RPC: `id, listing_type, listing_id, rating, review_title, review_body, reviewer_label, purchased_quantity, review_status, created_at`.
3. Keep `buyer_id`, `reviewed_by`, `moderation_note`, and other internal fields unavailable to API roles. Do not add them to a public view or grant.
4. Preserve the existing RLS row policies. Column grants do not replace RLS.
5. Verify that `get_listing_review_summary` still works as SECURITY INVOKER with only the necessary column grants, and that authenticated/anon cannot select any withheld column.
6. Review any future moderation workflow separately; staff must use narrow audited RPCs rather than broad public column grants.

This is a pre-existing exposure in the staged review schema, not evidence that a hosted database has been changed. The migration has not been applied to hosted environments.

## 4. Business eligibility creation

Use a private trigger function on `public.commerce_orders` for the transition from a non-completed state to `completed`:

- Only process `NEW.listing_type = 'buyer_demand'`.
- Resolve `business_profiles.id` by the order's `seller_id`; never accept a client-supplied Business ID.
- Insert one private eligibility row with:
  - `listing_type = 'business'`
  - `listing_id = business_profiles.id`
  - `buyer_id = NEW.buyer_id`
  - `purchase_reference = 'commerce_order:' || NEW.id::text`
  - `purchased_quantity = NEW.quantity`
  - `completed_at = NEW.completed_at` (fallback to `now()` only if the completion contract legitimately permits null; otherwise fail closed).
- Use `ON CONFLICT DO NOTHING` against the existing eligibility uniqueness key to make trigger retries/idempotent updates safe.
- Trigger only on a real transition into completed, not on unrelated order edits or repeated completed updates.
- Do not generate eligibility for pending, accepted, ready, cancelled or rejected orders.
- Add a one-time backfill for already-completed Buyer Demand orders when the forward migration is eventually applied. It must use the same Seller-to-Business join and unique purchase reference, and must not create eligibility for non-Demand orders.

The trigger function must be private, SECURITY DEFINER only because it writes the private eligibility table from a commerce-order transition, have a fixed `search_path`, validate all source fields from `NEW`, and have execution revoked from `PUBLIC, anon, authenticated`. No client RPC may insert or edit eligibility.

## 5. Review RPC extension

- Add `business` to the check constraints for both `private.review_purchase_eligibility.listing_type` and `public.listing_reviews.listing_type` using explicit drop/recreate of the known constraints after confirming their catalog names in the replayed database.
- Extend `get_my_review_eligibility('business', business_id)` through the existing private eligibility table. Do not return Buyer ID, order ID, or private order data.
- Extend `submit_verified_listing_review` so `business` resolves `business_profiles.id` and its `seller_id`. Reject self-review, inactive/non-Buyer accounts, invalid rating/body/title, missing unconsumed eligibility, and duplicate Buyer/Business review.
- For Business reviews, do not require the Business to remain currently approved at submission time: a genuine completed order should not lose review eligibility merely because the Business was later suspended. Public visibility remains controlled by Business publication/moderation rules and review_status.
- Lock the selected eligibility row `FOR UPDATE`; insert the review and consume eligibility in the same transaction. Keep the existing one-review-per-Buyer-per-subject unique index as the final concurrency guard.
- Do not expose order IDs, Buyer identity, Seller private profile, contact details, quotation or negotiation history in a public review.

## 6. Frontend contract

The existing generic review helpers in `marketplace.js` already accept `listingType` and `listingId`, call the three review APIs, and render public review fields. Reuse them on a Business detail surface with `listingType='business'` and the public Business ID from `public_businesses.business_id`. Do not use the Seller profile ID as the review subject ID.

The review form must appear only when the RPC says `can_review=true`; UI visibility is convenience, never authorization. Refresh eligibility and review list after submit. Show a neutral “Verified Buyer” label, never Buyer name or account ID.

## 7. Required isolated replay/API tests

1. Completed Buyer Demand order creates exactly one Business eligibility row.
2. Repeated update while already completed creates no duplicate.
3. Two concurrent completion attempts create one eligibility row.
4. Pending, accepted, ready, cancelled and rejected orders create none.
5. Product/Service orders do not create Business eligibility.
6. Seller without a Business Profile creates no eligibility and raises a visible operational/test failure rather than inventing a subject.
7. Buyer A can see eligibility for their own Business subject; Buyer B cannot.
8. Anonymous caller cannot call private eligibility or submit-review RPC.
9. Buyer cannot supply another Business ID or another Buyer ID.
10. Seller cannot review their own Business.
11. Inactive Buyer and non-Buyer roles are denied.
12. Review insert consumes eligibility atomically; replay/duplicate submit is denied.
13. Multiple completed orders from the same Buyer to the same Business still allow only one review.
14. Two concurrent submissions yield one review only.
15. Public review list and summary work for anon/authenticated.
16. Direct PostgREST requests for `buyer_id`, `reviewed_by`, `moderation_note` are denied for anon/authenticated.
17. Published review displays only neutral reviewer label and public review fields.
18. A Business suspended after completion does not erase the Buyer’s genuine eligibility; public visibility remains independently controlled.
19. Existing Product and Service review flows still pass regression tests.
20. All relevant RLS, column grants, function execute privileges, fixed search paths and SECURITY DEFINER owners are inspected in catalogs.

## 8. Release gates and non-actions

- Do not edit historical migrations in place.
- Do not generate or rename a migration timestamp manually. The latest active migration is `20261115120000_multilingual_chat_foundation.sql`; wait until the CLI naturally generates a later timestamp.
- Do not apply to NEXORA-TEST, Live/Production, or deploy until Foundation/migration history reconciliation and a clean disposable local replay pass.
- No review schema, frontend, hosted DB, Production, deployment, DNS, or paid-service change is made by this design document.
- Browser/mobile E2E remains a separate release gate; static parsing is not a substitute.

## 9. Recovery-only grant candidate prepared (not executed)
- `supabase/recovery-not-for-deployment/local-setup/31_listing_reviews_column_grants_recovery_candidate.sql` contains the narrow revoke/table-column grant change.
- `supabase/recovery-not-for-deployment/local-setup/32_listing_reviews_column_grants_recovery_test.sql` asserts that anon/authenticated have no table-level SELECT and cannot read `buyer_id`, `reviewed_by`, or `moderation_note`, while the intended public columns and summary RPC remain available.
- These files are test/recovery artifacts only. They have not been run because a clean disposable replay is still blocked by unresolved Foundation/migration history. Do not apply them to a hosted database or treat the privacy issue as fixed until the test and real JWT/PostgREST checks pass.
