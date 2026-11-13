# NEXORA Work Tracker

Updated: 2026-11-14

Latest marketplace progress: [Business Profile & Product Form Progress](NEXORA_BUSINESS_PROFILE_AND_PRODUCT_FORM_PROGRESS.md). Buyer Demand review: [NEXORA Buyer Demand Progress](NEXORA_BUYER_DEMAND_PROGRESS.md). Buyer phase checklist: [NEXORA Buyer Completion Checklist](NEXORA_BUYER_COMPLETION_CHECKLIST.md).

Review RPC local validation closeout: [NEXORA_REVIEW_RPC_LOCAL_VALIDATION_CLOSEOUT.md](NEXORA_REVIEW_RPC_LOCAL_VALIDATION_CLOSEOUT.md). Repeated local logic testing is closed; two-session concurrency remains unverified and is not a blocker for continuing product implementation. Hosted deployment remains blocked.

Status definitions: **Done (staged)** = committed to Development, not necessarily deployed; **Partial** = foundation exists; **Pending** = not implemented; **Blocked** = prerequisite or release approval missing.

| Workstream | Status | Notes |
|---|---|---|
| Single-domain architecture | Done (staged) | One root app, shared auth/backend, role-based workspaces |
| Admin console moved into Administration route | Done (staged) | Existing Admin console moved from Login section into protected route; E2E pending |
| Role-aware dashboard routing | Partial | Buyer/Seller/Admin/Porter routes staged; browser E2E and hosted migration pending |
| Public registration roles | Decision confirmed | Homepage must show exactly Buyer, Seller and Porter; no administrative roles |
| Porter registration approval | Done (staged) | Signup, pending profile, review table, MFA + logistics.assign RPC, audit log and admin queue staged; migration/E2E pending |
| Admin sign-in + MFA | Partial | Existing Auth MFA AAL2 flow; browser E2E pending |
| Officer account management | Partial | Form/Edge Function/SQL migration staged; DB not migrated or integration-tested |
| Marketplace Wholesale + Retail alignment | Frontend and migration sources updated; Auth/RLS/E2E verification pending | Buyer account category removed; all active Buyers can see and order both Wholesale and Retail approved listings. Seller chooses sale type per product; account-level seller_categories is deprecated. Demand routing uses product taxonomy and approved Business Profile only. Not deployed; migration history remains unreconciled. |
| Services Marketplace | Partial | Listing flow staged; security/E2E remain |
| Buyer Demands & quotations | Partial | Existing form captures product, category/subcategory, specs, quantity, optional budget, currency, destination and required date; submission and public-board/Seller-inbox paths inspected. Underlying view/RLS/matching privacy review still pending; see NEXORA_BUYER_DEMAND_PROGRESS.md |
| Commerce orders | Partial | Order lifecycle staged; payments/disputes/refunds absent |
| Verified reviews | Partial | Verified-purchase workflow staged; E2E pending |
| Delivery Network | Partial | Partner/team, assignment and tracking staged; receipt, finance and API integration pending |
| Marketing Department | Pending | Lead, campaign and onboarding modules not complete |
| Accounts & Finance | Pending | Ledger, reconciliation, refunds/payouts and maker-checker incomplete |
| Reports & audit | Partial | Some audit records exist; unified reporting pending |
| Review RPC local logic validation | Done (local only) | Base and extended local suites passed; local superuser caveat documented; concurrency not yet verified; hosted deployment not approved |
| Separate Admin domain | Not required | Earlier prototype retained temporarily; do not deploy as a second app |
| Production release | Blocked | Migration history mismatch, isolated DB and E2E missing; no approval |

## M0 — Single-domain foundation
- [x] One-domain architecture documented.
- [x] Protected Administration Dashboard route added.
- [x] Existing Admin console moved out of Login section.
- [x] Header Dashboard navigation and Buyer/Seller/Admin post-login routing added.
- [x] Administration route checks active Admin Staff and MFA AAL2.
- [ ] Browser E2E: Buyer, Seller, pending/approved/rejected Porter, Director, MD, Marketing, Transport, Accounts.
- [ ] Test Admin MFA verification redirect, unauthorized deep links, inactive account, refresh and back/forward.
- [ ] Remove/archive separate Admin prototype after code review.

## M1 — Identity / governance
- [x] Local Review RPC base and extended logic-test cycle closed; see closeout document. No more repetitive local tests unless code changes materially.
- [ ] Optional focused two-session concurrency check before any hosted Review RPC release.
- [x] Director, MD and department governance defined.
- [x] Officer invite and permission backend staged.
- [ ] Reconcile all migrations in order.
- [x] Add Porter to profile role model and Auth signup trigger; public metadata cannot create Admin identities.
- [x] Ensure Porter starts pending; only audited Admin/Transport approval activates the account.
- [x] Route only approved active Porter accounts to Porter Dashboard and Transport Provider Center; block pending/rejected/suspended access.
- [ ] Run migration-chain checks and browser E2E for signup, approval, rejection, suspension and re-approval.
- [ ] Test migration on isolated DB.
- [ ] Negative tests for privilege escalation, MFA bypass, department scope, revocation and invite rollback.

## M2 — Marketplace
- [ ] Buyer department completion: see `docs/NEXORA_BUYER_COMPLETION_CHECKLIST.md`; universal product visibility, safe public columns, category-independent Inquiry/Order and Demand routing have been staged. The final inventory Order RPC's legacy Buyer-category gate has now been removed. Limited local visibility fixture/read-only catalog checks ran successfully: 7 PASS; no active Buyer/Seller fixture profiles, so account-level visibility comparisons SKIP. This does not test full Marketplace schema, RPCs, JWT/PostgREST or hosted RLS. Buyer quotation acceptance workflow remains unimplemented. Final privacy/Auth/RLS, wallet/payment, delivery integration and E2E remain pending.
- [x] Review and harden the final staged Auth trigger source: Buyer/Seller legacy market metadata ignored; every OAuth provider except email/phone forced to Buyer; public role allowlist blocks Admin/Director; Porter remains pending; trigger function has empty search_path and no Data API EXECUTE. Frontend role/OAuth/status gates reviewed. [x] Local B-01 regression SQL run PASS on nexora_test; hosted Auth/JWT/RLS and browser E2E remain untested. Do not deploy until migration history is reconciled.
- [x] Remove Buyer-category product visibility restrictions from database/RLS/RPC and order logic; verify that sale type remains per product.
- [x] Final Seller listing edit/review RPCs use per-product `market_category` and mode-specific MOQ/price-tier validation; no account-level `seller_categories` authorization gate remains in the final effective definitions. The read-only verification script checks both RPC definitions.
- [x] Remove account-level Buyer/Seller category assumptions: Buyer sees all approved listings; Seller chooses Wholesale or Retail per product.
- [x] Existing Business Profile/Sales Center foundation inspected: one profile per Seller, one sales-center address, multiple products per business.
- [x] Update Product Listing form and insert/edit paths so Seller selects Wholesale or Retail for each product; MOQ and price-tier semantics remain subject to a separate business decision.
- [x] Product/Service listing, image upload and editing foundation exists; dual-market edit and visibility alignment pending.
- [x] Buyer Demand form, submission, public-board and Seller-inbox client paths inspected. Staged source review confirms SECURITY INVOKER public projection omits Buyer identity, anon column grants omit buyer_id, Buyer ownership/Seller inbox RLS and offer-inbox gate, required date, and category/subcategory matching without sale-type gates. Read-only catalog audit 24 initially SKIPped because the limited fixture lacked Demand tables. Added local-only Demand fixture 25, behavior tests 26 and one-command Termux runner 27; user execution pending. JWT/PostgREST/E2E and quotation acceptance remain pending.
- [x] Commerce order and verified review workflow staged.
- [ ] Payments, inventory, dispute/refund and notifications.
- [ ] E2E, mobile and accessibility.

## M3 — Transport & Logistics
- [x] Partner/team/provider model, delivery jobs, assignment and tracking staged.
- [ ] Buyer receipt confirmation and completion report.
- [ ] Delivery charge and financial settlement.
- [ ] Courier API/webhooks.
- [ ] Retail/Wholesale E2E and negative authorization tests.

## M4 — Administration departments
- [ ] Director: staff lifecycle, permission catalogue, audit.
- [ ] MD: daily operations, escalation and coordination.
- [ ] Marketing: lead, acquisition, campaign and growth reports.
- [ ] Transport: delivery operations and provider performance.
- [ ] Accounts: ledger, reconciliation and maker-checker.
- [ ] Department-scoped reports and exports.

## M5 — Release
- [ ] Security/RLS/RPC review.
- [ ] Isolated DB migration rehearsal.
- [ ] Browser E2E and mobile tests.
- [ ] Backup/restore and release checklist.
- [ ] Explicit production approval.

## Blockers
1. Hosted Supabase migration history is behind staged migrations; do not apply only the latest migration.
2. No isolated development DB for integration testing; hosted JWT/PostgREST/RLS verification remains unavailable.
3. Previous Vercel deploy hit a rolling 24-hour cap; no deploy retry without approval.
4. Separate Admin prototype is reference only and must not be deployed.


## 2026-11-13 — Universal Buyer Marketplace visibility
- Decision updated: Buyer no longer selects Wholesale/Retail account category; all active Buyers can see both kinds of approved listing.
- Seller still chooses Wholesale or Retail per Product Listing. The chosen type is descriptive/business data, not a visibility entitlement.
- Frontend signup/dashboard/category filters and product detail/query restrictions removed.
- Auth/profile migration sources changed to clear legacy account-level category fields; product read/inquiry/order policies no longer category-gate Buyers; product insert no longer requires Seller account category.
- Buyer Demand routing now matches approved product taxonomy (category/subcategory) and approved Seller business, not account sale-type categories.
- Removed the remaining legacy Buyer-category comparison from the final `private.create_commerce_order` definition in `20261114150000_product_inventory_moq_quantity_pricing.sql`; the per-product sale type still controls Seller-side MOQ/retail rules only.
- Added `supabase/recovery-not-for-deployment/local-setup/20_dual_market_visibility_read_only_verification.sql` and `21_local_marketplace_visibility_fixture.sql`. The fixture creates only a limited local product/business visibility schema on `nexora_test`; it is not the full Marketplace schema and does not represent Demand, Inquiry, Order or listing-edit RPC behavior. The read-only script checks the visibility policy/catalog and safe anon column grants; RPC workflow checks explicitly SKIP in this limited fixture.
- Fixture is guarded against any database other than `nexora_test` and refuses to overwrite existing Marketplace objects. It inserts no sample records. The verification script is read-only and makes no data/schema changes.
- Added `22_run_local_visibility_fixture_termux.sh`, a single Termux runner that downloads cleanup/fixture/verification SQL, checks that only the runner's own connection is open, verifies the local foundation and confirms Marketplace objects are absent before cleanup, then runs cleanup 19, fixture 21 and read-only verification 20 in order. It stops without cleanup if another DB session remains or preflight fails.
- All work is on nexora-development. No migration applied, no hosted DB changed, and no local/browser tests run. The user must run the local fixture and verification script and share the outputs before any PASS can be recorded.


## 2026-11-13 — B-01 Auth trigger hardening
- Updated `20261114210000_porter_public_registration_and_review.sql`: all OAuth identity providers other than email/phone are forced to Buyer, regardless of editable user metadata. Email/phone role metadata is allowlisted to Buyer/Seller/Porter only.
- Trigger always stores `buyer_category = NULL` and `seller_categories = '{}'`; legacy signup metadata is ignored. Buyer/Seller profile is active; Porter profile and review row start pending.
- Revoked `PUBLIC`, `anon`, and `authenticated` EXECUTE on the SECURITY DEFINER Auth trigger function; empty search_path retained.
- Aligned the local-only foundation fixture and smoke tests with universal Buyer visibility/per-product Seller sale type.
- Added local-only patch + regression test: `supabase/recovery-not-for-deployment/local-setup/23_local_buyer_auth_trigger_alignment_tests.sql`. It patches only `nexora_test` fixture and rolls back test users. User has not run it yet; no local test PASS claimed.
- Frontend source review confirms Buyer/Seller/Porter signup choices, Google/Facebook Buyer-only controls, and inactive/suspended account sign-out; pending Porter is shown as pending without dashboard access.
- No migration was applied; no Live Supabase, Production or `main` changed.


## 2026-11-13 — B-03 Buyer Demand source review
- Completed source review of `20261112153000_publish_open_demands_without_buyer_identity.sql`, reconstructed secure-view recovery draft, and final `20261114160000_demand_inbox_quotations_subcategories.sql`.
- Updated `docs/NEXORA_DEMAND_INBOX_QUOTATIONS.md` to remove obsolete Buyer/Seller account-channel matching language; Demand routing is taxonomy + approved business only, irrespective of Wholesale/Retail sale type.
- Added `supabase/recovery-not-for-deployment/local-setup/24_local_buyer_demand_privacy_audit.sql`: read-only, nexora_test-only catalog audit for view privacy, grants, RLS, inbox ownership, quotation insertion, required date and category/subcategory matching. Not run yet; it will SKIP if full Demand schema is absent.
- Source review confirms public Demand view omits Buyer identity/contact, Buyer owner-scoped policies, Seller inbox-only open Demand access, direct inbox writes revoked, quotation insert restricted to own open inbox Demand, and required_date NOT NULL/non-past.
- Buyer quotation acceptance/counter-offer/order conversion remain unimplemented. Real JWT/PostgREST/RLS and browser E2E remain pending.
- No migration applied; no Hosted Supabase, Production or `main` changed.


## 2026-11-13 — B-03 local audit result
- User executed `24_local_buyer_demand_privacy_audit.sql` on `nexora_test`.
- Output: `SKIP: full Marketplace Demand schema is not installed in this local database`; DO completed, transaction rolled back, no database changes.
- This is an expected scope limitation: local fixture 21 creates only business/product visibility tables. It does not create `buyer_demands`, `seller_offers`, `buyer_demand_inbox` or Demand routing functions. Do not mark Demand runtime/security checks as passed.
- Marked the catalog audit execution complete but retained full Demand schema/JWT/PostgREST/browser tests as pending.
- Marked the old Buyer-category-gated dual-market recovery draft SUPERSEDED / DO NOT EXECUTE and corrected stale README descriptions of Wholesale-Only and Buyer category gates.


## 2026-11-13 — B-03 local Demand fixture staged
- Added guarded local-only `25_local_buyer_demand_fixture.sql` for Buyer Demand, Seller Offers, Seller Inbox, public privacy projection, RLS and routing triggers. It requires existing local fixtures 06 + 21 and refuses existing Demand objects.
- Added `26_local_buyer_demand_behavior_tests.sql` with transactional/rollback test data for anonymous privacy, Buyer ownership, Seller Inbox routing, per-product Wholesale/Retail independence, late product routing, quotation permissions, duplicate offers, spoofed Buyer ID and required date.
- Added `27_run_local_buyer_demand_tests_termux.sh` to download immutable SQL versions, preflight the local database, then run fixture 25, audit 24 and behavior tests 26.
- All three are local reconstruction/test assets under `recovery-not-for-deployment`; not migrations and not production schema recovery. No hosted DB touched. User run pending.



## 2026-11-13 — B-03 local Demand behavior verification completed
- User ran Termux runner commit `f202a630dc4e2503daada8ef2130cab90f3b88a6` successfully on `nexora_test`; preflight passed and existing complete local Demand fixture was reused.
- Narrow local policy dependency repair applied: private boolean helpers replace direct policy dependencies on protected `public_businesses.seller_id` and Buyer Demand ownership; authenticated-only helper EXECUTE, anon denied.
- Read-only B-03 catalog audit: 8 PASS.
- Transactional B-03 behavior suite: 12 PASS, covering public Demand privacy, Buyer ownership/isolation, Wholesale + Retail Seller routing, product taxonomy re-match, quotation permission/read isolation, no direct Inbox writes, no duplicate offers, Buyer ID spoof rejection, past required date rejection and RLS/private ACL boundaries.
- Runner final output: `LOCAL B-03 DEMAND BEHAVIOR TESTS PASSED; ALL TEST DATA ROLLED BACK`; all runner steps completed. Test data rolled back.
- B-03 local reconstructed fixture logic is complete for these covered cases. Hosted Supabase JWT/RLS/PostgREST, Data API, Storage/Realtime/Edge Functions and browser E2E remain pending; no production readiness claim.
- No migrations deployed/applied; Live Supabase, Production and `main` untouched.


## 2026-11-13 — Product-linked private Buyer/Seller Conversations staged
- Added staged migration source `supabase/migrations/20261114180000_product_linked_private_conversations.sql`: conversation context fields store Product ID, Seller ID, Product slug/name, first image, and price/currency snapshot. Product context remains on the private conversation row protected by existing conversation participant RLS.
- Updated `private.create_product_inquiry` so an active Buyer can create or reopen the same active Product thread for that Buyer + Seller + Product without duplicate conversations; the invited Seller receives the same conversation and must accept the invitation before messaging/calling, consistent with existing consent rules.
- Updated `chat.js`, `index.html`, and `style.css`: both Buyer and Seller see the same product-linked thread in Chat List with product image, product name, counterpart name, original price snapshot, latest message preview, invitation state, and direct Product Page link. Opening the thread shows a persistent Product Context header and Product Page link.
- The conversation stores a price snapshot for context; it does not overwrite the public Product price. A changed public listing price remains controlled by the Product listing, while past negotiation/order records retain their own agreed terms.
- General non-product conversations remain supported. Existing historical conversations are not guessed or retroactively attached to a Product where no reliable Product ID exists.
- Source-level review only. No local SQL/browser test has been run for this change. New migration is staged only; do not apply until migration history reconciliation and isolated rehearsal. Live Supabase, Production, and `main` remain untouched.

## 2026-11-13 — Cross-department product conversation hardening
- Continued Buyer-first work under the cross-department rule: reviewed the shared communications schema, conversation RLS/consent rules, Seller invitation visibility, Product detail route, and Buyer/Seller chat entry points together.
- Hardened staged migration `20261114180000_product_linked_private_conversations.sql`: optional first inquiry message is now inserted once for a newly created thread; reusing an existing thread does not duplicate the first message.
- Added a database trigger guard so participants cannot rewrite Product/Seller identity or the original Product name/image/slug/price/currency snapshot after the Product conversation is created. Conversation status/title remain outside this protected context.
- Updated `marketplace.js` Product Detail so Buyer can include an optional first inquiry message (max 500 characters) before opening the same private Buyer–Seller Product thread.
- Cross-department impact: Seller receives the same invitation and Product context; Seller must accept before messaging/calling under existing consent policy. Admin has no new access to private chat content. Porter/Delivery is not changed because this package does not create or assign a delivery job.
- No Product public price change; the conversation snapshot is historical context only. Buyer/Seller negotiation currently has separate negotiation records/UI and still needs integration into this same conversation history.
- Source review only; no SQL, local DB, hosted JWT/PostgREST, or browser E2E test was run. Migration history divergence remains a hard deployment blocker. No Live Supabase, Production, DNS or main changed.


## 2026-11-13 — Multilingual Chat foundation (all departments)
- Added staged migration `20261115120000_multilingual_chat_foundation.sql` with per-user `user_language_preferences` and private `message_translations` cache structure. Translation cache is scoped to the same message + conversation + target language; the composite foreign key prevents a translation row from being attached to a different conversation.
- RLS allows each authenticated user to read/change only their own preferred language. Authenticated users can read translations only for conversations where they are accepted participants. There is no direct client insert/update/delete grant on translation rows; a future trusted server-side translation workflow must verify participant access before writing.
- Added preferred Chat language selector to the shared Private Chat workspace, available to Buyer, Seller, Porter and Admin roles, with Bangla, Arabic, English, Chinese, Hindi, Urdu and other language choices. Preference is saved per user.
- Important current behavior: this is architecture + preference persistence only. Messages remain displayed in their original language; automatic text translation, translated Chat List previews, original/translated toggle, and voice/live-call translation are NOT active yet. UI explicitly tells users this.
- Future translation service must preserve original message text, cache translations, handle system/negotiation events and per-recipient language preferences, avoid translating IDs/prices/quantities/currency/product codes, and respect private-chat consent/privacy. Translation provider and cost/privacy review remain open; no paid provider is assumed.
- Cross-department impact: shared chat layer applies uniformly; no role-based access expansion. Admin does not gain private-chat content access. Buyer/Seller negotiations remain in the same conversation; translated negotiation cards must be generated from structured event data, not by mutating order/price values. Porter delivery updates can later use the same per-recipient translation path.
- Source-level review only. No SQL was run and no browser/hosted RLS test was performed. Migration history divergence remains a deployment blocker; Live Supabase, Production, DNS and `main` were not changed.


## 2026-11-13 — Multilingual translation engine architecture and privacy gate
- Added `docs/NEXORA_MULTILINGUAL_CHAT_TRANSLATION_ARCHITECTURE.md` defining recipient-specific translation, immutable originals, accepted-participant authorization, trusted server-side cache writes, fallback behavior, structured commercial-event handling and staged rollout.
- Confirmed no translation provider is selected/configured. Automatic translation stays disabled; no private message is sent to a third-party service by this work.
- LibreTranslate/Argos is recorded only as a self-hostable evaluation candidate, not as a selected or guaranteed zero-cost provider. Hosting costs, language-pair coverage (especially Bangla↔Arabic), quality, licensing, consent and cross-border data handling require evaluation.
- The browser must never hold provider/API secrets. Future endpoint must validate caller JWT + accepted conversation membership before provider access and trusted cache writes; no message body/token/secret logging.
- First release scope is text-only. Attachments and voice/video are excluded. Negotiation/system messages must use typed templates so prices, quantities, currency, IDs and dates remain unchanged.
- No Edge Function, provider configuration, consent switch, SQL execution, hosted test or browser E2E was added/run in this architecture package. Migration history divergence remains a deployment blocker; Live Supabase, Production, DNS and `main` untouched.


## 2026-11-13 — Adjacent staged negotiation SQL syntax correction
- During the multilingual architecture source recheck, found that `private.append_product_negotiation_chat_event` in `20261115110000_product_price_negotiation.sql` still had an invalid single-$ PL/pgSQL body delimiter.
- Corrected it to a matching `$$ ... $$` dollar-quoted body and re-fetched the branch file. Static delimiter check now reports no malformed single-dollar function block and a valid matching double-dollar block.
- This is source inspection only; the migration was not executed and no SQL behavior is claimed as tested.

## 2026-11-13 — Translation provider evaluation gate
- Verified current LibreTranslate/Argos package listings: Bengali and Arabic are each listed with English in both directions; the published package list does not establish a direct Bangla ↔ Arabic package. LibreTranslate documents intermediate-language pivoting, usually through English, but quality is unverified.
- Reviewed Meta NLLB-200 distilled 600M model card: CC-BY-NC 4.0 and research-only / not-production guidance make it unsuitable for NEXORA's commercial production path without separate compatible licensing. It is not selected.
- Updated `docs/NEXORA_MULTILINGUAL_CHAT_TRANSLATION_ARCHITECTURE.md` with evidence, privacy boundaries and a human-reviewed pilot quality gate.
- Decision: no provider selected, no Edge Function or provider adapter enabled, no private messages sent to external services. Self-hosted Argos remains a conditional proof-of-concept candidate only; hosting is not free by default.
- No SQL, provider quality test, Edge Function deployment, browser test or hosted test was run. Live Supabase, Production, DNS and `main` untouched.

## 2026-11-13 — Bengali ↔ English translation candidate review
- Confirmed Argos package availability in both directions (bn→en 67 MB; en→bn 68 MB, package 1.9). No reliable model-specific public quality benchmark for those exact Argos packages was found; package availability is not quality proof.
- Identified AI4Bharat IndicTrans2 as a stronger first Bengali-English pilot candidate: official project supports `ben_Beng` + `eng_Latn` both directions and supplies FLORES/IN22 evaluation tooling with chrF++, BLEU and COMET. The English→Indic distilled 200M model card shows MIT; exact license/revision for the paired Indic→English checkpoint must be confirmed before deployment.
- Decision: benchmark IndicTrans2 and Argos on the same consented bilingual test set before choosing. No model was run in this environment, no translation quality is claimed as tested, and no engine is enabled.
- Hosting/RAM/latency/throughput, exact paired-model licenses, privacy/consent and server security remain approval gates. IndicTrans2 covers Indic languages, not Arabic or all global languages.


## 2026-11-13 — Bengali ↔ English reproducible pilot corpus prepared
- Added `docs/NEXORA_BN_EN_PILOT_CORPUS.md` with 24 synthetic parallel cases, testable in both directions, plus reviewer protocol, protected-token checks and blank results matrix.
- Covers commercial chat risks: negation, price/quantity, currency, date/time, units, delivery instructions, IDs, and mixed Bangla-English terms.
- References are explicitly seed references requiring two independent bilingual reviewers before scoring; 24 cases/direction is screening only, not statistically conclusive.
- No private conversation data used. No model inference/download was executed in this environment; no scores or winner claimed. Automatic translation remains disabled; no SQL, Supabase, Edge Function or deployment change.


## 2026-11-13 — Bengali-English local inference runner and exact model access review
- Confirmed upstream MIT license labels for both official IndicTrans2 distilled checkpoints; both are gated on Hugging Face and require operator acceptance. Exact immutable revisions are required by the runner. Current repository file listing shows model.safetensors around 1.1 GB despite the 200M checkpoint label.
- Confirmed Argos direct bn→en and en→bn package index entries at package 1.9 / Argos 1.9.0. Package index metadata does not disclose artifact license; commercial-use rights remain unverified.
- Added `scripts/translation_pilot/run_bn_en_pilot.py` and `docs/NEXORA_BN_EN_MODEL_RUNBOOK.md` for local offline inference, raw CSV capture and per-case latency. The runner does not calculate a winner; human review remains mandatory.
- Runtime not executed: this environment has no configured model runtime/weights and cannot provide a verified local inference host. No private chat content used; no model quality score claimed; no paid compute started.
- No SQL, migration execution, Supabase, Edge Function, Live, Production, DNS or `main` change. Translation remains disabled.


## 2026-11-13 — Colab notebook prepared for actual model inference
- Added `notebooks/NEXORA_BN_EN_Model_Pilot.ipynb` for phone-friendly browser execution on a temporary Colab runtime.
- Notebook clones only the development branch, prompts for Hugging Face token securely, resolves immutable checkpoint SHAs per session, runs the same synthetic corpus, and downloads raw CSV outputs.
- Google Colab free compute is not guaranteed and limits vary; no paid runtime was started. Notebook has not been executed; no model outputs/quality score are claimed.
- Private NEXORA chat data must never be uploaded. Automatic translation remains disabled.


## 2026-11-14 — Delivery strategy and Buyer Demand quotation workflow hardening

- Product strategy confirmed: build and validate the Bangladesh-market version first; defer international expansion until the local product is functional and gaining usage. Prepare to seek investment only after the software is standing and there is evidence of market demand. Keep the architecture extensible, but do not delay the Bangladesh launch for international-only features.
- Current product-direction clarification: do not make wholesale-vs-retail account separation a visibility gate. All users should be able to see marketplace items; Sellers decide their own product price and quantity terms. Older per-product market-category behavior must be reconciled against this latest decision before further UI/schema work; do not silently reintroduce account-level separation.
- Reviewed Buyer Demand quotation negotiation SQL and the matching Buyer/Seller UI handlers.
- Fixed NULL negotiation-action validation and added active Buyer/assigned Seller checks to Buyer Demand order transitions.
- When a Seller accepts a Buyer counter-offer, the generated order now starts in accepted state, records accepted_at and emits an accepted order event. Buyer acceptance of a Seller proposal still creates a pending order for Seller confirmation.
- Updated `docs/NEXORA_BUYER_DEMAND_PROGRESS.md` with source-review findings and outstanding verification gates.
- Changes are staged only on `nexora-development`. No SQL migration was executed; no hosted Supabase, Live data, Production, `main`, DNS or deployment was changed.
- Next: prepare isolated full-schema migration rehearsal and focused tests for Buyer acceptance, Seller acceptance, counter-offer turn-taking, rejection, expired offers, inactive participants, order transitions, RLS and browser flows. Do not mark this workflow Done until those tests pass.


## 2026-11-14 — Negotiation rejection guard and isolated audit preparation

- Added server-side turn-taking validation for rejection: only the participant receiving the other party's latest proposal can reject. The UI is not the security boundary.
- Added a read-only, `nexora_test`-guarded installed-contract audit at `supabase/recovery-not-for-deployment/local-setup/29_local_buyer_demand_order_contract_audit.sql`; documented when it can safely run.
- Re-fetched the changed migration and audit file from GitHub to confirm the source changes are present.
- Full isolated migration rehearsal is not safe yet: no trusted original foundation schema export/baseline is present in the branch, and current local fixtures are reconstructed rather than production-equivalent. The new audit will SKIP if its prerequisite workflow is not installed; it does not create schema or data.
- No SQL was executed and no Live Supabase, Production, `main`, DNS or deployment was changed. Workflow remains pending actual local PostgreSQL behavior tests, hosted JWT/PostgREST/RLS tests and browser E2E.

## 2026-11-14 — Live schema recovery evidence

- Read-only inspection of the connected NEXORA Supabase project confirmed PostgreSQL 17.11, 22 public relations (20 tables + 2 views), RLS enabled on all 20 tables, five non-internal public triggers, 37 public/private functions and 24 live migration-history entries.
- Captured exact catalog metadata for eight foundational tables and ten related functions in supabase/recovery-not-for-deployment/live-schema-evidence/20261114_foundation_catalog_snapshot.json. This includes columns/defaults, constraints, indexes, policies, triggers and selected function definitions; no user rows were exported.
- This narrows the baseline recovery blocker but does not equal a full schema-only dump or original historical SQL. All ACL/default privileges, complete Auth/Storage customizations, and remaining functions still need a complete export and review.
- Next: obtain a schema-only export locally, preserve credentials only on the user's device, compare live objects against branch migrations, then rehearse selected migrations only on a disposable local database.
- No Live Supabase schema/data/history changed; no migration executed; no main, Production, DNS or deployment changed.

- Extended the metadata evidence snapshot with all 22 public relations, the 37-function public/private inventory, 12 custom auth/storage triggers (including their function definitions), and four auth/storage policies. Ten selected Foundation function definitions are fully captured; a complete raw schema-only export and full ACL/default-privilege capture remain pending.


## 2026-11-14 — Android-only recovery path

- User confirmed Android/Termux is the only available device. Supabase CLI and Docker are not installed; Docker CLI alone is not a viable substitute for a Docker Engine.
- Continued with connected Supabase MCP read-only catalog queries instead of asking the user to install unsupported tooling. The evidence JSON now includes the complete public/private relation and function inventories, view definitions, policy/trigger counts, and the complete 24-entry live migration version/name list.
- Latest evidence update committed on `nexora-development`: `15480737ada1eca9b37e11a2f9ee1abc11a328fb`.
- The connected catalog confirms 22 public relations (20 tables + 2 views), 37 public/private functions, 78 public RLS policies, 4 storage policies, 5 public triggers, 1 auth trigger, and 11 storage triggers. This is catalog evidence only, not a complete executable schema dump.
- Next: capture remaining exact definitions and ACL/default-privilege/extension metadata through read-only catalog queries in bounded batches, then compare with branch migrations. No private user rows or message content will be queried.
- No Live Supabase schema/data/history changed; no SQL migration executed; no main, Production, DNS or deployment changed.


- Further Android-only catalog recovery completed through read-only queries: all 37 public/private function definitions captured; 578 table-grant rows, 68 routine-grant rows, 136 default-privilege ACL entries, and five extension/version records captured in the evidence JSON. Snapshot re-fetched and parsed successfully after commit; current file blob SHA `9ca8701bcc5e448d32ea98651321fca5cb7698a`.
- This substantially improves the recoverable baseline, but it is still not a complete `pg_dump --schema-only`: complete DDL for all Auth/Storage internals, role attributes/membership, event triggers, publications/replication settings and object-level restore ordering still require separate review. No user rows were queried or exported.
