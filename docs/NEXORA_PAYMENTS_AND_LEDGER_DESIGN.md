# NEXORA Payments, Finance Ledger and Settlement — Design Gate

Status: **Initial provider-neutral database foundation implemented; provider integration and full finance workflows remain pending.** This document is a design boundary, not evidence that payments are collected or funds are held. It is staged on `nexora-development` only.

## 1. Non-negotiable invariants

- A Commerce Order, quotation, delivery charge, payment intent, provider callback or uploaded receipt is not proof that money was received.
- Only a verified provider event or a separately authorized, audited manual reconciliation may move a payment into a financially settled state.
- The browser must never write payment status, ledger entries, balances, refunds, fees, payout state or provider settlement state directly.
- Every monetary amount is stored as integer minor units (for example, paisa) with an ISO 4217 currency code. Never use floating-point arithmetic for money.
- One immutable provider event ID is processed at most once. Duplicate, delayed, reordered and invalid-signature callbacks must be safe.
- Every posted journal entry is balanced per currency; posted entries are immutable. Corrections use reversing entries, never edits/deletes.
- No cross-currency balancing. FX requires an explicit conversion record with source/target amounts, rate, timestamp, provider/reference and approval.
- No payment, refund or settlement is considered complete solely because an Order is marked completed or delivered.

## 2. Proposed bounded contexts

1. **Checkout & Payment Intent** — records the amount/currency/order snapshot, chosen payment method/provider, expiry and lifecycle. Intent creation is idempotent per client request key and order/payment attempt.
2. **Provider Adapter** — isolates provider-specific request signing, callback verification, status lookup, refund API and provider references. Provider secrets stay server-side in managed secrets; never in Git or browser code.
3. **Payment Events Inbox** — stores raw provider event identity and minimal verified metadata, unique on (provider, provider_event_id). Verify signature before accepting an event; persist then process transactionally. Invalid callbacks are rejected and security-logged without changing money state.
4. **Reconciliation** — compares internal intents/transactions with provider settlement reports and bank statements. Differences enter an exception queue; they are not silently auto-corrected.
5. **Double-entry Ledger** — append-only journal headers and lines, balanced by currency, with source references and immutable posting.
6. **Refunds & Disputes** — refund requests, approvals, provider refund references, chargeback lifecycle, evidence and ledger reversals/adjustments.
7. **Payables & Settlement** — seller/provider payable calculation, hold/reserve, payout batches, maker-checker approvals, transfer references and reconciliation.
8. **Audit & Reporting** — actor, permission, AAL2, before/after metadata, reason, correlation IDs and immutable financial event trail.

## 3. Order and payment state separation

Order fulfillment and payment are separate state machines. A delivery/Order transition must not imply a payment transition.

Suggested payment intent states:
`created → pending_provider → authorized → captured`
with terminal/exception states `failed`, `expired`, `cancelled`, `requires_review`.

Refund states:
`requested → approved → submitted_to_provider → succeeded`
or `rejected`, `failed`, `requires_review`.

Payout states:
`draft → awaiting_second_approval → approved → submitted → paid`
or `rejected`, `failed`, `reconciled_exception`.

Provider callbacks are hints until signature, provider account, amount, currency, reference, expected state and provider-side transaction status are verified. A callback cannot change a captured payment to failed or reverse a posted ledger entry.

## 4. Minimum ledger model

- `finance_accounts`: account code, account type, currency, active flag; protected from browser writes.
- `finance_journals`: source type/id, idempotency key, posting status, currency, created/posted timestamps, actor/system origin.
- `finance_journal_lines`: journal ID, account ID, debit minor units, credit minor units, currency, optional order/payment/provider dimensions.
- `payment_intents`: order, payer, provider, amount minor units, currency, request idempotency key, provider reference, status and timestamps.
- `payment_transactions`: provider transaction reference, intent, amount, currency, transaction type/status and verified timestamp.
- `provider_webhook_events`: provider, unique event ID, signature verification result, payload hash, received/processed timestamps, processing result.
- `refunds`: source transaction, amount, reason, requester, approver, provider reference and state.
- `settlement_batches` / `settlement_items`: payee, gross, fees, reserves, refunds/chargebacks, net, currency, transfer reference and reconciliation state.
- `finance_approvals`: immutable maker/checker decisions, actor, permission, MFA assurance, reason and timestamps.

All financial tables belong in a non-exposed schema or otherwise have explicit no-browser-write grants and RLS defense in depth. Public RPCs, if any, are SECURITY INVOKER wrappers over narrowly scoped private functions; SECURITY DEFINER is exceptional and must validate `auth.uid()`, active role, permission and AAL2 where required.

## 5. Ledger posting examples

- Successful customer capture: debit provider-clearing/cash-in-transit; credit customer-funds-held (or the applicable revenue/liability account according to the legal funds-flow model).
- Refund: debit the corresponding customer-funds-held/refund liability; credit provider-clearing. The refund provider confirmation is required before posting the completed-refund entry.
- Seller/provider payable: debit the applicable customer-funds-held/clearing liability; credit seller/provider payable.
- Platform commission: recognize only under an approved accounting policy and actual contractual trigger; do not infer it from an Order.
- Payout: debit seller/provider payable; credit bank/provider payout clearing.
- Provider fees, taxes, chargebacks, reserves and FX are separate lines with explicit source evidence.

The exact chart of accounts and whether NEXORA is agent, marketplace facilitator, merchant of record or payment intermediary must be confirmed with the business/legal/accounting model before production posting. This design does not assume NEXORA may custody customer funds.

## 6. Authorization and operational controls

- Buyer can create an intent only for their own eligible Order and may read only their own payment summary.
- Seller can read only the minimum payment/settlement status needed for their own Orders; never other participants' bank or payment credentials.
- Provider/courier roles cannot read payment instruments or approve payouts.
- Accounts staff can prepare/reconcile but cannot approve their own financial action.
- A distinct authorized checker approves refunds above policy thresholds, manual capture/reconciliation adjustments and payout batches. Maker and checker must be different active identities.
- High-risk approval requires MFA AAL2, permission-scoped access, reason, immutable audit and transaction locking.
- Webhook endpoints authenticate provider signatures independently; do not rely on a user JWT for provider callbacks.
- Rate limits, replay protection, request-size limits, strict schema validation, secret rotation and alerting are required.

## 7. Required verification before enabling real money

- Disposable PostgreSQL tests for amount/currency tampering, duplicate and out-of-order webhooks, signature failure, concurrent capture, duplicate refund, over-refund, payout double approval, maker=checker, cross-tenant access and ledger imbalance.
- Full Supabase migration-chain replay; real Auth/JWT/PostgREST/RLS tests; advisors; private schema and grants review.
- Provider sandbox tests using a provider selected by the business owner, with test credentials stored outside Git.
- Reconciliation tests against provider settlement exports and controlled bank-statement fixtures.
- Browser/mobile E2E and failure/retry tests.
- Legal/accounting sign-off on fund flow, custody, fees, tax, refunds, chargebacks, reserves, seller contracts and payout timing.
- Explicit approval before hosted migration, provider credentials, live payment, payout or Production deployment.

## 8. Decisions still required before provider integration

- Bangladesh launch provider(s) and merchant account ownership.
- Whether checkout is hosted redirect, provider SDK or another supported flow.
- NEXORA's legal funds-flow role and who is merchant of record.
- Commission, delivery fee, tax/VAT, refund window, reserve and settlement policies.
- Seller/provider KYC requirements and payout bank/mobile-financial-service destination.
- Whether manual/offline payments are supported and the evidence + maker-checker policy.

Until these are decided, implement provider-neutral ledger and reconciliation foundations only; do not hard-code a gateway, claim online payment support, or enable live money movement.


## 9. First Development implementation — 2026-11-15

Migration `20261115220000_payment_intent_webhook_foundation.sql` now stages the first provider-neutral database foundation on `nexora-development`:

- Private, RLS-enabled `payment_intents`, `payment_transactions`, `provider_webhook_events`, currency precision, chart-of-account, journal and journal-line tables. Browser roles receive no direct table privileges.
- `public.create_payment_intent` is Buyer-authenticated, requires an active Buyer and Seller plus an accepted/ready Order, snapshots the Order amount, enforces a request idempotency key and permits only one unresolved intent per Order. `public.get_my_payment_intents` exposes only minimal status fields to the linked Buyer/Seller.
- `public.attach_payment_provider_reference` and `public.ingest_verified_payment_event` are service-role-only. The Edge/server adapter MUST verify the provider signature and provider-side transaction status before calling the normalized event RPC; this SQL RPC is not a cryptographic signature verifier. Raw webhook bodies are not stored; only a SHA-256 payload fingerprint and normalized fields are retained.
- Duplicate provider event IDs are idempotent and normalized-content conflicts fail closed. Unmatched events can be replayed after the provider reference is attached. Amount/currency mismatches, late captures, additional captures and invalid state transitions enter `requires_review`; they do not silently mark funds as received.
- Currency minor-unit exponents are explicit. Current Commerce Order prices have two decimal places, so only configured two-decimal currencies are enabled. JPY (0 decimals), KWD/BHD (3 decimals) remain disabled until the underlying price model supports their precision.
- Service-role-only journal posting validates equal debit/credit totals in one currency, protects posted journals/lines from mutation, supports idempotent posting and creates an immutable mirrored reversal entry.
- `public.expire_stale_payment_intents` is a service-role-only maintenance RPC; it must be invoked by a trusted scheduler/worker. No scheduler has been configured.

Focused tests: `tests/payment-finance-foundation.test.js` and `tests/payment-finance-foundation-postgres.test.sql`. The SQL suite passed locally against a disposable PostgreSQL 18.6 database. GitHub Actions CI #43672885634 passed on the exact implementation commit `afb09e4bb0374fbe1b74a97e503d8ac5f0faac5e`.

Still not implemented: provider-specific cryptographic adapter/checkout, gateway sandbox verification, payment reconciliation reports, refunds, chargebacks, seller payable calculations, payout/settlement, maker-checker approval UI, legal/accounting fund-flow decisions, full Supabase Auth/JWT/PostgREST/RLS integration, and browser/mobile end-to-end validation. No hosted Supabase migration, live payment, or Production change has been made.


## 10. Provider-neutral transaction reconciliation — 2026-11-15

Migration `20261115230000_payment_reconciliation_batch_queue.sql` adds a private, RLS-enabled reconciliation inbox for normalized provider transaction statements:

- A service-role-only ingestion RPC accepts a statement reference, report window, source-file SHA-256 and normalized transaction rows. The original report file/body is not stored.
- Statement references are idempotent; reuse with different content fails. Each provider transaction is matched to the internal transaction reference, amount, currency, normalized status and (when supplied) event ID.
- Exceptions are classified as unmatched provider transaction, duplicate transaction row, amount mismatch, currency mismatch, state mismatch or event mismatch.
- A service-role-only review RPC records a resolution/dismissal note and advances the batch to `reviewed` only when all exceptions have been reviewed. A batch with no exceptions is marked `matched`.
- Reconciliation is deliberately observational: it does not change payment capture state, create ledger entries, trigger refunds, or move money. The report window is retained as provenance metadata; this is not yet two-way completeness checking or bank-settlement matching. Missing internal captures, provider fees/net settlements and payout transfers remain outside this implementation. Provider-specific report parsing and trusted adapter integration remain unimplemented.

Focused SQL test: `tests/payment-reconciliation-postgres.test.sql`; static test: `tests/payment-reconciliation.test.js`. Local disposable PostgreSQL execution passed. GitHub Actions CI #43674068727 passed on exact implementation commit `803724a681015f9dcdd0f20b4609b341d679d0b1`.


## 11. Confirmed Bangladesh launch funds-flow policy — 2026-11-15

The business owner has confirmed the intended commercial flow:

**Buyer → NEXORA → Seller**

- NEXORA is intended to receive the Buyer's payment first; the platform, not the Seller directly, is the intended first recipient in the product's commercial flow.
- Seller payout is not eligible merely because the Buyer paid, the Order was accepted, a courier marked a parcel delivered, or a delivery charge was quoted.
- Seller payout becomes eligible only after successful delivery to the Buyer is confirmed. The current staged delivery design's Buyer receipt OTP is the intended primary confirmation signal; any exception/manual confirmation must be separately authorized, reasoned and audited.
- A disputed, failed, unverified or otherwise unresolved delivery/payment must remain on hold and must not be treated as payout-eligible.
- The system must calculate Seller payable from verified captured funds and the applicable agreed commission/charges, not from Order totals alone. The actual commission, taxes, fees, refunds, reserves and settlement amounts still require approved policy and contractual inputs.
- Partial-delivery settlement is not yet decided. Do not release the full Seller payable on a partial proof; keep the unresolved portion on hold until the complete-delivery and dispute outcome rules are explicitly defined.
- Refunds, chargebacks, payout approval and provider/bank settlement remain separate state machines with independent evidence and maker-checker controls.

**Important legal and implementation boundary:** this is the confirmed intended product flow, not a finding that NEXORA currently has legal authority to custody, pool or disburse customer funds. Before choosing a provider or enabling real money, obtain Bangladesh legal/accounting advice and provider approval on the permitted merchant-of-record/funds-flow model, licensing/authorization, safeguarded account structure, KYC/AML, consumer protection, tax/VAT, refund/chargeback obligations and seller contracts. If a licensed provider must hold or split funds, implement the approved provider-controlled flow rather than assuming NEXORA can hold funds itself.

No gateway, live collection, custody, payout or hosted database change is enabled by this decision.
## 12. Settlement backend implementation audit — 2026-11-15

A source audit was performed before adding payout SQL. It found two delivery/payment boundary issues that must be corrected in a new forward-only migration before Seller payout eligibility can safely be automated.

### 12.1 Buyer collection amount must include delivery charges

The current Commerce Order model adds delivery_charge into generated grand_total, while total_price remains the goods subtotal. The current public.create_payment_intent implementation snapshots commerce_orders.total_price, not grand_total. Therefore an Order with a non-zero delivery charge can currently create a payment intent that under-collects the intended Buyer total.

Required correction:
- Snapshot the complete Buyer collection amount from grand_total (or an equivalent immutable, explicitly componentized amount) and retain the goods subtotal and delivery charge as separate immutable components.
- Do not treat the delivery charge as Seller earnings. It must be allocated only under an approved carrier/partner settlement policy.
- Reconcile the exact captured amount against the same immutable snapshot before any journal or settlement is created.
- Add a regression test for a non-zero delivery charge, including idempotent intent reuse and mismatch review.

### 12.2 A delivered job status is not, by itself, proof of full Order quantity

The current delivery proof workflow records cumulative delivered quantity against the Commerce Order quantity. However, the receipt-verification function accepts both out_for_delivery and partially_delivered job states and transitions the job to delivered. The verified OTP challenge verified_at is then cleared after the guarded transition. A delivered label can therefore represent a Buyer-confirmed partial shipment unless the cumulative proof quantity is independently checked.

Required correction:
- Persist an immutable receipt-confirmation record for each successfully verified OTP, linked to the Buyer, Order, Delivery Job and the exact proof/quantity snapshot.
- Allow receipt confirmation for a partial drop without treating the whole Order as fully delivered; allow another confirmation for a later partial drop.
- Mark the Order delivery complete and open Seller settlement eligibility only when cumulative, validated proof quantity equals the Order quantity (within the existing numeric precision), the final receipt is confirmed, and no active dispute exists.
- Preserve the raw OTP only in the Buyer response; store a digest/confirmation metadata, never the code itself.
- A delivery dispute in open or under_review, a failed/returned shipment, quantity shortfall, missing proof, or payment/reconciliation exception must keep settlement on hold.

### 12.3 Proposed settlement gate and ledger lifecycle

The next database implementation should be an append-only, per-Order Seller settlement workflow with private RLS-enabled tables and service-only mutation RPCs. It must not be callable by Buyer/Seller/Porter browser roles to approve or move money.

Eligibility is a conjunction, not a single status:
1. Exactly one linked Delivery Job exists for the Order.
2. The payment intent is captured and the captured amount/currency exactly matches the immutable Buyer-total snapshot.
3. All ordered quantity is supported by validated delivery proof and final Buyer receipt confirmation.
4. No active delivery dispute, payment exception, unresolved reconciliation exception, refund/chargeback hold or other risk hold exists.
5. A current, explicitly approved commission/fee/tax policy exists for the Order currency and effective date.
6. Seller payout destination/KYC status has been verified under the selected licensed provider's requirements.

Recommended states: blocked, eligible, pending_approval, approved, submitted, paid, failed, on_hold, reversed. State changes must be locked, idempotent, audited and monotonic except explicit, separately journaled reversal/hold transitions. A provider payout callback is not sufficient by itself: verify it against the provider's authenticated transfer status and unique transfer reference.

The accounting flow must separate, by currency, at least: provider clearing/receivable, Seller payable, NEXORA commission revenue, delivery-partner payable, tax payable, refund/chargeback liabilities and payout cash/clearing. Journal posting must use the existing balanced, immutable post_finance_journal mechanism. No amount or percentage is to be hard-coded before the commercial fee schedule and carrier allocation policy are approved.

### 12.4 Current implementation status and safe boundary

- This audit and specification are documentation only. No settlement tables/RPCs, OTP behavior changes, payment-intent correction, payout adapter, or ledger automation have been deployed or committed.
- Existing migrations are immutable. The active chain currently ends at 20261115230000_payment_reconciliation_batch_queue.sql; the local Supabase CLI-generated timestamp observed during this work was earlier than that version. Do not hand-pick/edit a migration timestamp or modify an already-committed migration. Generate the next migration with the official CLI only when its generated version naturally sorts after the active chain.
- The Vercel Sandbox creation needed for isolated PostgreSQL work was rejected with HTTP 402 because the Hobby team's snapshot-storage usage limit was exceeded. No sandbox was created. No hosted Supabase project was used as a substitute.
- Implementation remains blocked until an isolated local test runner is available and a valid next migration version can be generated. After that, implement the Buyer-total correction and full-quantity receipt gate first, then settlement eligibility/ledger workflow, then run disposable PostgreSQL tests and Development CI.
