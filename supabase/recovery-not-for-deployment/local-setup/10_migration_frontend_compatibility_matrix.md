# NEXORA — 38-Migration Dependency & Frontend Compatibility Matrix

**Status:** Static source audit, v1 — no SQL executed  
**Audited branch:** `nexora-development`  
**Audited inventory:** 38 active SQL files, 38 unique version prefixes  
**Target:** NEXORA-TEST only (empty at audit time)  
**Purpose:** Reconcile migration order, missing Foundation objects, frontend contracts and product decisions before authoring a Test-only SQL baseline.

> This is a source-level compatibility assessment, not a successful migration rehearsal. It does not certify runtime SQL, hosted Supabase behavior, RLS, triggers, Auth, Storage or Realtime. No SQL or database was changed.

## 1. Executive result

**Status: BLOCKED — do not run the 38 migrations against the empty NEXORA-TEST project yet.**

The active migration directory contains 38 files with unique versions, but the sequence is not self-contained. It assumes an earlier Foundation schema and custom helper functions which are not created by any of the 38 active migrations.

The missing prerequisites include:

- `public.profiles`, `public.role_requests`, `public.profile_change_requests`
- `public.admin_staff`, `public.admin_departments`, `public.admin_permission_catalog`, `public.admin_permission_grants`, `public.admin_audit_logs`
- `public.rls_auto_enable()` and its expected event-trigger context
- `public.is_nexora_admin()`, `public.is_nexora_super_admin()`
- `private.has_nexora_permission(text)`, `private.is_nexora_super_admin()`, `private.is_nexora_active_admin_staff()`
- Auth profile provisioning contract and Auth trigger binding for `public.handle_new_user()`.

The first active migration already calls `REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()`; no active migration creates that function. The first Marketplace migration assumes `profiles` and `is_nexora_admin()`. Later Admin, Transport, Listing, Delivery and Porter migrations assume the Admin foundation tables and permission functions.

The previous local fixture is not a suitable replacement: it is explicitly a local PostgreSQL compatibility fixture and contains the now-obsolete Buyer/Seller market-category model. It has been marked superseded.

## 2. Active migration-by-migration dependency matrix

Legend: **F** = missing Foundation prerequisite; **P** = platform prerequisite; **M** = earlier active migration prerequisite; **L** = legacy/no-op or cleanup; **C** = compatibility check still required.

| # | Migration | Principal objects / operation | Required dependency and audit result |
|---:|---|---|---|
| 01 | `20261112045441_revoke_public_rls_auto_enable_execute.sql` | Revoke execute on RLS DDL helper | **F:** `public.rls_auto_enable()` must already exist. No active migration defines it. |
| 02 | `20261112050241_secure_public_profile_identity_projection.sql` | Creates `public_identities`, `public_profiles`, sync trigger/function | **F:** `profiles(id, full_name)`. View uses `security_invoker`; confirm profile owner policy allows the projection trigger to populate rows safely. |
| 03 | `20261112050345_create_marketplace_core_schema.sql` | `business_profiles`, `buyer_demands`, `products`, `public_businesses`, `seller_offers`; public business sync | **F:** `profiles`, `public.is_nexora_admin()`; verify Auth context, profile FK/delete behavior and exact business/listing RLS. |
| 04 | `20261112050553_optimize_marketplace_rls_and_fk_indexes.sql` | RLS/index/policy optimization | **F:** `profiles`, `role_requests`, `profile_change_requests`, `is_nexora_admin()`; policies reference pre-existing profile-change workflows. |
| 05 | `20261112050854_create_private_communications.sql` | Conversations, participants, messages, attachments, calls; private Storage setup; Realtime publication | **F/P:** `profiles`, Supabase Storage schema/API, `supabase_realtime` publication and Auth helpers. Calling objects are preserved but remain paused. |
| 06 | `20261112050951_harden_private_communications_rls.sql` | Private conversation membership helpers and RLS hardening | **M:** #05 communication tables; **P:** `auth.uid()`. Review helper ownership, search_path and execute ACLs. |
| 07 | `20261112051022_allow_invitees_to_view_chat_invitation.sql` | Invitee visibility helper/policy | **M:** #05–06 conversation tables and participant lifecycle. |
| 08 | `20261112051711_update_conversation_timestamp_on_message.sql` | Message insert timestamp trigger | **M:** #05 messages/conversations. |
| 09 | `20261112051906_fix_conversation_insert_returning_visibility.sql` | Conversation insert-returning policy adjustment | **M:** #05–07 conversation policies. |
| 10 | `20261112151344_enforce_aal2_on_admin_metadata_reads.sql` | Admin metadata AAL2 policies | **F:** Admin tables, `public.is_nexora_super_admin()`, active staff/profile contract, `auth.jwt()`. |
| 11 | `20261112151436_optimize_aal2_policy_initplans.sql` | Admin RLS initplan optimization | **F/M:** same Admin tables and helper contract as #10. |
| 12 | `20261112151504_centralize_admin_mfa_rls_check.sql` | Creates `private.is_nexora_active_admin_staff()` | **F:** profiles + Admin staff/departments/catalog/grants; **M:** #10–11 policy targets. Depends on role/account status and AAL2 claim. |
| 13 | `20261112153000_publish_open_demands_without_buyer_identity.sql` | Public SELECT policy and restricted column grants on open demands | **M:** #03 buyer_demands. Confirm column-level grants stay aligned with the current Demand card fields and never expose Buyer ID/contact. |
| 14 | `20261112162234_create_product_inquiry_request.sql` | Private/public product inquiry RPC | **M/F:** #03 products/businesses, #05 conversations; profiles and participant contract. |
| 15 | `20261113100000_create_porter_delivery_workflow.sql` | Explicit legacy no-op | **L:** intentionally creates nothing. Do not treat it as creating Porter delivery tables. |
| 16 | `20261113180000_transport_provider_vehicle_model.sql` | Transport providers and vehicles; guarded updates | **F:** profiles, role_requests and `private.has_nexora_permission(text)`; approved-provider/vehicle status contract. |
| 17 | `20261113200000_transport_provider_admin_review.sql` | Provider/vehicle review RPCs | **F/M:** Admin staff/audit, profiles, #16 providers/vehicles, permission helper and AAL2. |
| 18 | `20261113203025_product_linked_private_conversations.sql` | Product context on conversations; guard trigger and inquiry RPC update | **M:** #03 products/businesses and #05–09 communication objects. |
| 19 | `20261113220000_delivery_assignment_system.sql` | Delivery jobs/events and assignment/cancel/reassign RPCs | **F/M:** Admin tables, audit, permission helper, #16–17 transport providers/vehicles. |
| 20 | `20261113230000_buyer_seller_market_categories.sql` | Drops obsolete category fields; updates role/request constraints and signup trigger | **F:** profiles, role_requests and existing `handle_new_user()` contract. Cleanup migration must run only against a compatible starting schema. Current role check is later expanded by #35 for Porter. |
| 21 | `20261113235900_product_market_category.sql` | Removes product market-category remnants; updates inquiry function | **M:** #03, #14, #18 products/businesses/conversations; **C:** ensure it contains cleanup only and no stale category field assumptions. |
| 22 | `20261114090000_services_marketplace.sql` | service_listings and public-business linkage | **F/M:** profiles, business_profiles, public_businesses, Admin check; current auth-gated service listing read contract. |
| 23 | `20261114100000_listing_image_storage.sql` | Listing image Storage policies/metadata linkage | **M/P:** #22 service_listings; Supabase Storage API/schema and object ownership rules. |
| 24 | `20261114110000_seller_listing_edit.sql` | Legacy listing edit staging | **M:** #22 service_listings; verify it remains compatible with later review workflow. |
| 25 | `20261114120000_listing_edit_review_workflow.sql` | Listing edit requests and review/submit RPCs | **F/M:** Admin staff/catalog/audit, permission helper, #03/#22 product and service listing structures, Storage metadata. Permission keys include `products.edit`, `services.edit`. |
| 26 | `20261114130000_listing_edit_history.sql` | Listing edit events and snapshot triggers | **M:** #25 edit request tables/functions and #03/#22 product/service rows. |
| 27 | `20261114130100_verified_purchase_reviews.sql` | Listing reviews and purchase eligibility | **M:** #03 products, #22 service listings, #28 commerce orders/eligibility contract; profile ownership and public review summaries. |
| 28 | `20261114140000_commerce_orders_and_review_completion.sql` | Commerce orders/events and order RPCs | **M:** #03 products/businesses and review eligibility; profiles. Verify generated totals, participant ownership and status transitions. |
| 29 | `20261114150000_product_inventory_moq_quantity_pricing.sql` | Product inventory/commercial fields, validation trigger and order function updates | **M:** #03 products, #28 orders. Seller-defined MOQ/quantity tiers; no forced Retail MOQ=1. |
| 30 | `20261114160000_demand_inbox_quotations_subcategories.sql` | Buyer demand inbox/routing triggers and matching | **F/M:** Admin staff/audit/helpers, #03 demands/products/offers, #25 listing edits; public Demand projection. Matching must not use removed Buyer/Seller market categories. |
| 31 | `20261114170000_delivery_network_management.sql` | Delivery partners/staff and partner management RPCs | **F/M:** Admin staff/audit/permission helper and #16–19 transport/delivery foundation. |
| 32 | `20261114180000_unified_delivery_jobs_assignment.sql` | Unified network job assignment/history | **F/M:** Admin staff/audit/permission helper, #19 delivery jobs, #28 commerce orders, #31 partner/staff and #16 providers/vehicles. |
| 33 | `20261114190000_delivery_tracking_status_history.sql` | Delivery tracking events and status RPC | **F/M:** Admin staff/audit/permission helper and #19/#31/#32 delivery objects. |
| 34 | `20261114200000_centralized_officer_account_management.sql` | Admin staff hierarchy/department/permission seeds and officer management RPC | **F:** existing admin_staff/departments/catalog/grants/audit, profiles, `private.is_nexora_super_admin()`; **C:** review one-active-MD/department-head constraints, seeds, and Director-only appointment. |
| 35 | `20261114210000_porter_public_registration_and_review.sql` | Porter review table, Auth signup trigger replacement and review RPC | **F:** profiles, Admin staff/audit, `private.has_nexora_permission()`, Auth trigger context; **M:** #16 transport provider. Porter account approval and provider approval remain separate gates. |
| 36 | `20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql` | Seller offer negotiation history/RPC and order transitions | **M:** #03 demands/offers, #28 orders/events, profiles. Required-by date and Buyer privacy remain part of the Demand contract. |
| 37 | `20261115110000_product_price_negotiation.sql` | Product price negotiation/events and chat-linked RPCs | **M:** #03 products/businesses, #05 messages/conversations, #28 commerce orders. |
| 38 | `20261115120000_multilingual_chat_foundation.sql` | Language preferences and message translation records | **M:** #05 communications tables and profiles. Translation remains disabled in production; no rollout in this test baseline. |

## 3. Foundation contract: objects that must be authored and reviewed first

| Foundation object | Required minimum contract | Evidence / blocking reason |
|---|---|---|
| `public.profiles` | Auth user UUID PK/FK; `full_name`, `role`, `account_status`, timestamps; protected columns and owner policies | Referenced throughout Marketplace, Admin, Chat, Transport, Porter, Commerce and Delivery. |
| `public.role_requests` | Owner, requested role limited to Seller, status/reviewer/review timestamps, protected review columns | Referenced by #04, #16 and #20; frontend reads it and calls a role-review RPC. |
| `public.profile_change_requests` | Owner-submitted name/profile-change request; protected reviewer/status metadata | Referenced by #04; no active migration creates it. |
| `public.admin_departments` | Unique department key, name, description, assignable state | Required by Admin RLS, officer hierarchy, delivery/finance permission scope. |
| `public.admin_staff` | One protected appointment per Admin profile; admin_code, admin_level, department, active status, creator, timestamps; later position/reporting fields | Required by #10–12, #17, #19, #25, #30–35. |
| `public.admin_permission_catalog` | Unique permission key, department, name/description, sensitive flag, active state | Used by #19, #25, #31–34; #34 seeds catalogue. |
| `public.admin_permission_grants` | Admin, permission, allow/deny, granting actor, timestamps; protected self-grant/Director rules | Used by Admin RLS and officer workflow. |
| `public.admin_audit_logs` | Actor, actor admin code, action, target, reason, safe JSON details, timestamp; append-only from client perspective | Required by provider, listing, Porter, delivery and officer review functions. |
| `public.rls_auto_enable()` | Exact event-trigger helper contract and ownership/execute policy must be recovered or deliberately redesigned | Migration #01 revokes its default execution; no active file creates it. Do not create a guessed helper without inspecting event trigger semantics. |
| `public.is_nexora_admin()` | Compatibility helper for current RLS policies; DB-derived active Admin identity | Used in Marketplace, service, Demand routing policies; not defined in active migrations. |
| `public.is_nexora_super_admin()` and `private.is_nexora_super_admin()` | Compatibility and private Director helper contracts, no user metadata shortcut | Used by #10–11 and #34; no active migration creates either function. Avoid duplicate names/signatures with divergent logic. |
| `private.has_nexora_permission(text)` | Active Admin + AAL2 + explicit grant + scope; deny by default | Used by Transport, Listing, Delivery, Porter; no active migration creates it. |
| `private.is_nexora_active_admin_staff()` | Active Admin profile/staff + AAL2 check | Created in #12; depends on Foundation tables. |
| `public.handle_new_user()` | Auth trigger function validates Buyer/Seller/Porter only; Admin never from user metadata; Porter pending | Replaced in #20 and #35; no active migration initially creates the function or binds the Auth trigger. |
| Auth trigger binding | Exactly one `auth.users` after-insert trigger invoking `handle_new_user()`; transactional failure and duplicate behavior tested on Supabase Auth | Required for signup; not a substitute for function source. |
| Supabase publication/Storage | Supabase-managed schemas/APIs, Realtime publication and private bucket/policies | Must be verified on actual Supabase runtime; never create or mutate platform-internal schemas manually. |

### Admin permission keys observed in active migration SQL

- `logistics.view`
- `logistics.assign`
- `products.edit`
- `services.edit`

Migration #34 seeds a broader catalogue for Marketing, Transport and Accounts. The exact catalogue must be extracted and reconciled with every frontend Admin permission check before any baseline SQL is authored. Missing permissions must deny, never default allow.

## 4. Frontend ↔ database contract mismatches requiring resolution

Static scan of `auth.js`, `marketplace.js`, `chat.js`, `app.js`, `admin/admin.js`, `delivery-network-admin.js` found these call surfaces:

### 4.1 Frontend RPCs not created by the 38 active migrations

The following frontend calls have no matching `CREATE FUNCTION` in the active migration set and must be confirmed as deliberate Foundation RPCs, legacy UI or stale code before baseline design is finalized:

- `review_role_request`
- `manage_nexora_user`
- `admin_assign_porter_delivery_job`
- `admin_cancel_porter_delivery_job`
- `admin_reassign_porter_delivery_job`
- `list_active_nexora_porters_for_logistics`
- `porter_update_delivery_job_status`

Do not invent these RPCs just to satisfy the client. Inspect their current UI workflows, authorization expectations and replacement paths. In particular, the active database model uses approved transport providers/vehicles and unified `delivery_jobs`; old Porter-user assignment RPCs may conflict with that model.

### 4.2 Frontend tables not created by the active migration set

- `porter_delivery_jobs`
- `porter_delivery_job_events`

These are referenced by `marketplace.js`, but no active migration creates those table names. The old `20261113100000_create_porter_delivery_workflow.sql` is a documented no-op; the replacement is the Transport Provider + Vehicle + unified Delivery Job model. Resolve whether these frontend paths are stale and route to the unified schema or explicitly define a supported compatibility layer. Do not create duplicate legacy tables.

### 4.3 Other compatibility items

- `review_role_request` and `manage_nexora_user` need exact parameter/return contracts and AAL2/permission rules.
- Frontend references `admin_permission_grants`, `admin_staff`, `profiles`, and `permission_key`; confirm column names and permitted read paths, not just table existence.
- Chat reads `public_profiles`; this view is created by migration #02, but profile privacy and safe projection semantics must remain intact.
- Service listing reads are login-gated in the frontend; the database currently expects authenticated access. Do not loosen anonymous RLS to silence a 401.
- Calls are paused. Keep call tables/migrations and schema compatibility; do not implement/test call lifecycle or WebRTC in this matrix phase.

## 5. Migration-order and product-model observations

1. **No active Foundation migration:** 38 files are feature migrations layered on a prior database.
2. **RLS auto-enable bootstrap:** #01 expects an event-trigger helper before any other file; its exact historical source is missing.
3. **Auth trigger gap:** #20 replaces `handle_new_user()`; #35 extends it for Porter, but neither creates/binds the original trigger in a fresh empty project.
4. **Admin permission gap:** critical functions are referenced but absent from the active set. #12 creates only the AAL2 helper, not the permission resolver or Director resolver.
5. **Legacy Porter no-op:** #15 deliberately creates no tables; frontend references to old Porter job tables/RPCs are incompatible with the active unified delivery model.
6. **Marketplace cleanup migrations:** #20–21 remove old market-category behavior. The current Foundation must not recreate `buyer_category` or `seller_categories`.
7. **Role lifecycle:** #20 allows Buyer/Seller/Admin, #35 later adds Porter. The final constraint must allow all four internal roles but public signup only Buyer/Seller/Porter.
8. **Demand privacy:** #13 exposes only selected public Demand columns; Buyer ID/contact must remain unavailable. Current required-by date remains part of the contract.
9. **Calling:** existing tables and RLS remain; no new Calling feature or tests while suspended.
10. **Translations:** table schema may be staged, but no production translation rollout is authorized.

## 6. Required next corrections before writing SQL

| Priority | Action | Gate |
|---:|---|---|
| 1 | Recover/define exact Foundation schemas and column contracts from branch references and available schema-only evidence; no personal rows | Foundation source review |
| 2 | Reconcile all Admin table columns, department/permission catalogue seed keys and Director bootstrap | Admin security review |
| 3 | Resolve frontend legacy Porter tables/RPCs against unified delivery schema | Frontend contract review |
| 4 | Define `rls_auto_enable()` only after understanding original event trigger and whether it is required in hosted Test | DDL/RLS safety review |
| 5 | Define Auth signup trigger exactly once and test Buyer/Seller/Porter/Admin-metadata rejection with Supabase Auth | Auth runtime test |
| 6 | Run static SQL parser/format checks and a clean disposable Supabase replay of Foundation + all 38 active migrations | Disposable runtime gate |
| 7 | Only after the above and separate explicit approval, apply the reviewed Test-only Foundation and feature migrations to `NEXORA-TEST` | Hosted Test gate |

## 7. Supabase CLI v3 operational guard

The current CLI v3 documentation/changelog confirms:
- DB commands default to local stack; hosted project requires explicit `--remote`.
- Hosted changes ask for confirmation; non-interactive mutations require `--yes`.
- Configuration flags/environment variables override `config.toml`.
- Do not use deprecated `--linked`, `--project-ref`, or `--db-url` in new automation.

For any future hosted Test mutation, verify the project ref immediately before the command and explicitly target `lhxmqoyxoywntmkmmnjb`. Never run a hosted command with an ambiguous/default target.

Sources:
- Supabase CLI v3 migration guide: https://supabase.com/docs/guides/local-development/cli/migrating-to-v3
- Supabase Nov 4, 2026 breaking-change changelog: https://supabase.com/changelog?types=breaking-change

## 8. Final audit conclusion

**Do not generate or apply Foundation SQL yet.** The static audit has surfaced concrete missing Foundation prerequisites and frontend/database mismatches that need product and security decisions. The safe next implementation is to resolve the legacy Porter frontend paths and document exact Admin/role-request RPC contracts, then prepare the Foundation SQL design. No hosted SQL or application data was changed during this audit.


## 9. Follow-up source verification — legacy Porter Admin panel (2026-11-14)

The previous finding in §4.1–4.2 is now narrowed with direct source inspection:

- `supabase/migrations/20261113220000_delivery_assignment_system.sql` creates `public.delivery_jobs` and `public.delivery_job_events`, backed by approved `transport_providers`/`transport_vehicles`. It does not create `porter_delivery_jobs` or `porter_delivery_job_events` and does not expose the old Porter-user assignment RPC contract.
- `supabase/migrations/20261114170000_delivery_network_management.sql` introduces `delivery_network_partners` and `delivery_network_staff`.
- `supabase/migrations/20261114180000_unified_delivery_jobs_assignment.sql` extends the same `delivery_jobs` model with network partner/staff assignment, delivery mode and Commerce Order linkage. It records assignment history in `delivery_job_assignment_history` and uses the new network assignment functions.
- In `marketplace.js`, the Porter workspace itself already states that the old Porter job-table is not used and directs to Transport Provider Center. However, the Admin Logistics monitor still queries `porter_delivery_jobs` and `porter_delivery_job_events`, reads assigned Porter names directly from `profiles.full_name`, and calls the absent legacy RPCs `admin_assign_porter_delivery_job`, `admin_cancel_porter_delivery_job`, `admin_reassign_porter_delivery_job`, `list_active_nexora_porters_for_logistics`.
- The Admin Logistics monitor is therefore a confirmed stale frontend path, not an unresolved database requirement. Do **not** create legacy Porter tables or RPCs. The correct replacement must use `delivery_jobs`, `delivery_job_events`, `delivery_job_assignment_history`, approved transport provider/vehicle and delivery-network partner/staff records, and the existing narrowly authorized network assignment RPCs.
- Replacement UI must avoid displaying private `profiles.full_name` or raw pickup/delivery contact/address details outside the Logistics permission boundary. Keep the current RLS and AAL2/permission checks; do not make direct client writes to operational tables.
- Until the Admin panel is migrated and tested against the unified schema, keep its old panel explicitly blocked/hidden rather than allowing it to issue failing legacy queries. This is separate from Buyer Department priority; do not divert Buyer delivery tracking into the Admin panel.

No application code or database was changed in this source-verification step. The exact Admin UI replacement is a follow-up implementation item after Buyer-critical work and Foundation runtime gates.


## 10. Follow-up source verification — Seller role request and Admin contracts (2026-11-14)

- Inspected current `auth.js`: Seller request owner reads `role_requests(user_id,requested_role,status,created_at)`; submits only Seller/pending; frontend expects a unique pending-per-user constraint named `one_pending_role_request_per_user`; Director review RPC signature is `review_role_request(request_id uuid, decision text)`, decisions `approved|rejected`.
- The original historical SQL for `role_requests` / `review_role_request` is absent from the active migration set. It is a confirmed frontend contract, not recovered historical implementation. New Foundation implementation must atomically approve Buyer→Seller or reject without role change, enforce AAL2 + Director, lock/reject replayed requests and audit.
- Inspected #34 officer management: exact staff fields include `admin_code`, `admin_level`, `department_key`, `is_active`, `created_by`, `staff_email`, `position_key`, `reports_to_user_id`; grants use `admin_user_id,permission_key,is_allowed,granted_by`; audit writes `actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details`. Director is currently represented by `admin_level='super_admin'` and `position_key='director'`.
- Confirmed stale Admin UI aliases: older `marketplace.js` calls `manage_nexora_user`, later Admin UI calls `admin_manage_user`; neither appears in active migrations. Do not create both aliases without reconciling intended status transitions and permission keys. The Admin user-management list reads Buyer/Seller profile identity and therefore requires a strict server-side permission boundary and audit.
- Added detailed source-derived contracts, mismatches and synthetic security gates to Foundation design spec §11. It remains design-only; no SQL or runtime schema changed.
- Commit: `7b95b2206d5b4f2fa553f293e63e2fd63351c58f`.


## 11. Follow-up permission-key inventory — Admin UI and migration sources (2026-11-14)

Direct source inspection confirmed the current Admin UI references `users.view|suspend|restore|cancel`, `products.suspend|restore|cancel`, and `businesses.suspend`. Listing edit migrations use `products.edit` and `services.edit`; delivery/provider/Porter flows use `logistics.view` and `logistics.assign`. Migration #34 seeds Marketing, Transport and Finance permissions including partner/staff management and refund/payout keys. The exact full seed inventory must be checked against every active migration before a Foundation seed set is authored.

The UI's client-side grant lookup is not an authorization boundary. The exact server-side permission requirements for legacy `manage_nexora_user`, newer `admin_manage_user` and `manage_marketplace_listing` calls remain unresolved. Do not enable these actions or create aliases until the intended status transitions, permission keys and audit semantics are specified. See Foundation spec §11.6.


## 12. Follow-up source audit — Auth signup, RLS bootstrap and permission seed coverage (2026-11-14)

- Scanned the 38 active SQL migration files for Auth/RLS/Admin function references and permission-catalog seed statements.
- Signup function history: #19 defines Buyer/Seller-only `public.handle_new_user()`; #35 replaces it with Buyer/Seller/Porter allowlist, defaults OAuth to Buyer, and keeps Porter pending with a review row. Admin is never a public signup role. Both versions revoke direct client EXECUTE. The Foundation must still verify/install the Auth trigger binding on `auth.users`; function source alone does not prove trigger installation.
- `public.rls_auto_enable()` is referenced only by migration #1's EXECUTE revoke and has no definition in the active migration set. This is an unresolved historical/Foundation dependency. Do not add a no-op or remove the revoke without a tested replacement.
- Active permission seeds: #19 `logistics.view|assign` (department `logistics`); #24 `services.edit` (`product_business`); #34 Marketing, Transport and Finance keys. #34 repeats the Logistics keys under `transport` with `ON CONFLICT DO NOTHING`, so it does not change their earlier `logistics` department.
- Frontend keys `users.view|suspend|restore|cancel`, `products.suspend|restore|cancel`, `businesses.suspend`, and `products.edit` are not seeded by the active 38 migrations. These are unresolved catalog requirements. Confirm department, sensitivity and RPC enforcement before seeding.
- `is_nexora_admin()`, `is_nexora_super_admin()` and `has_nexora_permission(text)` are consumed by feature migrations but remain Foundation prerequisites; canonicalize their fail-closed behavior, AAL2 and protected Director rules before any replay.
- No SQL, app code, local/hosted DB, NEXORA-TEST, Live/Production, main, DNS, paid service or deployment was changed. This pass is source audit + documentation only; no runtime test was run.

## 13. Auth trigger binding and Admin resolver source audit (2026-11-14)

- Second scan of all 38 active migrations confirms application triggers exist for public profile identity and business identity, but no active migration creates an `auth.users` trigger invoking `public.handle_new_user()`. #19/#35 only define or replace the function.
- No active migration creates an event trigger for automatic RLS enablement. #1 only revokes EXECUTE on `public.rls_auto_enable()`; its definition and binding are absent.
- #12 defines `private.is_nexora_active_admin_staff()` with AAL2 + active Admin profile + active staff appointment. It does not itself enforce protected Director appointment or per-permission catalog/grant/department scope. Several policies OR it with `public.is_nexora_super_admin()`, which has no definition in the active feature migrations.
- `private.has_nexora_permission(text)` is consumed by multiple workflows but not defined in the active feature migration set.
- Foundation must install/verify one Auth trigger, define a tested RLS automation strategy, and make the old active-admin helper a narrow wrapper (or replace its policies) so it cannot bypass the canonical permission resolver.
- Release gate: full disposable local replay + synthetic signup/role/AAL1/AAL2/RLS tests. No trigger or database was changed in this audit.

## 14. Proposed Auth/RLS baseline and Supabase Data API exposure (design only, 2026-11-14)

- Auth: install one `auth.users AFTER INSERT FOR EACH ROW` trigger invoking the final #35 `public.handle_new_user()` function. The function remains SECURITY DEFINER with empty search_path and trusted owner; no client EXECUTE. It must atomically create exactly one profile and exactly one pending Porter review where applicable; reject Admin/unknown role metadata; do not swallow errors. #19/#35 define the function but do not install this trigger.
- RLS automation: implement the existing expected `public.rls_auto_enable()` as a real event-trigger function, with one owner-controlled `ddl_command_end` event trigger for CREATE TABLE/CTAS/SELECT INTO. Process only newly created ordinary/partitioned tables in `public`, enable RLS (not FORCE), and ignore views, foreign/system/extension objects. This does not create policies or grants; audit existing tables separately. Keep client EXECUTE revoked.
- Admin: one canonical `private.has_nexora_permission(text)` resolver; AAL2 + active Admin profile + active staff appointment; protected Director appointment; active catalog key; explicit department-scoped grant for officers; deny wins; fail closed. Public Admin/Super Admin and old active-staff helpers become wrappers only, never policy bypasses.
- Supabase platform change: new `public` tables are no longer automatically exposed to Data/GraphQL API; enforcement date 2026-10-30. Explicitly grant only needed table/sequence/function privileges and pair them with RLS. Check frontend REST/RPC calls against actual grants/exposure. Reference: https://supabase.com/changelog/breaking-change-data-api-tables-not-exposed-by-default
- Replay constraint: a newly timestamped Foundation migration after latest feature migration cannot satisfy earlier timestamp-ordered dependencies. Do not fabricate an earlier timestamp. If historical source cannot be recovered, use a clearly marked recovery-only bootstrap in disposable local DB before replaying all 38 feature migrations; only later design a genuine forward reconciliation migration.
- Verification gates: trigger catalog cardinality/ownership; signup and rollback matrix; RLS table/policy/grant matrix; Admin AAL1/AAL2/department/deny matrix; fresh-project Data API exposure; full local replay and synthetic E2E. No SQL/code/trigger/database/hosted change occurred in this design pass.

## 15. Permission catalog and frontend RPC mismatch audit

**Source audit only; no SQL/RPC/seed changed.**

### Seeded permission keys
- #19: `logistics.view`, `logistics.assign` (inserted under department `logistics`).
- #25: `services.edit` (inserted under `product_business`).
- #34: `marketing.leads.view`, `marketing.leads.manage`, `marketing.campaigns.manage`, `transport.partners.view`, `transport.partners.manage`, `transport.staff.manage`, `logistics.view`, `logistics.assign`, `finance.view`, `finance.transactions.view`, `finance.transactions.manage`, `finance.refunds.request`, `finance.refunds.approve`, `finance.payouts.manage`.
- Critical: #34's Logistics key inserts use `ON CONFLICT DO NOTHING`; they do not move #19's existing keys from `logistics` to `transport`. #34 officer assignment requires department match, so Transport staff cannot receive those permissions. #25's `product_business` department is not in #34's department seed. #25 references `products.edit` but only seeds `services.edit`.

### Frontend keys with no active migration seed found
`users.view`, `users.suspend`, `users.restore`, `users.cancel`, `businesses.view`, `businesses.suspend`, `products.view`, `products.suspend`, `products.restore`, `products.cancel`, `products.edit`, `security.audit_logs.view`.
Missing keys deny by default; do not grant or bypass.

### RPC contracts
- `review_role_request(request_id uuid, decision text)` with `approved|rejected`; owner table contract expects `role_requests(user_id,requested_role,status,created_at)` and partial unique `one_pending_role_request_per_user`. Missing from active migrations. Foundation must add row lock, pending-only transition, active Buyer precondition, atomic Buyer→Seller approval, rejection preserving Buyer, Director/AAL2 enforcement and audit.
- Frontend calls `manage_nexora_user(p_user_id,p_action,p_reason)`; no active definition.
- Alternate `admin_manage_user` was observed but also has no active definition. Do not add aliases.
- Frontend calls `manage_marketplace_listing(p_target_type,p_target_id,p_action,p_reason)`; no active definition. Do not invent generic mutation.
- #34 `manage_nexora_officer` exists but depends on unresolved catalog department mapping.

### Next blocker
Choose canonical departments for Logistics/Transport, Product/Business, user governance, listing moderation and audit; map each UI action to one seeded key and one server-side RPC/policy. Then reconcile stale RPC callers and test missing/deny, cross-department and Director/AAL2 cases. No database or runtime changes in this audit.

## 17. Recommended department governance proposal (not approved / no SQL)

- Keep `logistics` separate from `transport`: Logistics = order/delivery assignment; Transport = external providers, vehicles and staff. Seed both department keys explicitly. Do not remap #19 Logistics permissions to Transport.
- Seed `product_business` for Product/Service listing workflows; add missing `products.edit` only after reviewed action/RPC mapping.
- Proposed `trust_safety` owns user, business and product moderation. Marketing remains leads/campaigns only.
- Proposed moderation keys: `users.view/suspend/restore/cancel`, `businesses.view/suspend`, `products.view/suspend/restore/cancel`; sensitive by default except read-only product projection. `users.cancel` is reversible deactivation, never Auth hard delete.
- `products.edit` and `services.edit` belong to `product_business`.
- Director-only initially: Seller public activation, Product/Service/Business initial approval, Admin appointment, Buyer→Seller role review and Audit Log viewing. No default audit-log staff grant.
- Trust & Safety cannot grant permissions, appoint staff, change roles, access finance or private chat/call content. Cross-department exceptions are explicit and audited.
- No RPC aliases. User moderation and listing moderation remain separate narrow RPC contracts; role review remains separate Director-only row-locked RPC.
- Proposal only, pending explicit owner confirmation; no executable seeds/RPC/migration authorized.
