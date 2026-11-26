# NEXORA Local Foundation Security Audit — Findings & Remediation Plan

**Status:** Review plan only. No SQL changes applied.  
**Scope:** Local Android PostgreSQL fixture in `nexora_test` and its catalog output.  
**Not a Supabase platform security certification.** Do not execute this document as SQL.

## 1. Evidence received

The user ran the read-only catalog audit and supplied these results:

- RLS is enabled on all nine foundation tables: 0 disabled.
- FORCE RLS is disabled on all nine tables.
- All nine tables are owned by local role `u0_a552`.
- Two SECURITY DEFINER functions are in `public`: `is_nexora_admin()` and `handle_new_user()`.
- The five inspected functions have pinned `search_path=""`.
- `anon` cannot execute any of the five inspected functions.
- `authenticated` can execute `private.has_nexora_permission(text)`, `private.is_nexora_super_admin()`, and `public.is_nexora_admin()`.
- `authenticated` cannot execute `private.protect_profile_updates()` or `public.handle_new_user()`.
- Two UPDATE policies exist without an authenticated UPDATE table grant. The supplied visible row confirms `role_requests_reviewer_update`; the audit summary also reports a second such policy, expected to be the profile-change reviewer policy. Confirm exact row before any remediation.

## 2. Findings and interpretation

### F-01 — RLS enabled, FORCE RLS disabled (9 tables)
**Severity:** Informational / platform-architecture review, not an automatic defect.

RLS is enabled on all nine tables. The tables are owned by the local Termux role `u0_a552`; therefore this local result does not predict hosted Supabase ownership or service-role behavior. Table owners and roles with BYPASSRLS can bypass RLS unless FORCE RLS applies, but forcing RLS indiscriminately can break trusted maintenance, migrations, triggers, and backend workflows.

**Decision:** Do not enable FORCE RLS as a blanket fix. On an isolated Supabase environment, inspect actual table owners, service-role use, function owners, and every backend workflow. Keep a deliberate owner/bypass model and test JWT roles.

### F-02 — SECURITY DEFINER functions in public (2)
**Severity:** Medium review; no confirmed anonymous exposure in supplied output.

- `public.is_nexora_admin()`: SECURITY DEFINER, pinned empty search_path, anon execute false, authenticated execute true.
- `public.handle_new_user()`: SECURITY DEFINER trigger function, pinned empty search_path, anon/authenticated execute false.

The function ACLs shown do not indicate anonymous execution. A trigger function does not need client EXECUTE permission. The public helper can be called by authenticated users and returns a boolean; determine whether that disclosure is acceptable. Prefer keeping authorization helpers in a non-exposed schema and exposing only narrow RPCs when required. Do not move or alter the Auth trigger function without validating Supabase's trigger binding and migration behavior in an isolated Supabase stack.

**Decision:** No immediate SQL change. Keep EXECUTE revoked from PUBLIC/anon. Review PostgREST exposed schemas and function grants in actual Supabase.

### F-03 — Reviewer UPDATE policies without UPDATE table grant (2)
**Severity:** Functional design gap; direct grant is not the recommended fix.

The local fixture defines reviewer UPDATE policies for `role_requests` and `profile_change_requests`, but authenticated lacks UPDATE table privilege. Therefore ordinary authenticated reviewer clients cannot perform direct UPDATE even when policy conditions match.

Simply granting UPDATE is unsafe: current policies use the same broad permission predicate for USING and WITH CHECK, and do not restrict which columns a reviewer can alter. A reviewer with the permission could potentially alter ownership/request metadata or other protected review fields if table-level UPDATE were granted.

**Decision:** Do NOT add table-level UPDATE grants. Implement narrow SECURITY DEFINER RPCs in the private/non-exposed schema or a controlled exposed API schema, with:
- authenticated actor derived only from `auth.uid()`;
- permission check for the exact review capability;
- locked target row (`SELECT ... FOR UPDATE`);
- state transition only from `pending` to `approved` or `rejected` (and any explicitly approved cancellation path);
- immutable `user_id`, requested role/name, creation time;
- reviewer, review timestamp and bounded admin note set by server;
- no self-approval if policy requires separation of duties;
- audit-log insert in the same transaction;
- no caller-supplied actor ID or privilege flags;
- explicit EXECUTE grants only to authenticated and revoked from PUBLIC/anon;
- tests for unauthorized actor, wrong department, repeated review, invalid transition, tampering and valid review.

The exact business rule for whether MD/Director can review each workflow should follow the approved governance charter and permission catalogue.

## 3. Other controls to verify before declaring Foundation secure

1. Confirm exact names and expressions of both UPDATE policies.
2. Check whether `authenticated` can INSERT malformed requests by supplying reviewer fields, unexpected status, or oversized admin notes. Existing WITH CHECK expressions should be tested against every column.
3. Check profile-change request multiplicity: whether multiple pending requests per user are allowed; add a partial unique index only after the product decision.
4. Ensure `admin_audit_logs` has no client INSERT/UPDATE/DELETE grant and only trusted server-side workflow writes audit events.
5. Confirm `admin_permission_grants` and `admin_permission_catalog` cannot be modified by authenticated clients.
6. Test SECURITY DEFINER owner and search_path behavior using actual Supabase roles, not only local compatibility stubs.
7. Validate the Auth trigger with real Supabase Auth signup and OAuth in an isolated local Supabase stack.
8. Verify Buyer identity cannot leak through any public view or demand query. The current nine-table foundation audit does not test Marketplace projections.
9. Confirm the local test harness simulates auth.uid() accurately enough for the specific SQL assertions; it is not a JWT/RLS integration test.

## 4. Safe next implementation sequence

1. Preserve the current local fixture as the baseline; do not rerun it on top of existing tables.
2. Add a separate **local-only** RPC prototype file under `supabase/recovery-not-for-deployment/local-setup/`; never put it in `supabase/migrations/`.
3. Add transactional SQL tests using controlled local auth.uid() context for positive and negative review cases.
4. Re-run the smoke tests and audit after any local prototype change.
5. Later validate on an isolated Supabase local stack with real Auth/JWT/PostgREST.
6. Only after migration-history reconciliation and explicit approval consider any deployable migration.

## 5. Explicit non-actions

- No RLS policy, grant, table owner, FORCE RLS setting, function, trigger, or application data was changed.
- No hosted Supabase or production system was accessed or changed.
- This plan is not deployable SQL and does not resolve migration-history divergence.
