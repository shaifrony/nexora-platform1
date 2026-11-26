# NEXORA Foundation Schema — Source Gap Register

**Date:** 2026-11-13  
**Repository:** `shaifrony/nexora-platform1`  
**Branch:** `nexora-development`  
**Scope:** Source review only; no SQL execution.

## 1. Finding: the foundational DDL is not in the current branch tree

The current `nexora-development` repository tree contains 36 files under `supabase/migrations/`, beginning with:
- `20261112045441_revoke_public_rls_auto_enable_execute.sql`
- `20261112050241_secure_public_profile_identity_projection.sql`
- `20261112050345_create_marketplace_core_schema.sql`

No migration in the current tree creates the foundational `public.profiles`, `public.role_requests`, `public.profile_change_requests`, or the original Admin Staff / permission tables. The earliest current migration already alters or references objects that must pre-exist. The branch therefore does not contain a complete clean-database bootstrap sequence.

The older `main` tree inspected during this review has no Supabase migration/schema paths. The backup branch is not a verified source for the missing DDL. No exact original foundation SQL has been recovered in this pass.

## 2. Confirmed dependencies from branch SQL

| Object | Referenced by | Evidence visible in source |
|---|---|---|
| `public.profiles` | Profile identity projection; core marketplace; RLS optimization; transport provider; Porter signup/review; officer management | `id`, `full_name`, `role`, `account_status`, `buyer_category`, `seller_categories`, `updated_at` are explicitly referenced |
| `public.role_requests` | Marketplace RLS optimization; transport role constraint migration | `user_id`, `requested_role`, `status` |
| `public.profile_change_requests` | Marketplace RLS optimization and index creation | `user_id`, `requested_full_name`, `status`, `admin_note`, `reviewed_by`, `reviewed_at` |
| `public.admin_staff` | Transport/Porter review and centralized officer management | `user_id`, `admin_code`, `admin_level`, `department_key`, `is_active`, `created_by`; later migration adds `staff_email`, `position_key`, `reports_to_user_id` |
| `public.admin_departments` | Centralized officer management | `department_key`, `is_assignable` plus display/description fields |
| `public.admin_permission_catalog` | Centralized officer management | `permission_key`, `department_key`, `is_sensitive` plus labels/descriptions |
| `public.admin_permission_grants` | Centralized officer management and permission checks | `admin_user_id`, `permission_key`, `is_allowed`, `granted_by` |
| `public.admin_audit_logs` | Provider, vehicle, Porter and officer review | `actor_user_id`, `actor_admin_code`, `action_key`, `target_type`, `target_id`, `reason`, `details` |
| `public.is_nexora_admin()` | Core marketplace RLS | Function body is not defined by the current migration set inspected |
| `private.has_nexora_permission(text)` | Transport, Porter and Admin workflows | Function body is not defined by the current migration set inspected |
| `private.is_nexora_super_admin()` | Central officer management | Function body is not defined by the current migration set inspected |
| `public.handle_new_user()` | Porter migration replaces the existing Auth trigger function | Original implementation is not present in the current migration set inspected |

This is a dependency/column-reference inventory, not a complete table specification. It does not establish original data types, defaults, all constraints, indexes, grants, RLS policies, triggers or function bodies.

## 3. Why no baseline CREATE TABLE script is being invented

The missing foundation contains security-critical identity and authorization rules. Guessing the original schema could:
- conflict with actual profile columns and constraints;
- break existing Auth user creation and signup behavior;
- weaken role protections or allow public Admin self-registration;
- mismatch the Admin MFA/AAL2 model and permission grants;
- invalidate foreign keys or audit references in later migrations.

For that reason, a reconstructed `profiles` or Admin schema must not be presented as recovered original SQL. It should only be authored as a clearly labelled, independent local test fixture after the intended column contract, role lifecycle, permissions and constraints have been reviewed.

## 4. New local read-only check

A database-name-guarded read-only preflight script has been added:

`supabase/recovery-not-for-deployment/local-setup/03_foundation_prerequisite_audit.sql`

It checks the branch-referenced columns in the foundation tables, required helper functions, schemas and local roles. It performs no DDL or DML and must only be run against the local `nexora_test` database.

## 5. Evidence still required before writing the local foundation fixture

1. Exact `profiles` definition, including every column, type, default, constraint, index, RLS policy, grant and trigger.
2. Exact `role_requests` and `profile_change_requests` definitions.
3. Exact Admin Staff, department, permission catalogue/grant and audit table definitions.
4. Exact definitions and ACLs for `is_nexora_admin()`, `has_nexora_permission(text)`, `is_nexora_super_admin()`, and the original `handle_new_user()`.
5. Auth trigger binding and required behavior for Buyer, Seller, Porter and Admin provisioning.
6. The intended mapping of historical Admin levels and permission keys to the current Director/MD/department model.

Preferred evidence source: a schema-only export from a known isolated Supabase development project or a trusted pre-change SQL backup. Do not query or modify Live Supabase as part of this local task. If no exact source exists, the next design must explicitly be labelled a new local-only fixture and reviewed as such.

## 6. Safety state

- No migration file in `supabase/migrations/` was changed.
- No recovery draft was executed.
- No SQL was run against Live Supabase.
- No changes were made to `main`, production, DNS or paid resources.
- All new work remains under `supabase/recovery-not-for-deployment/local-setup/`.
