# NEXORA Review RPC — Concurrency and Hosted Integration Test Plan

**Branch:** `nexora-development`  
**Status:** Test plan only; no SQL or hosted configuration changes.  
**Prerequisite:** Local script `15_local_review_rpc_extended_tests.sql` passes.

## 1. Concurrency test — isolated local database only

The current local scripts wrap fixtures and test data in transactions and roll them back. A genuine two-session race therefore needs a separately prepared, disposable local test database or explicitly committed test fixture rows. Do not remove the rollback from the existing test scripts.

### Required scenario

1. Prepare one active Buyer and one pending Buyer-to-Seller request in a disposable local database.
2. Prepare one active reviewer with the exact `users.role_requests.review` permission.
3. Open two independent psql sessions, A and B, connected to that same disposable database.
4. In session A, set the reviewer claim and call the public wrapper for the pending request, but keep the surrounding transaction open after the call.
5. In session B, set the same reviewer claim and call the same wrapper for the same request.
6. Confirm session B waits for the row lock while A is uncommitted.
7. Commit session A.
8. Confirm session B resumes and fails with SQLSTATE `55000` because the request is no longer pending.
9. Verify exactly one final decision and exactly one matching audit row exist.

Expected result: exactly one review succeeds. The second review must not overwrite the first decision or create a second audit event.

### Cleanup

Use only disposable local data. Remove the test identities and rows after verifying results. Do not use production or a live Supabase project for this concurrency exercise.

## 2. Hosted Supabase staging integration — separate authorization required

This is not covered by local PostgreSQL. It requires an isolated Supabase staging project and explicit project-owner authorization.

Required test identities:
- anonymous caller;
- Buyer;
- Seller;
- Porter;
- active Admin with the exact review permission;
- active Admin without the exact review permission;
- inactive Admin with a stale permission grant.

Required checks:
- Real Auth-issued JWTs, not manually-set local claim GUCs.
- Call only `public.rpc_review_role_request` and `public.rpc_review_profile_change_request` through PostgREST.
- Anonymous and non-reviewer roles are denied.
- The authorized reviewer can review only the workflow covered by their permission.
- Direct authenticated UPDATE on profiles and request tables is denied.
- Forged owner INSERT values for `status`, `reviewed_by`, `reviewed_at`, and `admin_note` are rejected by policy.
- Confirm `private` is absent from Supabase Data API Exposed Schemas.
- Inspect hosted function owners, `SECURITY DEFINER`, pinned empty search paths, and function ACLs.
- Verify audit insert failure rolls back the request and profile changes.
- Verify concurrent review behavior.

## 3. Safety boundary

- Never point these local-only scripts at hosted Supabase.
- Do not copy recovery scripts into `supabase/migrations/`.
- Do not change migration history or production.
- A passing local test suite is not hosted deployment approval.
