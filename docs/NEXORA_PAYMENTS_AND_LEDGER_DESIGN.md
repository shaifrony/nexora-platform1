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

Focused tests: `tests/payment-finance-foundation.test.js` and `tests/payment-finance-foundation-postgres.test.sql`. The SQL suite passed locally against a disposable PostgreSQL 18.6 database. CI integration has been added but must pass on the exact pushed commit before this milestone is marked CI-verified.

Still not implemented: provider-specific cryptographic adapter/checkout, gateway sandbox verification, payment reconciliation reports, refunds, chargebacks, seller payable calculations, payout/settlement, maker-checker approval UI, legal/accounting fund-flow decisions, full Supabase Auth/JWT/PostgREST/RLS integration, and browser/mobile end-to-end validation. No hosted Supabase migration, live payment, or Production change has been made.
