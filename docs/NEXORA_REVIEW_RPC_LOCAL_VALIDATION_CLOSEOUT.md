# NEXORA Review RPC Local Validation Closeout

Updated: 2026-11-13
Branch: `nexora-development`

## Decision

The repeated local Review RPC logic-test cycle is closed. Development should move forward to the next product implementation workstream instead of adding more overlapping local test scripts.

This closeout does **not** approve production deployment and does not claim hosted Supabase security validation.

## Verified local evidence

The user reported successful execution of:

- Foundation smoke tests (local logical checks).
- Foundation read-only catalog audit and deep diagnostic.
- Review RPC prototype creation.
- Review RPC test suite: authorization, Buyer-to-Seller approval, rejection, self-review prevention, repeat-review prevention, profile-name workflow, audit writes, NULL decision validation and narrow ACL metadata.
- Extended Review RPC tests: inactive Admin, missing permission, Seller/Porter denial, missing request ID, invalid decision, cancelled request, overlength note, non-Buyer target and audit-failure rollback.

The extended test output ended with:

```
NOTICE: PASS: inactive Admin, missing permission, Seller/Porter denial, missing ID, invalid decision, cancelled request, overlength note, non-Buyer target, and audit-failure atomic rollback
=== LOCAL EXTENDED REVIEW RPC TESTS PASSED; ALL TEST DATA AND TEST DDL ROLLED BACK ===
```

## Explicit limitations

- Local psql execution uses a local superuser that bypasses real RLS and table/function ACL enforcement during functional execution.
- The local fixture is a reconstructed test environment, not an original production schema.
- No hosted Supabase Auth-issued JWT, PostgREST, RLS, private-schema exposure, MFA/AAL2 or hosted function-owner validation has been completed.
- A two-session concurrency runbook and fixture exist, but the user has not reported running the two-session concurrency scenario. Concurrency is therefore **not verified**.
- Hosted migration history mismatch remains unresolved. Do not apply this prototype or recovery SQL to hosted Supabase.

## Work policy from this point

1. Do not create more repetitive local Review RPC logic-test scripts unless implementation changes materially.
2. Do not block ordinary product development on optional local test repetition.
3. Keep the concurrency scenario marked pending; run it only as a focused check before considering the Review RPC for hosted deployment.
4. Keep hosted Supabase deployment blocked until migration history is reconciled and a disposable hosted/staging environment is available for JWT/PostgREST/RLS checks.
5. Continue implementation only on `nexora-development`.
6. Do not modify `main`, hosted Supabase, production deployment, DNS or paid services without explicit approval.

## Next implementation workstream

Proceed with the **wholesale-only Buyer/Seller/Porter onboarding and Seller business/product foundation**, reusing the existing repository implementation where possible.

Before writing schema changes, inspect the current staged migrations and existing frontend/backend code to avoid duplicate tables, conflicting policies or role drift. Preserve these product rules:

- Public homepage registration exposes exactly Buyer, Seller and Porter; never Admin.
- Buyer can register and use the account without Admin approval.
- Seller can register and complete business details without prior approval, but public storefront/listings require Admin approval.
- Porter can register but remains pending until Admin approval before Porter work access.
- Users cannot self-change role, account status, verification status or protected fields.
- NEXORA is wholesale-only; no retail listings or retail order flow.
- One Business Profile and one sales-center address per business; multiple products belong to that sales center.
- Each product has its own Product ID and stable URL.
- Initial product form fields: Product Name, Category, Product Images, Product Description, Origin, Specifications & Quality, Price & Currency. Do not add MOQ, supply capacity or packaging/delivery fields to this initial form.
- Buyer Demand remains public while Buyer identity/contact details stay private; include the required-by date.

No migration is ready for hosted deployment merely because it is staged in GitHub.
