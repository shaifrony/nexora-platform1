# NEXORA-TEST Foundation Baseline — Reviewed Design Specification

**Status:** DESIGN BASELINE v1 — NOT SQL / NOT DEPLOYABLE / NOT APPLIED  
**Date:** 2026-11-14  
**Target:** Supabase project `NEXORA-TEST` only  
**Repository branch:** `nexora-development`  
**Purpose:** Define the minimum identity, account lifecycle, Admin authorization and audit foundation required before replaying the 38 active feature migrations.

> This is a new Test-only design specification. It is not recovered historical SQL, is not a migration, and must not be copied into `supabase/migrations/` as-is. No schema or data has been changed by writing this document. The prior `06_local_foundation_baseline_fixture.sql` is a PostgreSQL compatibility fixture for local testing only; it is not a hosted Supabase baseline.

## 0. Current product decisions override older design notes

The following are the current authoritative decisions and supersede conflicting statements in the older `05_foundation_design_proposal.md`:

1. Marketplace is a **single unified marketplace**. Do not create Buyer/Seller Wholesale/Retail category fields or category-based visibility. Everyone sees the same approved marketplace listings; sellers set their own prices and quantities. Wholesale/Retail delivery service modes, if used by logistics, are a separate transport concept and do not create marketplace user categories.
2. Buyer, Seller, Porter and Admin are the four internal account roles. Public signup permits Buyer, Seller and Porter only; Admin is provisioned through protected governance.
3. Buyer can use an account after valid registration. Seller can create their Business Profile and product listings, but public visibility requires Admin approval. Porter signup creates a pending account and requires Admin approval before Porter workspace/use.
4. Buyer Demand cards are public, but Buyer identity, profile ID and contact details remain private. Required-by date is part of the Demand data contract.
5. No user can self-change role, account status, verification state, Admin membership, approval metadata or other protected fields.
6. No user may browse another user's full/private profile. Public identity is a narrowly scoped projection only.
7. Calling is paused, not deleted. Keep existing call tables/functions/migrations intact; do not extend or test Calling in this baseline.
8. Private Chat, Message, File/Image Sharing and Conversation Privacy remain separate feature migrations and are tested only with synthetic identities/data.

The older proposal's Wholesale-only Buyer/Seller category requirements and the local fixture's corresponding category check are **superseded**. Do not implement those fields in the new Test baseline.

## 1. Baseline boundary and schema layout

### 1.1 Platform-owned prerequisites (must already exist in a real Supabase project)

- Supabase-managed `auth.users`, `auth.uid()`, `auth.jwt()`, roles and session claims.
- Supabase Storage schema/API and Realtime publication managed by Supabase.
- `pgcrypto`/UUID support required by the feature migrations.
- A real Auth trigger binding for profile provisioning, created only after the function contract is tested.

Do not recreate or alter Supabase-managed Auth/Storage internals. Do not fake AAL2, PostgREST, Storage API or Realtime behavior in plain PostgreSQL and call it a platform test.

### 1.2 NEXORA application schemas

- `public`: only application tables deliberately exposed through the Data API. Every table must have RLS enabled before any Data API grant.
- `private`: authorization helpers and internal functions; not exposed through PostgREST. Grant schema usage/execute only to the minimum required database roles.
- No user data, existing Live IDs, private messages, call records, Storage objects, credentials or production configuration are copied.

## 2. Minimum foundation objects

| Object | Purpose | Essential contract |
|---|---|---|
| `public.profiles` | One app profile per Auth identity | `id uuid PK -> auth.users(id)`; `full_name`; `role`; `account_status`; `created_at`; `updated_at`. No Buyer/Seller market-category columns. |
| `public.role_requests` | Controlled Buyer-to-Seller request if retained by current UI | `user_id`; `requested_role='seller'`; pending/review lifecycle; reviewer and review timestamps. Never Admin/Porter self-escalation. |
| `public.profile_change_requests` | Request legal/display name change | `user_id`; requested name; status; admin note; reviewer; review timestamps. No direct user update to protected profile fields. |
| `public.admin_departments` | Organization department catalogue | Stable `department_key`, display name, description, assignable state. Seed only current approved departments. |
| `public.admin_staff` | Protected appointment record for Admin profile | `user_id` PK/FK to profiles; unique `admin_code`; position, department, active state, reporting relationship, creator and timestamps. |
| `public.admin_permission_catalog` | Permission definitions | Unique `permission_key`, department scope, description, sensitivity/protected flag, active state. |
| `public.admin_permission_grants` | Least-privilege assignment | Admin user, permission, grant/deny state, granting actor, timestamp; no self-grant of protected powers. |
| `public.admin_audit_logs` | Append-only governance/security audit | Actor, action key, target type/id, reason, safe JSON details, timestamp. No direct update/delete by application roles. |
| `public.porter_account_reviews` | Porter registration review gate | One row per Porter profile; pending/approved/rejected/suspended; reviewer, reviewed time and note. |
| `public.public_identities` (or equivalent safe projection) | Limited display identity only if required by UI | Approved display name and optional approved avatar reference only. Never a full profile or Buyer-demand join key. |

The exact types and additional fields must be reconciled against current frontend and feature SQL before generating the hosted baseline. Do not add optional phone/address/verification columns merely because they may be useful later.

## 3. Profile and account lifecycle

### 3.1 Roles

- Allowed internal `profiles.role`: `buyer`, `seller`, `porter`, `admin`.
- Public signup accepts exactly `buyer`, `seller`, `porter`.
- Admin is never accepted from `raw_user_meta_data`, `raw_app_meta_data`, a public RPC argument or a client-side profile update.
- Unknown role values are rejected, not normalized to elevated roles.
- OAuth/social signups default to Buyer unless a separately reviewed signup flow explicitly supports another public role.

### 3.2 Account status

Proposed constrained values: `active`, `pending`, `suspended`, `rejected`, `disabled`.

| Role | Signup status | Access gate |
|---|---|---|
| Buyer | active | Normal authenticated Buyer workspace |
| Seller | active | May complete private Business Profile/listing drafts; public marketplace visibility only after Admin approval |
| Porter | pending | No Porter workspace or delivery work until Admin approval |
| Admin | no public signup | Protected appointment + active staff record + required AAL2 + explicit permission |

A Seller's active account does not mean their business or listings are approved. A Porter account approval does not automatically approve a provider or vehicle; those remain separate operational gates.

### 3.3 Profile fields and direct writes

- `id` is always the Auth user UUID, never a client-selected identity.
- Users cannot update `role`, `account_status`, verification, approval, Admin membership, review metadata or protected profile attributes.
- Direct profile updates should be denied by default. If a user-editable field is required, grant only that column and enforce both RLS `USING` and `WITH CHECK`; never grant whole-row update casually.
- Name changes use `profile_change_requests` and an authorized review action.
- No assumption that `raw_user_meta_data` is trustworthy for authorization. It is user-editable; use it only as validated signup input. Authorization is based on database-controlled profile/staff/permission records.

## 4. Admin governance and authorization contract

Organization hierarchy: **Director → Managing Director → Department Heads → Department Officers**.

Initial operational departments: Marketing; Transport & Logistics; Accounts & Finance.

- Director is the sole authority for organization structure, protected permission catalogue, appointment/removal of MD and Department Heads, and core governance/security changes.
- MD coordinates day-to-day operations only within explicit permissions.
- Department Heads and Officers are constrained by department scope and explicit grants.
- Job title or department membership alone never grants access.
- Cross-department permissions require explicit Director authorization and audit.
- Marketing cannot approve its own provider/vehicle applications. Transport can review providers/vehicles and dispatch eligible jobs but cannot alter finance ledger or approve its own invoices. Accounts handles reconciliation and settlement approval separation.
- Director bootstrap is an out-of-band, controlled process. No fixed UUID, email allowlist, signup metadata or public RPC may silently create a Director.

### Required helper functions

| Function | Schema | Intended result |
|---|---|---|
| `is_nexora_admin()` | public (compatibility name required by existing migrations) | True only for active, valid Admin staff membership; no user-controlled claims. |
| `has_nexora_permission(text)` | private | True only for active Admin + AAL2 + explicit active grant and valid department/governance scope. |
| `is_nexora_super_admin()` | private | True only for the Director's protected appointment; no generic role/metadata shortcut. |
| `handle_new_user()` | public (existing trigger name compatibility) | Validates public signup role, inserts the profile, and creates pending Porter review where applicable. Not callable as a client RPC. |

Function security rules:
- Use `SECURITY DEFINER` only where required, with fully qualified object references and `SET search_path = ''`.
- Revoke default `EXECUTE` from `PUBLIC`, `anon` and `authenticated` on trigger-only or internal definer functions.
- Keep internal authorization logic in the unexposed `private` schema.
- Expose only narrow invoker wrappers when a frontend RPC is genuinely required; each wrapper delegates to a private function with its own `auth.uid()`, AAL2, permission and input checks.
- Never authorize from user-editable JWT metadata. AAL2 is only an MFA assurance check, not a substitute for a staff record or permission grant.

## 5. RLS, grants and privacy matrix

| Object | anon | authenticated user | Admin |
|---|---|---|---|
| `profiles` | no access | own row only, and only safe columns/approved path | permission-scoped; not blanket full-profile browsing |
| `role_requests` | no access | own request read/submit; cannot set review fields | designated review permission |
| `profile_change_requests` | no access | own request read/submit; cannot set review fields | designated profile-review permission |
| `admin_staff` | no access | no general roster access | governance/staff permission only |
| `admin_departments` | no access | no access unless a specific UI need is approved | relevant governance permission |
| `admin_permission_catalog` | no access | no access | read/write protected by Director governance |
| `admin_permission_grants` | no access | no access | read/write only under protected grant rules |
| `admin_audit_logs` | no access | no access | permission-scoped read; insert through audited functions; no update/delete |
| `porter_account_reviews` | no access | Porter may read own review state only if needed | logistics review permission |
| public identity projection | no access unless a specific public use is approved | only approved minimal display fields | permission-scoped |

RLS requirements:
- RLS enabled on every table in exposed `public`.
- Start with `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`; add only explicit grants required by frontend/RPC.
- An UPDATE policy needs a SELECT policy and both `USING` and `WITH CHECK`; column grants must not expose protected columns.
- Views must use `security_invoker = true` on PostgreSQL 15+ or be inaccessible to client roles and exposed through a protected alternative.
- No public view or RPC may expose Buyer identity/contact through Buyer Demand.
- No broad Admin policy that grants every Admin access to all private profiles, chat, files or calls. Admin emergency support is a separate audited process.
- Force RLS is a separate design choice: do not enable it blindly on tables whose legitimate trigger/definer workflows require owner access. Test owner/service-role behavior explicitly.

## 6. Auth provisioning flow

1. Auth creates a user through Supabase Auth.
2. `handle_new_user()` reads the requested public role as untrusted input, validates it against `buyer|seller|porter`, and derives the initial status server-side.
3. Buyer/Seller: create profile with `active`.
4. Porter: create profile with `pending` and exactly one pending `porter_account_reviews` record.
5. Admin signup metadata is rejected.
6. Social OAuth defaults to Buyer unless a separately approved role selection is implemented safely.
7. Profile trigger failure must fail the signup transaction; do not leave an Auth user without the required profile.
8. The trigger function is not granted as an executable client function. Trigger binding and duplicate signup behavior must be tested using the actual local Supabase Auth service, not plain PostgreSQL alone.

## 7. Dependencies to satisfy before the 38 active migrations

At minimum, the following dependencies must exist before feature migration replay:

- Identity: `profiles` and role/account constraints; `role_requests`; `profile_change_requests`.
- Admin: departments, staff, permission catalogue, permission grants, audit log.
- Helpers: `public.is_nexora_admin()`, `private.has_nexora_permission(text)`, `private.is_nexora_super_admin()`, `public.handle_new_user()`.
- Private schema and appropriate schema usage grants.
- Supabase Auth trigger binding and Auth role/session context.
- Realtime publication prerequisite before communications migrations that add tables to `supabase_realtime`.
- Storage bucket and policies are owned by their dedicated communications migration/API setup; do not create binary objects or copy files in Foundation.
- Admin department seeds and permission catalogue seeds must match all permission keys referenced by the active migrations. A missing permission must fail closed (deny), not default allow.

Do not apply any feature migration until a dependency scan confirms every referenced table, column, function, enum, extension and publication exists in the expected version.

## 8. Required validation gates

### Gate A — source contract
- Compare every column/function reference in all 38 active migrations and frontend files against this spec.
- Resolve stale migration references and business-model contradictions before replay.
- Review Admin governance source and exact permission keys.
- Check all function overloads, grants, triggers, RLS policies and FK delete behavior.

### Gate B — disposable Supabase runtime
- Create the Foundation only in a disposable local Supabase stack using synthetic identities.
- Verify signup for Buyer/Seller/Porter; reject Admin metadata and unsupported roles.
- Verify Porter pending gate, Admin AAL1 denial, AAL2 + permission approval, and no self-approval.
- Verify user cannot mutate role/status/review/verification fields.
- Verify profile isolation and no Buyer identity/contact leakage.
- Run security/performance advisors and inspect all RLS, grants and function ACLs.

### Gate C — hosted NEXORA-TEST
- Only after Gate A/B pass, apply a reviewed Test-only foundation to the empty `NEXORA-TEST` project.
- Use CLI v3 with explicit hosted targeting; never rely on default target. Any hosted mutation requires explicit user authorization and confirmation.
- Recheck project ref before every operation. Use synthetic test identities/data only.
- Confirm no Live project ref, no Production variables, no service-role key in browser, and no real data.

### Gate D — feature migrations
- Rehearse all 38 active migrations in order, then apply to NEXORA-TEST only after a separate review/approval.
- Keep archived duplicate migrations and historical recovery drafts outside active migration path.
- Reconcile the 11 missing historical migration versions separately; do not invent history entries or mark unverified drafts as applied.

### Gate E — physical Android
- After current fail-closed Preview is deployed and confirmed connected only to NEXORA-TEST, test on the user's Vivo Android device.
- Until then, do not ask the user to log in, send chat, or upload files to a Preview deployment that may point to Live.

## 9. Explicitly excluded

- Any Live/Production schema or data change.
- Copying Live Auth users, profiles, private messages, call sessions/signals, attachments or Storage objects.
- Any service-role/secret key in frontend source.
- Calling feature development or testing (paused, not deleted).
- Translation rollout (disabled).
- Payments, payout ledger or financial operations beyond the minimum permission catalogue dependency.
- Replaying the local compatibility fixture against hosted Supabase.
- Treating recovered migration drafts as original or certified.

## 10. Current decision and next implementation step

**Current result:** Foundation contract is now consolidated for the current Marketplace and account decisions. It is a design specification only; it has not been converted to SQL or executed.

**Next safe implementation:** build a dependency-by-dependency compatibility matrix for all 38 active migrations and current frontend, then author a new Test-only SQL baseline only after every required field, permission key, trigger behavior and function signature is confirmed. The SQL must be generated through the approved Supabase migration workflow when the CLI timestamp gate allows it; never invent or rename a migration timestamp.


## 11. Frontend-derived role-request and Admin governance contracts — source audit v2

This section records exact current frontend contracts and identifies incompatibilities. It is design/reconciliation evidence only; it does not authorize SQL or a hosted change.

### 11.1 Seller role request — current frontend contract

Verified in `auth.js`:

- Owner reads only their own pending request using `role_requests(user_id, requested_role, status, created_at)`, ordered newest first, limit 1.
- Owner inserts only `user_id = auth.uid()`, `requested_role = 'seller'`, `status = 'pending'`; a partial unique constraint/index must prevent more than one pending request per user.
- Owner handles SQLSTATE `23505` / constraint name `one_pending_role_request_per_user` as an already-pending request.
- Admin queue reads pending rows with `id,user_id,requested_role,created_at`, then reads only applicant projection `profiles(id,full_name,role,account_status)` for those IDs. This must be restricted to the authorized role-review workflow; it is not permission for general Admin profile browsing.
- Admin review RPC call is exactly `review_role_request(request_id uuid, decision text)`; accepted decision values sent by frontend are `approved` and `rejected`. Admin UI gates to active Super Admin, and server-side implementation must independently enforce Director/Super Admin identity, AAL2, row locking, current pending state, valid applicant role/status, audit logging and atomic profile role transition.
- On approval, the intended product outcome is Seller role; on rejection, Buyer remains Buyer. A request cannot grant Admin or Porter. Duplicate/replayed decisions must fail safely.

**Important:** the frontend call is confirmed, but the original historical SQL defining this table/RPC is not present in the active migration set. Do not infer or fabricate historical source. A new compatible Foundation contract may implement it only after the exact current UI and product decision are approved and synthetic tests pass.

### 11.2 Admin staff columns consumed by current frontend / migrations

The current frontend reads `admin_staff(admin_code,admin_level,department_key,is_active)` for the signed-in Admin. The Director management UI additionally reads the staff roster and permission assignments. Migration #34 directly requires or writes:

- `user_id` (one staff record per Admin profile), `admin_code`, `admin_level` (Director uses `super_admin`; managed staff use `assistant_admin`), `department_key`, `is_active`, `created_by`, `staff_email`, `position_key`, `reports_to_user_id`, `updated_at`.
- Position values: `director`, `managing_director`, `department_head`, `department_officer`. #34 permits at most one active MD and one active Head per department.
- Managed officers are provisioned only against an existing active Buyer Auth/profile account after a secure invite. The server changes the profile role to Admin and inserts staff + permission grants in one transaction. Director is never self-created through signup or public metadata.
- `admin_permission_grants` must support `admin_user_id`, `permission_key`, `is_allowed`, `granted_by`; #34 replaces an officer's grant set transactionally on update and deletes grants on deactivation. Authorization must fail closed; an explicit deny must never be overridden by an allow from another grant row.
- `admin_permission_catalog` must support `permission_key`, `department_key`, `permission_name`, `description`, `is_sensitive`, `is_active`; permission seeds are spread across feature migrations, not just #34. The Foundation must inventory every referenced key before seeding and reject inactive/mismatched department grants.
- `admin_audit_logs` must support the exact columns written by current functions: `actor_user_id`, `actor_admin_code`, `action_key`, `target_type`, `target_id`, optional `reason`, `details` JSONB and timestamp. Append-only from client roles; writes only through audited server-side workflows.

### 11.3 Confirmed frontend / database mismatches requiring reconciliation

- `auth.js` calls `review_role_request(request_id, decision)`; no active migration defines this RPC. It remains a Foundation RPC requirement, not a recovered historical object.
- `marketplace.js` still calls `manage_nexora_user(p_user_id, p_action, p_reason)`, while later Admin UI paths call `admin_manage_user(p_user_id, p_action, p_reason)`. Neither is defined by the 38 active migrations according to the dependency scan. These are not interchangeable until their intended actions, status transitions and permission keys are reconciled. Do not create both aliases blindly.
- `marketplace.js` reads `profiles(id,full_name,role,account_status,created_at)` for Admin user management and allows Buyer/Seller account actions. This must be gated by exact user-management permissions, AAL2 and audited RPCs; frontend grant checks are only presentation, never authorization.
- `admin_staff.admin_level='super_admin'` is still hard-coded by current Director UI and #34, while the newer organization model also uses `position_key='director'`. Preserve a compatibility value for the Director but make the Director predicate require both the protected staff appointment and active Admin profile; position text alone is not authority.
- Existing older Admin policies in migrations #10–12 are not fully aligned: #10 checks AAL2 inline, #12 centralizes active Admin/AAL2 for selected policies, and some Super Admin reads bypass the helper via `public.is_nexora_super_admin()`. Foundation must define one canonical private authorization implementation and compatibility wrappers with identical fail-closed semantics; migration replay tests must verify there is no pre-MFA or inactive-staff read path.

### 11.4 Permission resolver minimum semantics

The canonical `private.has_nexora_permission(text)` must:

1. Require `auth.uid()`, current JWT AAL2, active `profiles.role='admin'`, active account status and one active `admin_staff` appointment.
2. Treat the Director as a protected governance appointment; do not infer Director from email, signup metadata, role alone, a client argument or a permission grant.
3. Require an active catalog entry and an explicit allowed grant for non-Director staff; enforce department scope and any Director-authorized cross-department exception.
4. Fail closed for missing, inactive, conflicting or malformed grants. If deny rows are retained, deny takes precedence over allow.
5. Keep all reads and decisions server-side. The frontend may hide controls based on grants but cannot authorize RPC execution.
6. Revoke PUBLIC/anon execution and grant only the minimum authenticated invocation needed by RLS/RPC wrappers. Internal definer helpers remain in `private`, fully qualified, with empty search_path and explicit `auth.uid()` validation.

### 11.5 Required synthetic tests added to the Foundation gate

- Buyer/Seller cannot read Admin staff, department, permission catalogue/grants or audit data.
- Admin AAL1, inactive Admin, missing staff row, suspended profile, missing grant, inactive catalog permission, wrong department and explicit deny all fail.
- Director-only officer create/update/deactivate works only for the protected Director at AAL2; self-appointment and duplicate active MD/department Head are rejected.
- Officer permission changes are atomic, remove stale grants, preserve audit trail and cannot grant keys from another department without the protected cross-department approval path.
- Seller role request is owner-only, one pending request per user, cannot request Admin/Porter, and only an authorized AAL2 reviewer can approve/reject once. Approval changes Buyer to Seller atomically; rejection leaves Buyer unchanged.
- Admin user suspend/restore/cancel operations are defined once, separately permissioned, audited and cannot be invoked through stale legacy aliases.
- Auth signup cannot create Admin; Porter stays pending until separate approval; Buyer/Seller signup remains active.

**Status:** contracts are now more precise, but original missing historical SQL remains missing. This document is still NOT SQL / NOT DEPLOYABLE / NOT APPLIED. Continue to keep NEXORA-TEST empty until local Supabase runtime gates pass.


### 11.6 Admin permission keys consumed by frontend and active migrations

Additional source inspection of `marketplace.js` and Admin/Logistics migrations identifies these permission keys:

- Current Assistant Admin UI checks `users.view`, `users.suspend`, `users.restore`, `users.cancel`.
- It checks `products.suspend`, `products.restore`, `products.cancel`, and `businesses.suspend` for listing moderation.
- Listing edit workflow uses `products.edit` and `services.edit`.
- Logistics / Porter review and delivery workflows use `logistics.view` and `logistics.assign`.
- #34 adds `marketing.leads.view`, `marketing.leads.manage`, `marketing.campaigns.manage`, `transport.partners.view`, `transport.partners.manage`, `transport.staff.manage`, `finance.view`, `finance.transactions.view`, `finance.transactions.manage`, `finance.refunds.request`, `finance.refunds.approve`, `finance.payouts.manage`.

The Foundation seed audit must account for every key above and every additional key found in the remaining active migrations. The UI's grant lookup is presentation-only. Each RPC must enforce its own server-side key; never treat a visible button or a row in `admin_permission_grants` as sufficient by itself. In particular, the exact permissions for the older `manage_nexora_user` / newer `admin_manage_user` and `manage_marketplace_listing` calls remain unverified and must be reconciled before those operations are enabled.


## 12. Follow-up source audit — Auth trigger, RLS bootstrap and complete permission seed gaps (2026-11-14)

A source scan of all 38 active SQL migration files on `nexora-development`, followed by direct inspection of the relevant definitions, confirms:

### 12.1 Auth signup function evolution

- Migration `20261113230000_buyer_seller_market_categories.sql` defines `public.handle_new_user()` for Buyer/Seller signup. It reads a client-supplied role only from the restricted allowlist `buyer|seller`; invalid roles, including Admin/Porter, are rejected.
- Migration `20261114210000_porter_public_registration_and_review.sql` replaces that function. Email/phone signup can request Buyer, Seller or Porter; OAuth providers default to Buyer. Porter is created with `account_status='pending'` and a pending `porter_account_reviews` row. Admin remains prohibited from public signup.
- Both versions are SECURITY DEFINER with empty search_path and revoke direct EXECUTE from PUBLIC/anon/authenticated. The role value is user metadata, so it must remain limited to this explicit allowlist and must never be treated as proof of Admin authority.
- These migrations define/replace the trigger function; they do not by themselves prove that the Auth trigger is installed exactly once on `auth.users`. The Foundation replay must create/verify the trigger binding, its owner, and safe failure behavior before signup can be considered tested.

### 12.2 RLS bootstrap dependency

- The active migration set contains no definition of `public.rls_auto_enable()`; the only occurrence is migration `20261112045441_revoke_public_rls_auto_enable_execute.sql`, which revokes EXECUTE from that function.
- Therefore the active migration chain has an unresolved dependency on an external/historical Foundation object and likely its event-trigger binding. Do not invent a no-op function or silently remove the revoke. Recover authoritative source or explicitly design and test a replacement event-trigger mechanism in the local Foundation baseline.

### 12.3 Permission catalog seed inventory from active migrations

The active migration sources explicitly seed:
- `logistics.view`, `logistics.assign` in migration `20261113220000_delivery_assignment_system.sql` under the `logistics` department.
- `services.edit` in migration `20261114120000_listing_edit_review_workflow.sql` under `product_business`.
- Marketing, Transport and Finance keys in migration `20261114200000_centralized_officer_account_management.sql`: `marketing.leads.view`, `marketing.leads.manage`, `marketing.campaigns.manage`, `transport.partners.view`, `transport.partners.manage`, `transport.staff.manage`, `finance.view`, `finance.transactions.view`, `finance.transactions.manage`, `finance.refunds.request`, `finance.refunds.approve`, `finance.payouts.manage`.
- #34 also lists `logistics.view|assign` under `transport` but uses `ON CONFLICT DO NOTHING`; because #19 already seeds those keys under `logistics`, the original department mapping remains `logistics`. Do not assume the duplicate statement moves the keys to `transport`.

The current frontend additionally checks `users.view|suspend|restore|cancel`, `products.suspend|restore|cancel`, `businesses.suspend`, and `products.edit`. These keys are not explicitly seeded by the 38 active migration files inspected. They remain unresolved Foundation/catalog requirements, not existing seed data. The active sources do not establish a complete, consistent mapping for these permissions. Reconcile each key's owning department, sensitivity and server-side RPC enforcement before creating the canonical seed set.

### 12.4 Canonical resolver and authorization compatibility

- Multiple active migrations call `public.is_nexora_admin()` and `public.is_nexora_super_admin()`; logistics, listing-edit and delivery workflows call `private.has_nexora_permission(text)`. Their definitions are not supplied by the active feature migrations and remain Foundation dependencies.
- The Foundation must implement the canonical resolver once, then provide only narrowly compatible wrappers with the same fail-closed semantics. It must require active Admin profile + active staff appointment + AAL2; Director authority must come from a protected appointment. Non-Director grants must require an active catalog key, department scope and explicit allow; deny/missing/inactive states fail closed.
- No active migration defines the frontend's Seller role-review RPC `review_role_request(uuid,text)`, or the stale Admin aliases `manage_nexora_user` / `admin_manage_user`. Do not create speculative aliases.

**Status:** source-level audit only. This is not deployable SQL. No local or hosted database was changed, and no runtime/Auth trigger test was run. Keep NEXORA-TEST empty until the local Foundation replay and synthetic Auth/RLS gates pass.

## 13. Auth trigger and permission resolver dependency audit — follow-up (2026-11-14)

### 13.1 Auth trigger binding is absent from the active migration chain

A second source scan of all 38 active migration files distinguished ordinary application triggers from the Supabase Auth signup trigger:

- Active migrations create `profiles_sync_public_identity` on `public.profiles` and `business_profiles_sync_public_business` on `public.business_profiles`, plus application-specific triggers.
- No active migration creates an `auth.users` trigger invoking `public.handle_new_user()`; no active migration creates an event trigger for automatic RLS enablement.
- #19 and #35 define/replace the function body, but function existence is not evidence that the trigger binding exists. The active migration chain alone therefore cannot guarantee profile provisioning on signup.
- The canonical Foundation must explicitly install or verify exactly one `auth.users` AFTER INSERT trigger, verify function owner and SECURITY DEFINER privileges, and test rollback/failure behavior. Do not assume the trigger is managed out-of-band unless an authoritative, versioned source proves it.

### 13.2 Existing active-Admin helper is not the canonical Director/permission resolver

Migration #12 defines `private.is_nexora_active_admin_staff()` and checks JWT AAL2, active `admin_staff`, and active Admin profile. This helper is a useful historical compatibility dependency, but:
- It does not verify the protected Director appointment.
- It does not check `position_key`, protected governance constraints, permission catalog state, department scope or explicit grants.
- Several RLS policies separately OR this helper with `public.is_nexora_super_admin()`; that public predicate's definition is absent from the active feature migration set.
- Feature workflows call `private.has_nexora_permission(text)`, whose definition is also absent from the active feature migration set.

Foundation should retain `private.is_nexora_active_admin_staff()` only as a narrow compatibility wrapper over the canonical resolver, or replace its policies after a complete dependency review. It must not become an alternate authorization path that allows AAL2 active staff to bypass permissions.

### 13.3 Trigger/RLS bootstrap release gates

Before any candidate Foundation SQL is considered:
1. Recover authoritative historical trigger/event-trigger source if available; otherwise explicitly design a new versioned replacement.
2. Prove signup creates exactly one profile and, for Porter, exactly one pending review row; invalid roles and Admin metadata cannot create privileged accounts.
3. Prove every exposed public table has RLS enabled and every relevant policy is installed; verify the RLS automation mechanism on tables created after Foundation.
4. Test trigger owner, function owner, grants, empty search_path, SECURITY DEFINER boundaries and error rollback.
5. Replay the complete 38-migration chain against a disposable local database and run synthetic Buyer/Seller/Porter/Admin AAL1/AAL2 tests before considering NEXORA-TEST.

**Status:** source scan and design documentation only. No trigger, event trigger, SQL migration or database was changed. No runtime claim is made.

## 14. Proposed Auth + RLS infrastructure baseline — design decision v1 (2026-11-14)

**Status: DESIGN ONLY — NOT SQL, NOT A MIGRATION, NOT DEPLOYABLE, NOT APPLIED.** This section defines the candidate contract to resolve the missing historical infrastructure. It does not claim that the active feature chain is currently replayable.

### 14.1 Auth user provisioning trigger contract

Install exactly one PostgreSQL row trigger on `auth.users`:
- Timing/event: `AFTER INSERT FOR EACH ROW`.
- Function: the final, reviewed `public.handle_new_user()` contract already replaced by feature migration #35 (`20261114210000_porter_public_registration_and_review.sql`).
- Function security: `SECURITY DEFINER`, empty `search_path`, every relation/type/function fully qualified, owner explicitly verified as a trusted database owner. Do not grant direct EXECUTE to `PUBLIC`, `anon` or `authenticated`; trigger invocation does not require exposing it as a client RPC.
- The function must derive identity from `NEW.id`; user-editable `raw_user_meta_data` is only an input for the explicitly permitted signup role allowlist and display fields, never Admin authorization. Reject unknown roles and all Admin signup attempts. OAuth provider default remains Buyer as #35 specifies.
- Buyer/Seller signup creates exactly one profile with the intended active status. Porter signup creates exactly one pending profile and exactly one pending `porter_account_reviews` record. Admin appointment is never inferred from metadata/email.
- No blanket exception swallowing. A provisioning error must roll back the Auth insert rather than leave an Auth user without the required application profile/review state. Test email confirmation, OAuth, duplicate/replayed provisioning and malformed metadata.
- Migration must verify/drop only the specifically named expected trigger before creating it, then query `pg_trigger`/catalogs to prove exactly one non-internal trigger points to the intended function. Do not drop unrelated Auth triggers.
- Keep trigger creation separate from function-body history: #19/#35 already define the function, but neither installs the Auth trigger.

### 14.2 Automatic RLS enablement event-trigger contract

Preserve the compatibility object expected by migration #1, but implement it rather than stubbing it:
- Function name: `public.rls_auto_enable()`, return type `event_trigger`.
- Event trigger: one named event trigger on `ddl_command_end`, restricted to `CREATE TABLE`, `CREATE TABLE AS`, and `SELECT INTO` tags, invoking the function.
- Execute only as the trusted database owner capable of altering newly created relations. Verify event-trigger owner and function owner; never expose the function as an RPC. Keep the existing PUBLIC/anon/authenticated EXECUTE revoke.
- Inspect `pg_event_trigger_ddl_commands()` and act only on newly created ordinary or partitioned tables whose schema is exactly `public`. Ignore system schemas, extension-owned objects, views, materialized views, foreign tables and non-public relations. Use catalog OIDs/qualified identifiers rather than trusting an unparsed display string.
- Enable RLS (not FORCE RLS) on the qualifying table. RLS enablement is a fail-safe default, not a policy generator and not a GRANT. Every new public table still requires a separately reviewed owner/participant/admin policy set and explicit table/sequence/function privileges.
- The event trigger affects only objects created after it is installed. Foundation must separately enumerate all existing public tables and enable RLS where required, then test every table's policy and grants. It must not claim that a global trigger alone secures historical tables.
- Verify that the function does not recurse: its internal ALTER TABLE ENABLE ROW LEVEL SECURITY command is not one of the subscribed CREATE tags. Test multi-table DDL, CTAS, SELECT INTO, partitioned tables, non-public tables, extension operations, and a table created without a policy (it must remain inaccessible to API roles, not silently become public).

### 14.3 Canonical Admin authorization contract

Implement one private resolver and narrow compatibility wrappers:
- `private.has_nexora_permission(text)`: authenticated identity required; JWT AAL2 required; active `profiles.role='admin'` and `account_status='active'`; active `admin_staff` appointment required; permission catalog key must exist and be active.
- Director/Super Admin status comes only from the protected, active Director appointment (including the required `admin_level='super_admin'` compatibility value and approved Director position/governance invariant), never email, user metadata, role alone or client input. Director bypass must be explicit and audited for sensitive RPC actions.
- Non-Director staff require an explicit allowed grant, active staff, matching department, and approved cross-department exception where relevant. Explicit deny wins over allow; missing, inactive, duplicate/conflicting or malformed state fails closed.
- `public.is_nexora_admin()` and `public.is_nexora_super_admin()` are compatibility wrappers over the same canonical checks. `private.is_nexora_active_admin_staff()` may remain only as a narrow AAL2+active-staff wrapper and must not be OR'ed into policies in a way that bypasses permission checks.
- Keep decision tables/functions in non-exposed `private`; fully qualify names; empty `search_path`; revoke PUBLIC/anon; grant authenticated execution only where required by RLS or public wrapper. Sensitive mutations stay in narrow audited RPCs, not generic client writes.
- Before replacing policies #10–12, enumerate every policy that calls the old public predicates and test pre-MFA, inactive profile, missing staff, Director, department officer, explicit deny and wrong-department cases.

### 14.4 Data API exposure and table grants (current Supabase platform behavior)

Supabase's breaking change dated 2026-04-28 became enforced on all projects on 2026-10-30: new public tables are no longer automatically exposed to the Data/GraphQL API. Therefore:
- Do not assume a public table is REST-accessible merely because it is in `public`.
- For each table the frontend must access, explicitly grant only the needed schema/table/sequence/function privileges and pair them with RLS policies. Tables not intended for client access should have no client grants and should use private RPC/view paths as designed.
- Add a release checklist that compares frontend `supabase.from(...)`/RPC/Storage calls against actual GRANTs, exposed schemas and RLS policies. Verify Data API behavior on a fresh project rather than relying on legacy defaults.
- Reference: https://supabase.com/changelog/breaking-change-data-api-tables-not-exposed-by-default

### 14.5 Foundation installation order and replay constraint

The active feature migrations depend on Foundation objects before and during their execution. A newly timestamped migration after the current latest version cannot satisfy earlier dependencies in a clean timestamp-ordered replay. Do not create a late Foundation migration and pretend it is a valid bootstrap.

Permitted next design path:
1. Continue searching for authoritative historical Foundation source and trigger definitions.
2. If unavailable, prepare a separately versioned recovery-only Foundation bootstrap candidate for a disposable local database, clearly marked non-deployable.
3. Apply that candidate manually only in the disposable local test environment before replaying feature migrations; validate all 38 migrations in order and record the bootstrap as a deliberate recovery prerequisite, not fabricated historical migration history.
4. After compatibility and replay pass, design a clean forward migration/reconciliation strategy with genuine CLI-generated timestamps and explicit approval. Do not apply anything to NEXORA-TEST yet.

### 14.6 Verification gates

- Catalog assertions: exactly one Auth signup trigger; exactly one RLS event trigger; correct function owner/security config; no client EXECUTE on internal trigger functions.
- Signup matrix: Buyer, Seller, Porter, OAuth Buyer, invalid role, attempted Admin metadata, duplicate provisioning, and trigger failure rollback.
- RLS matrix: every public table enabled; policies and grants separately enumerated; new table after event trigger becomes RLS-enabled before API use; no API role can read an unpolicied table.
- Admin matrix: AAL1/AAL2, active/inactive profile, active/inactive appointment, protected Director, department mismatch, missing/inactive catalog, explicit deny, stale JWT and sensitive RPC audit.
- Platform matrix: explicit Data API grants/exposure on fresh Supabase project; do not rely on old auto-exposure behavior.
- Only after local Foundation + all 38 feature migrations + synthetic E2E pass may NEXORA-TEST be considered, with separate explicit approval.

**Decision:** this design resolves the intended shape of the Auth/RLS baseline, but the missing Foundation source, clean replay and local runtime evidence remain blockers. No SQL, code, trigger, migration, database, hosted project or deployment was changed in this step.
