# NEXORA — Missing Migration Recovery Package

**Branch:** `nexora-development`  
**Repository:** `shaifrony/nexora-platform1`  
**Purpose:** Preserve recovery work for 11 migration-history entries whose original SQL files were not present in the repository.  
**Execution status:** NONE — no SQL in this directory has been executed.

## Critical warning

This directory is deliberately named `recovery-not-for-deployment` and is outside `supabase/migrations/`. These files must not be moved into the active migration directory or run against Live Supabase.

The package does **not** claim that 11 original historical SQL files have been recovered byte-for-byte. The original sources were not found in the checked GitHub branches/commit paths. Ten files are catalog-based reconstruction drafts; one SQL body was recovered from a GitHub commit but its live migration timestamp differs from the repository file timestamp.

A reconstruction is a new representation of the observed final database state, not proof of the exact historical statements, ordering, intent, or intermediate state.

## Recovery inventory

| Live history version | Package file | Source classification |
|---|---|---|
| `20261112063728` | `20261112063728_add_wholesale_product_pricing_fields.sql` | Reconstructed from current products columns/defaults/constraints |
| `20261112092911` | `20261112092911_restrict_public_products_to_approved_businesses.sql` | Reconstructed from current products RLS policy |
| `20261112093024` | `20261112093024_limit_anonymous_product_columns.sql` | Reconstructed from current anon column privileges |
| `20261112093107` | `20261112093107_expose_safe_public_business_check_for_anon_policy.sql` | Reconstructed from current function body, security mode and ACL |
| `20261112094305` | `20261112094305_public_business_safe_anon_read.sql` | Reconstructed from current public-business policy and anon column grants |
| `20261112094341` | `20261112094341_make_public_business_check_invoker_safe.sql` | Reconstructed from current SECURITY INVOKER function configuration |
| `20261112094441` | `20261112094441_revoke_postgres_default_public_api_grants.sql` | Reconstructed from current postgres-owned default ACL snapshot; exact historical scope not proven |
| `20261112115158` | `20261112115158_allow_cancelled_account_status.sql` | Reconstructed from current profiles account-status CHECK constraint |
| `20261112145135` | `20261112145135_require_aal2_for_nexora_admin_access.sql` | Reconstructed from current private super-admin function and ACL |
| `20261112153453` | `20261112153453_publish_open_demands_without_buyer_identity.sql` | SQL body source-recovered from commit `e468347c43e9a88d17504fca7c5ed8304aaa8374`; live version is 153453 but repo source is 153000 |
| `20261112160835` | `20261112160835_secure_public_buyer_demand_projection.sql` | Reconstructed from current view definition, reloptions and grants |

## GitHub source recovery notes

- Branch inventory showed `main` and `backup-before-changes` at the same older commit; the backup branch did not contain the migrations directory at the requested path.
- The `nexora-development` history was inspected, including commits related to public demand publication, admin AAL2, product pricing and security.
- Commit `e468347c43e9a88d17504fca7c5ed8304aaa8374` contains the SQL body that corresponds to the open public-demand policy/grant behavior. Its repository migration file is timestamped `20261112153000`, while live history records `20261112153453`.
- Existing migrations `20261112151344`, `20261112151436`, and `20261112151504` were inspected to understand the later AAL2 policy evolution. They do not prove the exact content of the earlier live-only version `20261112145135`.
- No claim is made that the remaining ten original SQL bodies were found.

## Live catalog evidence inspected (read-only)

The recovery drafts were based on read-only catalog inspection of:
- `products` columns, defaults, constraints, RLS policies and anonymous column grants;
- `public_businesses` columns, anonymous read policy and anonymous column grants;
- `public.is_public_business(uuid)` definition, SECURITY INVOKER setting and function ACL;
- `profiles_account_status_check`;
- `private.is_nexora_super_admin()` definition and function ACL;
- `buyer_demands` anonymous policy and column grants;
- `public.public_buyer_demands` view definition, `security_invoker=true` reloption and grants;
- `pg_default_acl` entries for objects owned by `postgres` in schema `public`.

These are point-in-time observations. They do not reveal the original SQL text or historical sequence.

## Required review before any use

1. Compare every draft with the complete current Live definitions again immediately before any future change.
2. Review privilege and RLS behavior in an isolated PostgreSQL/Supabase environment.
3. Resolve whether the default-privilege draft precisely matches the original intent; its scope is especially sensitive.
4. Test the security-definer functions and all anonymous access paths with both anon and authenticated roles.
5. Verify the demand view preserves buyer privacy and the required-date field.
6. Verify product price unit, MOQ and negotiability constraints against the approved wholesale-only business model.
7. Obtain explicit authorization for any Live database operation in a separate request.

## Current safety state

- No Live SQL executed.
- No migration-history rows inserted, deleted or updated.
- No existing migration file overwritten or deleted.
- No `main` branch or Production deployment changed.
- Recovery drafts are stored outside `supabase/migrations/` so normal migration discovery will not pick them up.
