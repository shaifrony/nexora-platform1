# NEXORA — Missing Migration Recovery Draft Audit

**Date:** 2026-11-13  
**Branch:** `nexora-development`  
**Scope:** The 11 SQL files in `supabase/recovery-not-for-deployment/`  
**Live project:** Read-only catalog inspection only  
**Execution:** No SQL draft was executed.

## 1. Audit boundary and test limitations

This is a source review against the current live catalog, not a successful migration test. The environment does not currently provide an isolated NEXORA database branch, and creating a paid Supabase branch was not approved. No PostgreSQL parser or `supabase test db` runtime was available in the current workspace.

Accordingly:
- SQL was manually reviewed for statement structure, object references, privilege scope, and consistency with catalog evidence.
- Catalog definitions were re-read using read-only SELECT queries.
- Supabase security/performance/health advisors were read; they report on the current live project, not on these unexecuted drafts.
- No claim is made that the SQL has passed PostgreSQL execution, migration replay, RLS integration tests, or end-to-end application tests.

## 2. Per-file review

| Version | Draft | Current-state evidence | Review result |
|---|---|---|---|
| `063728` | Product wholesale pricing fields | Live `products` has `price_unit text NOT NULL DEFAULT 'Piece'`, `minimum_order_quantity numeric NOT NULL DEFAULT 1`, `price_negotiable boolean NOT NULL DEFAULT true`; both MOQ and price-unit CHECK constraints exist with matching names and equivalent expressions. | **Catalog-consistent; syntax manually reviewed.** Depends on core `products` table. Do not replay against live. |
| `092911` | Public approved product policy | Live policy `products_public_approved_select` is for anon SELECT and filters approved listing plus `is_public_business(business_id)`. | **Catalog-consistent; syntax manually reviewed.** Depends on `products` and `public.is_public_business(uuid)`. |
| `093024` | Anonymous product column grants | Live anon has no table-level SELECT on `products`; its column allowlist matches the draft's grant list, including business_id and wholesale price fields, excluding seller_id. | **Allowlist consistent.** The dynamic revoke is intended to clear residual column grants; verify on a disposable database because column-level and table-level grants are independent. |
| `093107` | Safe public-business check function | Live function body checks `public.public_businesses.business_id`; live function is invoker-security with empty search_path; anon and authenticated have EXECUTE. | **Body/config consistent.** Requires public-businesses column access for invoker execution; current anon column grant includes business_id. |
| `094305` | Anonymous public-business read | Live `public_businesses_anon_read` policy is `USING (true)`; anon column SELECT grants are exactly business_id, display_name, country, city; no anon table-level grant. | **Catalog-consistent.** Seller ID and updated_at remain outside the anon allowlist. |
| `094341` | Invoker-safe function hardening | Live `is_public_business` has invoker security, empty search_path and EXECUTE for anon/authenticated. | **Catalog-consistent.** It is a final-state hardening draft; do not assume it reproduces the historical intermediate state. |
| `094441` | Revoke postgres default API grants | Live `pg_default_acl` for postgres/public shows custom defaults: tables only postgres plus service_role non-CRUD privileges; sequences postgres only; functions postgres EXECUTE only. | **Revised during audit.** Draft now targets API-facing table CRUD, sequence USAGE/SELECT, and function EXECUTE defaults only; it does not revoke service_role defaults. Exact original scope remains unknown. |
| `115158` | Cancelled account status | Live `profiles_account_status_check` permits exactly active, pending, suspended, cancelled. | **Constraint-consistent.** Replacing a constraint must be tested against all existing rows in an isolated clone. |
| `145135` | Admin AAL2 super-admin helper | Live function is SECURITY DEFINER in private schema, empty search_path, checks JWT aal2, auth.uid(), active super_admin staff and active admin profile; ACL grants authenticated only besides owner. | **Definition/ACL consistent.** Privileged function; isolated negative tests must prove anon denied, authenticated non-admin denied, aal1 denied, aal2 active super-admin allowed. |
| `153453` | Open buyer demands public projection | Related GitHub source body from 153000 matches the live anon open-demand policy and column allowlist; buyer_id is not granted to anon. | **Source body recovered with version mismatch.** Do not create a second migration record; live version is 153453, repository source was 153000. |
| `160835` | Safe public buyer-demand view | Live view definition exposes the same safe open-demand columns, omits buyer_id, has `security_invoker=true`; anon and authenticated have SELECT on the view. Authenticated has base-table SELECT; anon has matching column SELECT grants. | **View definition/grants consistent.** Requires RLS tests for both roles and buyer identity non-disclosure. |

## 3. Dependency map inferred from the current object references

This is a dependency graph for a possible clean reconstruction/testing sequence, not proof of historical migration order.

1. Core marketplace schema must create `products`, `public_businesses`, `buyer_demands`, and `profiles` first.
2. Product pricing columns/constraints (`063728`) must exist before the product anon column allowlist (`093024`) can grant those fields.
3. Public-business anon policy and column grants (`094305`) plus the `is_public_business` function (`093107`) must both be present before public product visibility is meaningfully testable.
4. The product approved-listing policy (`092911`) depends on the product table and `is_public_business` helper.
5. Invoker hardening (`094341`) modifies the same helper and belongs after the function exists; validate that the anon role can SELECT only the business_id column used by the helper.
6. Default-privilege controls (`094441`) affect future objects created by postgres, not existing objects. If used in a clean rebuild, apply before creating later public objects and then explicitly grant required access.
7. Cancelled status constraint (`115158`) depends on the profiles table.
8. Admin AAL2 helper (`145135`) depends on profiles, admin_staff, auth.jwt/auth.uid and the private schema.
9. Open-demand policy/grants (`153453`) depend on buyer_demands and its required columns.
10. Safe demand view (`160835`) depends on buyer_demands, its safe base-column grants, and its RLS policy. It must retain `security_invoker=true`.

## 4. Important security findings and required tests

### Anonymous product/business surface
- Test anon can read only approved products for public businesses.
- Test anon cannot read seller_id or private business identifiers/metadata beyond the approved public projection.
- Test a product attached to a non-public business is not visible.
- Test invoker helper works with only the business_id column grant and cannot bypass RLS.

### Buyer Demand privacy
- Test anon sees only open demands.
- Test anon cannot read buyer_id, buyer profile, contact details, or any private identity fields.
- Test the public view returns required_date and other intended demand fields.
- Test authenticated buyers/sellers still receive only the rows allowed by the current policies.

### Admin AAL2
- Test anon cannot execute the private helper.
- Test authenticated non-admin and inactive admin cannot pass.
- Test AAL1 admin cannot pass.
- Test active super_admin with AAL2 passes.
- Confirm every SECURITY DEFINER function has a fixed empty search_path and fully qualified object references.

### Default privileges
- Test a newly created table, sequence and function under postgres receive no unintended API-facing grants.
- Confirm service_role defaults remain unchanged.
- Confirm explicitly granted public objects continue to work.
- Check project Data API settings and Supabase platform default behavior before deciding whether this historical migration should be kept in any future baseline.

## 5. Current Supabase Advisor baseline

The advisor run was read-only and is a snapshot of the current live project, not an evaluation of these drafts.

- **Security:** 1 warning — leaked password protection is disabled.
  - Remediation: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- **Performance:** 6 unindexed foreign keys, 20 unused-index notices, and 8 multiple-permissive-policy notices.
  - Unindexed FK guidance: https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys
  - Multiple permissive policy guidance: https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies
- **Health:** no notices returned.

These are separate existing project findings; they must not be treated as failures caused by the recovery drafts.

## 6. Final disposition

| Status | Count |
|---|---:|
| Catalog-consistent and manually reviewed | 8 |
| Source body recovered with timestamp mismatch | 1 |
| Needs special scope/security test before any use | 2 (default privileges and admin AAL2) |
| PostgreSQL parser / isolated replay tests passed | 0 |
| Executed against Live | 0 |

The counts above are audit classifications, not execution approvals. All files remain in `supabase/recovery-not-for-deployment/`. They must not be moved into `supabase/migrations/` until a clean, isolated rebuild/reconciliation plan is approved and tested.

## 7. Official Supabase guidance consulted

- RLS and grants: https://supabase.com/docs/guides/database/postgres/row-level-security
- Safe views with `security_invoker`: https://supabase.com/docs/guides/database/views
- Default privileges / Data API access: https://supabase.com/docs/guides/api/securing-your-api
