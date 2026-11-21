# NEXORA Foundation Schema — New Local-Only Design Proposal

**Status:** SUPERSEDED DESIGN PROPOSAL — NOT ORIGINAL / NOT RECOVERED / NOT DEPLOYABLE  
**Date:** 2026-11-13  
**Repository:** `shaifrony/nexora-platform1`  
**Branch:** `nexora-development`  
**Purpose:** Review the missing foundation contract before writing any local-only SQL fixture.

> This document is a new design proposal based on current product decisions and references found in the development branch. It is not evidence of the historical schema. Nothing in this document has been applied to PostgreSQL or Supabase.

## 1. Design rules

1. Public signup roles are exactly `buyer`, `seller`, and `porter`. There is no Admin/Director/MD role in the public registration form or public signup metadata.
2. Admin identities are provisioned only through a protected, audited administrative process. The application profile role for an appointed staff member is `admin`; position and department belong in the Admin staff model, not in the public signup role list.
3. This marketplace is wholesale-only. No retail buyer/seller market category or retail-only order flow should be accepted. Existing migration values that allow `retail` are a conflict to resolve before replay.
4. Buyer may use the account after signup. Seller may create a business profile and products, but neither the business nor products become public until their respective Admin approval.
5. Porter signup creates a pending account. Porter workspace and delivery work remain blocked until Admin approval.
6. After Porter account approval, the Porter may submit a transport-provider profile and one or more vehicles. Provider approval and each vehicle approval are separate gates. No delivery assignment unless the account, provider and selected vehicle are all eligible.
7. A provider is a service/business profile owned by a Porter account; it is not a separate public signup role.
8. Users cannot self-change role, account status, verification status, Admin membership, review fields, or other protected fields.
9. Full profiles and contact information are private. Public identity is a deliberately limited projection. Buyer identity/contact details must never be exposed through public Buyer Demand listings.
10. All exposed `public` tables use RLS. Privileged actions use narrow server-side RPCs with explicit authorization and audit logging; frontend visibility is not a security boundary.
11. Keep this proposal and any future fixture under `supabase/recovery-not-for-deployment/local-setup/`. Never move it into `supabase/migrations/` or run it against Live Supabase.

## 2. Proposed foundation object groups

### A. Identity and account lifecycle

#### `public.profiles` — one row per Auth user

**Required contract inferred from branch references:**
- `id uuid primary key`, references `auth.users(id)`
- `full_name text`
- `role text`: `buyer | seller | porter | admin`
- `account_status text`: lifecycle gate; exact allowed values need approval
- `buyer_category text`: proposed wholesale-only value, or nullable for non-buyers
- `seller_categories text[]`: proposed wholesale-only category array, or empty for non-sellers
- `updated_at timestamptz`

**Recommended additional baseline fields (new proposal; confirm before implementation):**
- `created_at timestamptz not null default now()`
- optional `phone`, `avatar_path`, `country`, `city` only if the current UI and privacy rules require them
- explicit verification fields only if a real verification workflow is designed; do not treat a user-editable boolean as proof.

**Constraints and behavior to design:**
- Unique identity is the Auth user UUID; never accept a client-supplied profile ID unrelated to `auth.uid()`.
- Role is constrained to the four internal values above, but signup trigger accepts only Buyer/Seller/Porter and defaults OAuth/social signup to Buyer.
- Admin role can only be assigned by the protected officer-provisioning RPC.
- Buyer category must be wholesale; seller categories must be an allowed subset containing wholesale only, subject to whether the product taxonomy is stored separately.
- Account status is server-controlled. Buyer/Seller may become active after valid signup; Porter starts pending; Admin activation requires appointment and MFA policy.
- Users may request profile edits; they do not directly edit protected identity or authorization fields.

**Important source conflict:** `20261113230000_buyer_seller_market_categories.sql` and `20261114210000_porter_public_registration_and_review.sql` currently include `retail` as a category value. That conflicts with the approved Wholesale-Only business model and must be corrected in a separately reviewed design before any migration replay.

#### `public.role_requests`

Branch references require:
- `user_id uuid` → `profiles.id`
- `requested_role text`
- `status text`

Proposed purpose: a user-submitted request to change from Buyer to Seller (or another explicitly approved role transition). Porter public registration is direct and pending; it should not be implemented as a self-service role escalation. The exact supported transitions, uniqueness rule, review fields, and status values remain to be approved.

#### `public.profile_change_requests`

Branch references require:
- `user_id uuid` → `profiles.id`
- `requested_full_name text`
- `status text`
- `admin_note text`
- `reviewed_by uuid` → `profiles.id`
- `reviewed_at timestamptz`

Proposed purpose: users submit a change request; an authorized Admin reviews it. A pending request should not change the profile until approved. Define whether multiple pending requests per user are allowed before implementing.

#### `public.public_identities` / `public.public_profiles`

The current identity projection migration creates a globally readable authenticated projection of `full_name`. That is potentially broader than the privacy rule that only limited public identity is visible.

**Proposal:** expose only a deliberate public display identity, preferably an explicit `public_display_name` and optional approved avatar reference, and never expose email, phone, private address, legal name, Buyer contact details, or unrestricted profile columns. Whether full name itself is public must be an explicit product decision. Buyer Demand queries must use a separate public demand projection or strict column-limited API so the buyer identity cannot leak.

### B. Admin identity, organization and authorization

#### `public.admin_staff`

Branch references require:
- `user_id uuid` → `profiles.id`
- `admin_code text`
- `admin_level text`
- `department_key text`
- `is_active boolean`
- `created_by uuid`
- Later migration adds `staff_email text`, `position_key text`, `reports_to_user_id uuid`

Proposed purpose: a protected one-to-one appointment record for an Admin profile. It is not created through public registration.

The current officer-management source distinguishes:
- Director: `position_key='director'`, legacy/special `admin_level='super_admin'`
- Managing Director: `position_key='managing_director'`
- Department Head: `position_key='department_head'`
- Department Officer: `position_key='department_officer'`

The exact permitted combinations, whether Director is a staff row or a separately bootstrapped root identity, and whether the Managing Director can hold any permission outside their office require a reviewed decision. The branch currently enforces a single active Managing Director and department head per department.

#### `public.admin_departments`

Referenced fields:
- `department_key`
- `is_assignable`

Current branch seeds Managing Director Office, Marketing, Transport, and Accounts. Proposed additional fields: display name, description, created/updated timestamps.

#### `public.admin_permission_catalog`

Referenced fields:
- `permission_key`
- `department_key`
- `is_sensitive`

Proposed additional fields: permission display name, description, active flag, created timestamp. Permission keys are stable machine identifiers, not role names.

#### `public.admin_permission_grants`

Referenced fields:
- `admin_user_id`
- `permission_key`
- `is_allowed`
- `granted_by`

Proposed uniqueness: one grant decision per Admin and permission key. Denials/overrides and inherited department permissions need a clear precedence rule before implementation.

#### `public.admin_audit_logs`

Referenced fields:
- `actor_user_id`
- `actor_admin_code`
- `action_key`
- `target_type`
- `target_id`
- `reason`
- `details`

Proposed requirements: append-only to ordinary users and Admin operators; record actor, action, target, timestamp, reason and structured details. Only a narrowly controlled backend process may write; no ordinary user may update or delete audit history.

#### Authorization helpers

The branch expects:
- `public.is_nexora_admin()`
- `private.has_nexora_permission(text)`
- `private.is_nexora_super_admin()`

These must be defined from `auth.uid()`, active profile status, active Admin staff membership and permission grants. Sensitive Admin operations additionally require a verified AAL2 session, as later migrations already expect. Do not trust user-editable `raw_user_meta_data` for role/permission decisions. The helper functions must have pinned search paths, minimal EXECUTE grants and security-definer use only where justified and audited.

### C. Auth provisioning

#### `public.handle_new_user()`

The existing Porter migration replaces this function, which means its missing original behavior is a high-risk gap.

Proposed trigger behavior:
- Create exactly one profile for a newly created Auth user.
- Accept only `buyer`, `seller`, or `porter` from a strictly validated signup path; ignore/reject any attempt to create Admin through user metadata.
- OAuth providers (e.g. Google/Facebook) always create Buyer accounts.
- Buyer and Seller account lifecycle follows the approved signup rules; Porter profile starts pending and receives a pending review record.
- Initialize category fields consistently with the wholesale-only policy.
- Be idempotent or fail safely on duplicate trigger execution.
- Never silently overwrite an existing profile or Admin role.
- Any trigger failure must not leave an Auth user in a misleading partially provisioned state.

**Platform-only:** actual `auth.users` trigger binding and JWT/AAL2 behavior cannot be validated by the Android PostgreSQL compatibility scaffold. Test later on an isolated Supabase local stack.

### D. Porter account review

#### `public.porter_account_reviews`

The current Porter migration proposes:
- `user_id uuid` → `profiles.id`
- `review_status`: pending / approved / rejected / suspended
- `submitted_at`, `reviewed_by`, `reviewed_at`, `admin_note`, `created_at`, `updated_at`

The account gate is `profiles.account_status`: approval activates; rejection/suspension blocks workspaces. Keep the review record separate so rejected and suspended remain distinguishable. Only protected Admin RPCs may transition review status and write audit events.

### E. Dependencies intentionally outside the foundation

These are feature modules, not part of the minimum identity/Admin foundation:
- Marketplace: `business_profiles`, `public_businesses`, `products`, `buyer_demands`, `seller_offers`
- Transport: `transport_providers`, `transport_vehicles`
- Communications: conversations, participants, messages, invitations, attachments/call history
- Orders, quotations, inventory, delivery jobs, assignments and tracking

They should be added only after the foundation passes its own checks. Each feature table must use the profile FK and authorization contract consistently.

## 3. Lifecycle matrix to enforce

| Account type | Public signup | Initial account status | Admin review gate | Workspace access |
|---|---|---|---|---|
| Buyer | Yes | active after valid signup | No | Buyer workspace |
| Seller | Yes | active after valid signup | Business profile/listing approval before public visibility | Seller workspace; pending listings private |
| Porter | Yes | pending | Porter account approval | Blocked until approved |
| Admin | No | created only by protected appointment | Director-controlled appointment and MFA | Only when active and authorized |

Additional Porter dispatch rule: an approved Porter account alone is insufficient. Provider must be approved, and the particular vehicle must also be approved and available before assignment.

## 4. Conflicts and open decisions before SQL

| Issue | Evidence / risk | Proposed resolution for review |
|---|---|---|
| Wholesale-only vs retail values | Current category migrations allow `retail` | Remove retail from the new local contract; inspect dependent frontend and SQL before any change |
| Porter/provider ownership | Transport provider migration allows owner role Buyer/Seller, while product rules say approved Porter registers provider | Change proposed owner eligibility to active approved Porter; review UI and all dependent policies |
| Public identity projection | Current projection exposes `full_name` to all authenticated users | Decide whether public display name is separate; keep Buyer identity hidden on demands |
| Profile self-update | RLS follow-up creates owner UPDATE policy on `profiles` | Restrict writable columns; protect role, status, categories, verification and Admin fields with grants/trigger/RPC |
| Admin bootstrap/root | Officer migration assumes an existing Director with `super_admin` level | Define the initial trusted Director provisioning procedure outside public signup |
| Account status values | Several migrations depend on `active`, `pending`, `suspended`; complete original check is missing | Approve a single lifecycle vocabulary and transition table |
| Role request workflow | Existing references only prove three columns | Define allowed role transitions and whether role requests are still needed |
| Permission inheritance | Permission grant tables exist in later source, but original helper semantics are missing | Define explicit grants, deny precedence, department scoping and Director override |
| Auth trigger preservation | Existing trigger body is missing and later migration replaces it | Rebuild from desired behavior and test Buyer/Seller/Porter/OAuth/Admin cases on isolated Supabase |

## 5. Proposed build and verification order

1. Review and approve this design; resolve the conflicts above.
2. Write a **local-only fixture** with a loud database guard requiring `nexora_test`; keep it out of `supabase/migrations/`.
3. Create only the minimum local objects in dependency order: schemas/roles compatibility check → profiles → role/profile-change requests → Admin department/catalog/staff/grants/audit → authorization helpers → Porter review → Auth trigger stub/fixture.
4. Separate table DDL from grants/RLS/functions/triggers so each layer can be audited independently.
5. Add local SQL assertions for constraints, foreign keys, allowed role transitions, role immutability, Admin separation, privacy projection and approval gates. Since pgTAP is unavailable in the current Termux environment, use plain SQL assertions that raise exceptions on failure.
6. Run local tests in a transaction or disposable database. A passing Android test proves only PostgreSQL-level behavior for the implemented fixture; it does not prove Supabase Auth, PostgREST, Storage, Realtime, JWT/AAL2 or Edge Function behavior.
7. Only after the full migration-history divergence is separately reconciled should a real isolated Supabase project/local stack be used to test platform-specific behavior.

## 6. Explicit non-actions

- No SQL has been generated or executed by this proposal.
- No existing migration has been changed.
- No recovery draft has been executed.
- No Live Supabase database, migration history, production deployment, DNS or `main` branch has been changed.
- This document must not be treated as a deployable migration or as recovered historical schema.


## 7. Authoritative design resolutions (2026-11-13)

This section resolves the earlier open conflicts using the user's latest explicit NEXORA decisions and the approved governance charter. Where an older migration or design note disagrees, this section is the intended product direction. It still remains a **design proposal**, not a migration.

### 7.1 Account roles and public registration

The homepage registration form exposes exactly:
- `buyer`
- `seller`
- `porter`

No Admin, Director, Managing Director, department-head or officer role is displayed or selectable in public registration.

The internal profile role vocabulary is:
- `buyer`
- `seller`
- `porter`
- `admin` (internal staff only; never public signup)

A Porter is a person-level NEXORA account role. A Transport Provider is a separate provider/service profile linked to an approved Porter account. Therefore:
- Public Porter registration creates a `profiles.role='porter'` profile with `account_status='pending'` and a pending `porter_account_reviews` record.
- Porter cannot use the Porter workspace, register an active provider workflow, or receive delivery assignments until the Porter account is approved.
- After approval, Porter may submit a separate provider profile and one or more vehicles.
- Provider and each vehicle have independent Admin review states.
- Dispatch eligibility requires active approved Porter account + approved provider + approved/available vehicle.
- Buyer or Seller accounts do not own Porter provider profiles under this model.
- A provider is not another user role and never appears in the homepage role selector.

This supersedes the older `NEXORA_PORTER_ARCHITECTURE.md` statement that Porter is not an account role. That document must be updated to avoid contradictory instructions.

### 7.2 SUPERSEDED — old Wholesale-Only category model

This subsection is historical only and must not be implemented. The current approved Marketplace is unified: no Buyer/Seller market-category fields, no Wholesale/Retail marketplace split, and no category-based listing visibility. Sellers set their own prices and quantities; everyone can see the same approved Marketplace listings. The old category constraints and references are removed from the current frontend/product schema. Logistics service-mode terminology is separate and does not create marketplace account categories.

### 7.3 Business/listing approval and account lifecycle

| Account | Public signup | Initial account status | Additional review | What is blocked |
|---|---|---|---|---|
| Buyer | Yes | active after valid signup | None for basic account | No restriction beyond normal authorization |
| Seller | Yes | active after valid signup | Business Profile and listing must be approved before public marketplace visibility | Unapproved business/listings stay private |
| Porter | Yes | pending | Porter account approval, then provider approval and each vehicle approval | Porter workspace/delivery work until account approval; dispatch until all provider/vehicle gates pass |
| Admin staff | No | provisioned only by protected Director workflow | Invitation/appointment, MFA and explicit permissions | All staff access until active appointment and required MFA |

Account status, role, review status, verification status and protected category entitlements are server-controlled. A seller's active account does not imply a publicly approved business or product.

### 7.4 Transport provider and vehicle ownership

The current `transport_provider_vehicle_model` migration's owner policy allowing active Buyer/Seller accounts is incompatible with the latest Porter workflow.

Target policy:
- `transport_providers.owner_user_id` must reference an active, approved `profiles.role='porter'`.
- Provider creation is allowed only after `porter_account_reviews.review_status='approved'` and `profiles.account_status='active'`.
- The provider owner may submit and edit their own non-review fields only.
- Provider approval metadata/status is Admin-controlled.
- Vehicles belong to a provider and may be submitted by that provider's Porter owner.
- Each vehicle's approval and availability are separately controlled.
- Only Transport-authorized staff with required MFA may review provider/vehicle and assign delivery work.

### 7.5 Public identity and profile privacy

No Buyer, Seller or Porter may browse another user's full/private profile. The public identity layer is a narrow projection, not a profile endpoint.

Allowed public identity fields are limited to the minimum needed for a particular marketplace interaction, such as:
- approved display name (personal name or Business display name, depending on role/context);
- explicitly approved profile image;
- non-sensitive, approved public descriptors.

Never expose through public identity projection:
- email, phone, private address, legal identity documents, private verification data, account status, internal notes, Admin data, private activity or full profile columns.

Buyer Demand/Requirement Marketplace must not reveal the Buyer's name, profile ID, avatar, business identity, contact details or any joinable identifier. A public demand card exposes only demand information needed by potential Sellers, including product/requirement, quantity/specification and required date. Buyer identity/contact is revealed only through a separately authorized interaction after the appropriate request/consent workflow.

The existing `public_identities.full_name` projection must be redesigned as a context-safe public display identity. It must not be joined into public Buyer Demand results. Do not assume that RLS on `profiles` protects a separate globally-readable projection.

### 7.6 Internal Admin governance hierarchy

Use the approved `docs/NEXORA_ORGANIZATION_GOVERNANCE.md` as the authority model:

**Director → Managing Director (MD) → Department Heads → Department Officers**

Initial departments:
- Marketing
- Transport & Logistics
- Accounts & Finance

Director is the single highest constitutional authority and alone may change the organization chart, create/retire departments, modify protected permission definitions, appoint/remove MD and department heads, and approve core governance/security policy changes. Director actions require protected server-side controls, MFA and audit; succession/recovery must prevent permanent lockout.

MD runs day-to-day operations, coordinates department heads and may assign operational work within explicit permissions. MD cannot restructure departments, change the protected permission catalogue, grant protected powers to themselves, appoint/remove the Director, or approve their own financial claims/settlements.

Department Heads manage their department within the Director-approved remit and staffing limits. Officers receive only explicit least-privilege permissions scoped to their department. Job title alone never grants access. Cross-department permissions require explicit Director authorization and audit.

Separation of duties:
- Marketing may source/recruit providers but cannot approve its own provider/vehicle applications.
- Transport reviews providers/vehicles and assigns eligible delivery work, but cannot alter finance ledger or approve its own partner invoices.
- Accounts reconciles financial records and prepares refunds/payouts/settlements; the requester cannot approve their own transaction.
- No officer can silently change marketplace roles, account status or verification state without a narrowly scoped permission and audited workflow.

The Director's initial root identity must be provisioned through a secure, out-of-band bootstrap/controlled recovery process, not public signup and not a client-side role update. The exact recovery ceremony and key custody are implementation prerequisites.

### 7.7 `role_requests` and `profile_change_requests`

- `role_requests` is not a way to self-upgrade to Admin or Porter. If retained, its only permitted role transition is Buyer → Seller, and the transition requires an authorized review. Public signup can directly create Buyer, Seller or Porter according to the public registration form.
- Porter review is handled by `porter_account_reviews`, not `role_requests`.
- `profile_change_requests` records proposed personal-name changes. It does not directly modify `profiles`; approval applies the change through a protected server-side action. Multiple pending request policy must be enforced consistently.

### 7.8 Superseded source files and implementation scope

The following current branch artifacts are known to conflict with these decisions and must be reviewed before any migration replay:
- `docs/NEXORA_PORTER_ARCHITECTURE.md`: says Porter is not an account role and provider owners are ordinary Buyer/Seller.
- `supabase/migrations/20261113180000_transport_provider_vehicle_model.sql`: permits Buyer/Seller provider owners and does not enforce approved Porter ownership.
- `supabase/migrations/20261113230000_buyer_seller_market_categories.sql`: permits `retail` in Buyer/Seller categories.
- `supabase/migrations/20261112050241_secure_public_profile_identity_projection.sql`: exposes `full_name` through an authenticated-wide public identity projection.

This task only records the target design. It does not edit those active migrations or frontend behavior. A separate compatibility remediation plan must map every dependent policy, RPC, UI path and test before changing them.
