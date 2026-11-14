# NEXORA Foundation Review RPC — Local-Only Contract

**Status:** Design and test contract only. No SQL implementation or database change in this commit.  
**Branch:** `nexora-development`  
**Scope:** Local foundation fixture only; not a deployable migration.

## 1. Verified baseline

The local fixture defines:
- `role_requests`: owner-submitted Buyer-to-Seller request; reviewer permission key `users.role_requests.review`.
- `profile_change_requests`: owner-submitted full-name change request; reviewer permission key `users.profile_changes.review`.
- Both reviewer UPDATE policies use the permission helper in both `USING` and `WITH CHECK`.
- Authenticated has SELECT and INSERT on both request tables, but no UPDATE grant.
- Authenticated has SELECT on profiles but no UPDATE grant.
- `admin_audit_logs` has actor, action, target, reason, details and timestamp fields; ordinary authenticated clients have no INSERT/UPDATE/DELETE grant.
- Both request tables contain `status`, `admin_note`, `reviewed_by`, `reviewed_at`, `created_at`, and `updated_at`.
- The local role/table owner observed in the catalog is `u0_a552`; this is not evidence of hosted Supabase ownership.

The reviewer UPDATE policies are not sufficient by themselves: PostgreSQL table privileges are checked independently. The authenticated client currently cannot perform direct UPDATE.

## 2. RPC interface proposal

Use two narrowly scoped functions in `private`, subject to later Supabase/PostgREST exposure verification:

### A. `private.review_role_request(p_request_id uuid, p_decision text, p_admin_note text DEFAULT NULL)`

Allowed decisions: `approved`, `rejected`.

On approval:
- lock the request row;
- require current status `pending`;
- require the actor to be an active Admin with `users.role_requests.review` (or Director override through the approved helper);
- reject self-review (`request.user_id <> auth.uid()`);
- require target profile still exists and is an active Buyer;
- update only the request's review-controlled fields;
- change the target profile role from `buyer` to `seller` and set wholesale category fields consistently;
- write one audit record in the same transaction.

On rejection:
- do not change the target profile role or categories;
- update only status/reviewer/time/note and write an audit record.

### B. `private.review_profile_change_request(p_request_id uuid, p_decision text, p_admin_note text DEFAULT NULL)`

Allowed decisions: `approved`, `rejected`.

On approval:
- lock the request row;
- require current status `pending`;
- require the actor to be an active Admin with `users.profile_changes.review` (or Director override through the approved helper);
- reject self-review;
- validate requested name is trimmed and 1–150 characters;
- update only `profiles.full_name` for the request owner;
- update only review-controlled request fields;
- write one audit record in the same transaction.

On rejection:
- leave `profiles.full_name` unchanged;
- update only review-controlled request fields and write an audit record.

### Shared security requirements

- Actor identity is always `auth.uid()`; never accept actor ID, admin code, permission, role or account status from caller parameters.
- Require a non-null authenticated UID.
- Require active `profiles.role='admin'` and `profiles.account_status='active'` through the existing permission helper, not caller claims or `raw_user_meta_data`.
- Use `SECURITY DEFINER` only if required for the narrow atomic workflow; pin `SET search_path = ''`; fully qualify every relation/function; no dynamic SQL.
- Function owner must be a controlled trusted role in hosted Supabase, not an arbitrary local shell role. Verify owner and RLS bypass implications before any real deployment.
- Revoke EXECUTE from PUBLIC and anon; grant only to authenticated if the function is intentionally exposed as an RPC. Keep `private` out of PostgREST exposed schemas unless a documented RPC routing design requires otherwise.
- Do not grant table UPDATE to authenticated.
- Bound `p_admin_note` (maximum 1000 characters); normalize blank to NULL.
- Reject unknown decisions, already-reviewed requests, missing rows, self-review, unauthorized actors, and invalid state transitions with explicit SQLSTATE errors.
- Update request and profile and append audit log atomically; any failure rolls back all changes.
- Audit details must not copy private contact data or unnecessary identity attributes.

## 3. Audit action contract

Proposed action keys:
- `users.role_request.approved`
- `users.role_request.rejected`
- `users.profile_change.approved`
- `users.profile_change.rejected`

Target types:
- `role_request`
- `profile_change_request`

Audit record:
- `actor_user_id = auth.uid()`
- `actor_admin_code` derived from the active Admin staff row, never caller input
- `target_id` = request UUID text
- `reason` = bounded admin note
- `details` = minimal structured decision and old/new state only

## 4. Required negative and positive tests

| Test | Expected |
|---|---|
| no authenticated UID | reject |
| Buyer/Seller/Porter calls review RPC | reject |
| inactive Admin calls | reject |
| Admin without exact permission calls | reject |
| reviewer tries own request | reject |
| request ID does not exist | reject |
| decision other than approved/rejected | reject |
| request already approved/rejected/cancelled | reject |
| role request targets non-Buyer profile | reject |
| role request requests anything other than Seller | reject |
| approval of valid Buyer→Seller request | role becomes Seller; wholesale-only categories set; request approved |
| rejection of valid role request | profile role unchanged; request rejected |
| valid profile-name approval | profile full_name changes to requested value; request approved |
| profile-name rejection | profile full_name unchanged; request rejected |
| note longer than 1000 chars | reject |
| concurrent review of same request | exactly one succeeds; second sees non-pending state and rejects |
| any audit insert failure | entire workflow rolls back |
| authenticated direct UPDATE on either request table | denied |
| authenticated direct UPDATE on profiles | denied |
| authenticated direct INSERT with forged reviewer/status fields | denied by INSERT policy |
| anon executes either RPC | denied |
| PUBLIC inherited execute | denied |

## 5. Preconditions still required before writing executable SQL

1. Receive and inspect the complete catalog diagnostic output for both UPDATE policies, including `qual`, `with_check`, and privilege booleans.
2. Confirm function owner and whether the local `u0_a552` role has BYPASSRLS/superuser attributes. Do not transfer local ownership as a proxy for Supabase.
3. Inspect the full current `admin_audit_logs` policies and grants.
4. Confirm whether MD/department-head permission assignments should allow these two review workflows; do not infer permission from title.
5. Confirm whether a role request approval should automatically change the profile role to Seller. This follows the stated Buyer→Seller transition but must be consistent with any separate business-profile approval gate.
6. Confirm whether rejected requests can be resubmitted as new requests and whether only one pending request per user is allowed.

## 6. Explicit non-actions

- No function was created or replaced.
- No grants, policies, ownership, RLS or FORCE RLS settings were changed.
- No SQL was executed.
- No hosted Supabase, migration history, production deployment, or `main` branch was accessed or changed.
