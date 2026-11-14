# NEXORA — Isolated Recovery Test Harness

**Branch:** `nexora-development`  
**Purpose:** A safe, zero-cost-first test harness for the reconstructed migration drafts.  
**Execution status:** NOT RUN — Android PostgreSQL 18.6 is available; pgTAP is not available in the selected Termux package repository.

## Safety boundary

- This directory is under `supabase/recovery-not-for-deployment/`, never under `supabase/migrations/`.
- Do not run these checks against the Live Supabase project.
- Do not move recovery drafts into the active migration chain.
- Use a disposable local PostgreSQL/Supabase database or a separately approved isolated test project.
- Do not create a paid Supabase Branch without explicit approval.

## Current environment check

The user has PostgreSQL 18.6 running in Termux on Android 16 and has created `nexora_test`. The `pgcrypto` and `uuid-ossp` extensions are available; `pgtap` did not appear in `pkg search pgtap`. The guarded local compatibility scaffold is committed but has not yet been executed. Therefore no pgTAP test or migration replay has been claimed.

## Test suite

`tests/01_catalog_and_privileges.pgtap.sql` contains 15 catalog/privilege assertions covering:

1. Anonymous access to the private `products.seller_id` column.
2. Approved-product public SELECT policy and its predicates.
3. `public.is_public_business(uuid)` SECURITY INVOKER configuration and execute grant.
4. Anonymous access to private `buyer_demands.buyer_id`.
5. Anonymous access to `required_date`.
6. Open-only public demand policy.
7. `public_buyer_demands` view `security_invoker=true`.
8. AAL2 super-admin helper security mode, search path, and execute privileges.

These are schema-state checks, not proof that every row-level access scenario behaves correctly. In particular, they do not replace JWT/AAL2 simulation or positive/negative RLS tests using fixture users.

## How to run later — isolated environment only

Prerequisites:
- A disposable PostgreSQL/Supabase database restored from an agreed, reconciled schema snapshot.
- pgTAP installed/enabled in that disposable database.
- The recovery drafts and migration chain reviewed before replay.

Run the test file using the test runner appropriate to that isolated environment. Do not point it at the Live project. A full `supabase db reset` is currently unsafe because the repository migration chain and hosted migration history diverge; first create a reconciled baseline or a deliberately minimal fixture schema.

## Additional tests still required

| Area | Required test |
|---|---|
| Product RLS | With fixture businesses/products, anon sees only approved products belonging to public/approved businesses; pending/rejected/private businesses remain invisible. |
| Product privacy | Anonymous and authenticated non-owners cannot retrieve seller IDs or private business fields through tables, views, RPCs, or alternate API paths. |
| Demand privacy | Anon sees open demands only; buyer identity/contact stays inaccessible; required date remains visible. |
| AAL2 | Exercise anon, non-admin, inactive admin, AAL1 admin, and active super-admin AAL2 contexts; only the last should pass. |
| Default privileges | Create temporary tables, sequences, and functions as the target owner after applying the draft; verify PUBLIC/anon/authenticated defaults are revoked and service_role defaults are unchanged. |
| Constraints | Verify account-status and wholesale pricing values, defaults, and CHECK constraints against the approved business rules. |
| Authenticated access | Test Buyer, Seller, Porter, Admin, and service_role separately; verify no role gains access merely by being authenticated. |

## Current result

- Test harness authored and committed to `nexora-development`.
- Tests have NOT been executed.
- No Live SQL, schema, data, migration history, production branch, or deployment was changed.


## Android PostgreSQL note

A limited, guarded scaffold is available under `../local-setup/`. It is suitable only for selected PostgreSQL syntax/catalog work after it is executed locally. It does not reproduce Supabase Auth, Storage, Realtime, PostgREST, actual JWT validation, or the full Supabase RLS runtime. Do not run the recovery drafts or the active migration chain against it.
