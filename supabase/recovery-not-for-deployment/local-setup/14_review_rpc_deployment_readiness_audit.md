# NEXORA Review RPC Deployment Readiness Audit

**Branch:** `nexora-development`  
**Reviewed files:** `12_local_review_rpc_prototype.sql`, `13_local_review_rpc_tests.sql`, and the local foundation fixture / review contract.  
**Scope:** Static code review plus the user's reported local PostgreSQL test result. No hosted Supabase access or database changes were performed.  
**Decision:** **NO-GO for hosted deployment. Local prototype logic test: PASS.**

## 1. Executive summary

The prototype has a sound overall shape for a narrow administrative workflow:

- Public RPC entry points are `SECURITY INVOKER`.
- Privileged implementation functions are in `private` and are `SECURITY DEFINER`.
- All four functions pin `search_path = ''` and use schema-qualified object references.
- Reviewer identity is derived from `auth.uid()`; no caller-supplied actor ID, role, permission, or admin code is accepted.
- Each core checks its exact permission, active Admin profile/staff record, request ownership against self-review, and pending-only state transition.
- Request rows are locked with `FOR UPDATE`.
- Profile/request changes and audit inserts occur in one function transaction.
- `PUBLIC` and `anon` execution are revoked; `authenticated` receives explicit execute grants.
- No direct table UPDATE grant is added to `authenticated`.

The local test output reported by the user confirms the listed local logic assertions passed and the test transaction rolled back. It does **not** demonstrate real Supabase JWT, PostgREST, RLS, hosted function-owner, or schema-exposure behavior.

## 2. Findings

### F-01 — Privileged function ownership is deployment-critical
**Severity: BLOCKER before hosted deployment**

Both `private._rpc_review_*_core` functions are `SECURITY DEFINER`. They execute with the privileges of the function owner, not the caller. The SQL file does not set an explicit owner; the role that creates the functions becomes their owner.

The local owner is the Termux superuser `u0_a552`, which has `rolsuper=true` and `rolbypassrls=true`. That local owner is not a safe proxy for the hosted Supabase owner.

**Required before deployment:** In an isolated Supabase staging project, inspect `proowner`, role attributes, table ownership, and RLS bypass behavior for both cores and the permission helper. Confirm that the chosen owner is a trusted migration/administrative role and that the function's elevated access is intentional. Do not copy or assign the local `u0_a552` owner.

### F-02 — Keep `private` outside PostgREST exposed schemas
**Severity: BLOCKER before hosted deployment**

The public wrappers call private core functions. The prototype grants `USAGE` on schema `private` and `EXECUTE` on the two private cores to `authenticated`, which is needed for the invoker wrapper to call them under the caller's privileges.

If `private` is added to PostgREST's exposed schemas, the private SECURITY DEFINER functions may become directly callable as API RPC endpoints by authenticated users. Their internal permission checks still apply, but exposing implementation functions is unnecessary and violates the intended boundary.

**Required before deployment:** Verify the actual Supabase Data API / PostgREST Exposed Schemas setting excludes `private`. Expose only the intended public wrappers. Also confirm no other API routing configuration exposes the private schema.

### F-03 — Local test harness does not test real role enforcement
**Severity: BLOCKER for security sign-off; not a failure of the local logic test**

The test script runs as the local superuser. It changes the local `request.jwt.claim.sub` setting to exercise `auth.uid()`, but the SQL session remains superuser. Therefore table RLS and ordinary-role ACL enforcement are bypassed during the functional calls.

The catalog checks do verify function ACL metadata and table UPDATE privileges, but do not prove that a real `authenticated` PostgREST request succeeds or that an ordinary user is denied by actual database privilege/RLS checks.

**Required before deployment:** Repeat the test in an isolated Supabase stack/project using real Auth-issued JWTs and requests made as the `authenticated` role through PostgREST. Include Buyer, Seller, Porter, unauthorized Admin, authorized reviewer, and anonymous cases.

### F-04 — Test coverage is useful but incomplete versus the written contract
**Severity: HIGH before production readiness**

The current test script covers unauthenticated calls, ordinary Buyer denial, an authorized MD permission grant, Buyer-to-Seller approval, rejection, self-review, repeat review, profile-name approval/rejection, audit writes, NULL decision, function security mode/ACL, and absence of direct UPDATE grants.

It does not yet cover all cases listed in `10_review_rpc_contract.md`, including:
- inactive Admin;
- active Admin without the exact permission;
- Seller and Porter callers;
- missing request ID;
- overlength admin note;
- invalid or cancelled state transitions;
- concurrent review attempts;
- forced audit insert failure and proof the whole operation rolls back;
- authenticated direct UPDATE attempts against the real tables;
- forged reviewer/status fields on owner INSERT;
- verification of private schema exposure and hosted function ownership.

**Required:** Add these cases to a staging integration test plan. Concurrency and rollback-on-audit-failure should be explicit tests, not assumptions.

### F-05 — Buyer-to-Seller promotion must remain separate from public business listing approval
**Severity: PRODUCT / authorization boundary**

The role-review core changes the profile role from Buyer to Seller and sets the wholesale category fields. It does not create or approve a business profile or publish products, which is consistent with the current rule that a Seller may register and complete details but the business/listings require Admin approval before public visibility.

**Required:** Preserve this separation in later business-profile and product-listing workflows. A successful Buyer-to-Seller role request must not implicitly activate a public seller storefront or publish listings.

### F-06 — Security construction is aligned with current Supabase guidance, subject to staging validation
**Severity: PASS WITH CONDITIONS**

The inspected code pins empty search paths, qualifies object names, uses invoker wrappers, restricts function execution, and performs narrow permission checks inside the privileged core. These controls align with current Supabase database-function security guidance. They do not replace owner, JWT, schema exposure, and real-role verification.

## 3. Function-by-function static review

| Area | Result | Notes |
|---|---|---|
| Public wrapper security | PASS | Both wrappers are SECURITY INVOKER with empty search_path. |
| Private core security | CONDITIONAL | SECURITY DEFINER is narrowly scoped, but hosted owner must be verified. |
| Actor identity | PASS | Uses auth.uid(); actor ID is not a parameter. |
| Permission gate | PASS WITH CONDITIONS | Exact permission helper is called; verify helper owner and actual hosted permission catalogue. |
| Active Admin check | PASS | Requires active staff and active Admin profile. |
| Self-review prevention | PASS | Request owner cannot review their own request. |
| State transition | PASS | Locks request row and accepts only pending requests. |
| Buyer-to-Seller update | PASS WITH PRODUCT BOUNDARY | Requires an active Buyer and updates wholesale role fields. |
| Profile-name update | PASS | Validates trimmed name length and changes only full_name. |
| Audit | PASS BY INSPECTION | Audit insert is in the same transaction; forced audit-failure rollback still needs a test. |
| Direct table grants | PASS BY LOCAL CATALOG | No authenticated UPDATE grant is added by the prototype. |
| PostgREST exposure | NOT VERIFIED | Must confirm `private` is not exposed in hosted settings. |
| Hosted JWT/RLS behavior | NOT TESTED | Local superuser tests cannot certify this. |

## 4. Required staging verification sequence

1. Create/use an isolated Supabase staging project only after the project owner explicitly authorizes it; do not use production.
2. Confirm the hosted schema and function inventory match the intended foundation.
3. Verify `private` is not an exposed Data API schema.
4. Inspect owner, `SECURITY DEFINER`, `search_path`, and EXECUTE ACL for the two cores, the two public wrappers, and `private.has_nexora_permission(text)`.
5. Obtain real Auth sessions for test Buyer, Seller, Porter, permitted Admin, unpermitted Admin, and anonymous caller.
6. Call only the public wrapper endpoints using those sessions.
7. Confirm denied users cannot review; approved reviewer can review only requests covered by their permission.
8. Attempt direct table UPDATE and forged INSERT fields as authenticated; expect denial.
9. Test concurrent review and audit-insert failure rollback.
10. Run Supabase database advisors and inspect every finding before considering a deployable migration.
11. Keep migration-history reconciliation as a separate blocker; these recovery files must not be copied into `supabase/migrations/` as-is.

## 5. Explicit non-actions

- No SQL was run by this audit.
- No files in `supabase/migrations/` were created or modified.
- No grants, policies, function owners, RLS flags, or hosted database settings were changed.
- No Live Supabase, production deployment, DNS, or `main` branch was accessed or changed.
- The reviewed SQL remains under `supabase/recovery-not-for-deployment/local-setup/`.

## 6. Final status

**Local review RPC prototype:** PASS for the user's reported local logic/catalog test.  
**Static code design:** Promising, with explicit deployment conditions.  
**Hosted Supabase deployment:** **NO-GO until F-01, F-02, and F-03 are verified in isolated staging and the missing tests in F-04 are completed.**
