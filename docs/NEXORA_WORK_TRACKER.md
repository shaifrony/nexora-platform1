# NEXORA Work Tracker

Updated: 2026-11-14 (latest Migration reconciliation refresh)

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
| Unified Marketplace alignment | Source-level refactor complete; SQL/browser runtime verification pending | No Wholesale/Retail product sale-category split. All users can browse all approved products; Seller sets price and quantity terms. Buyer Demand routing uses product category/subcategory and approved Seller/business state. Logistics delivery modes remain separate. Not deployed; migration history remains unreconciled. |
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


- Continued Android-only read-only recovery: captured role attributes, role memberships, schema ACLs, seven event-trigger registrations, and exact security options/definitions for both public views. Stored in the evidence JSON.
- Reviewed all 17 SECURITY DEFINER functions in public/private that are executable by API roles: none is executable by anon or PUBLIC; all 17 are executable by authenticated. Their definitions were stored for explicit authorization review. This is not by itself a confirmed vulnerability: functions are in the private schema, and bodies include identity/permission checks; next review must verify exposed-schema configuration and each function's call path before changing anything.
- Evidence update commit: `5fc5dc852e0ad244d98d332418550930075d5e92`. All operations were catalog-only SELECTs; no user rows or message bodies accessed.


- 2026-11-14 API/RLS privacy review: the only public relation with anon SELECT grant is `public_buyer_demands`; its view is `security_invoker=true` and exposes no `buyer_id` column. The underlying `buyer_demands` table contains `buyer_id`, but anon has no SELECT grant on that base table. Public base tables all have RLS enabled; no public table was found with RLS enabled but zero policies. Private schema USAGE is denied to anon and granted to authenticated. This is a positive structural result, not an end-to-end HTTP penetration test.
- The effective PostgREST exposed-schema setting could not be read from SQL session/catalog context (`current_setting('pgrst.db_schemas', true)` returned NULL; no role/database override found). Therefore the exact Dashboard Data API Exposed Schemas list remains unverified and must not be guessed. 
- Supabase Security Advisor: leaked-password protection disabled (WARN). Performance Advisor: 6 unindexed FKs (INFO), 20 unused-index candidates (INFO), 8 multiple-permissive-policy warnings (WARN). No index/policy changes made; unused-index signals are not enough to drop indexes, and permissive policies need semantic consolidation review before editing.
- API/RLS snapshot committed: `ada6cca54175796d388f15e05bf5234048ee67ea`.


- Profile/business guard trigger source review captured four exact trigger-function definitions. Structural checks show buyer profile updates are restricted to own full_name, seller/porter profile changes require admin approval, and role/account_status are protected against self-change. Business public projection is synchronized only when approval_status='approved'. One compatibility cleanup candidate: `public.guard_profile_updates()` uses deprecated `auth.role()`; replace only in a reviewed development migration after validating equivalent service-role detection and tests. No Live changes made.
- Product/business Data API visibility: anon has SELECT only on `public_buyer_demands`; products and public_businesses are not granted anon SELECT, while authenticated users have SELECT. This may mean logged-out visitors cannot browse Marketplace through Data API; flag for product decision and later implementation review, not a confirmed defect until the intended guest-browsing behavior is specified.


### Correction and migration reconciliation — 2026-11-14

**Correction to the prior anon-access note:** the earlier check looked only at table-level grants and therefore understated public read access. Live catalog confirms anon has column-level SELECT grants on selected safe columns of `products` and `public_businesses`, alongside the public Buyer Demand view. Products have an anon SELECT RLS policy requiring `listing_status='approved'` and `is_public_business(business_id)`; public business projection has an anon SELECT policy and contains only business_id, display_name, country, city. Product anon columns exclude seller_id, reviewed_by, reviewed_at and admin_note. Product public fields are: id, business_id, product_code, slug, product_name, category, image_urls, description, origin, specifications_quality, price, currency, listing_status, created_at, price_unit, minimum_order_quantity, price_negotiable. This supports guest Marketplace browsing at the SQL grant/RLS level; HTTP-level testing is still pending.

**Migration inventory (read-only):** At snapshot time there were 40 branch SQL files and 39 unique versions. After the audited archive cleanup in the later entry below, the active migration directory has 38 files and 37 unique versions; 24 Live history entries; 13 version/name pairs match; 25 branch-only files (24 unique versions); 11 Live-only entries. Two exact duplicate-content copies (51801 and 52010) have been moved byte-for-byte outside the active migration directory; the canonical Live-recorded versions 51711 and 51906 remain active. Two different migrations still share version 20261114180000 (`product_linked_private_conversations` and `unified_delivery_jobs_assignment`). This version collision is a migration-runner blocker: assign unique versions using the approved CLI workflow before any migration execution. Do not delete/rewrite applied migration history based on this inventory alone.

The 11 Live-only entries have current catalog evidence for several effects: product pricing columns exist; approved-product anon policy exists; selected anon column grants exist; safe public-business anon policy/projection exists; public business helper has private SECURITY DEFINER and public SECURITY INVOKER wrappers; profile account_status permits cancelled; AAL2 checks are present in the private admin helper functions; Buyer Demand public view omits buyer_id and is security_invoker. The remaining SQL effect equivalence is not proven solely by object-name presence.

Evidence JSON updated at `supabase/recovery-not-for-deployment/live-schema-evidence/20261114_foundation_catalog_snapshot.json`, blob SHA `bfcf517535e4746d1b458c3ad9b0881bc4ad84c4`. No Live writes or migration execution.


### Migration dependency/security audit — 2026-11-14

**Static fixes applied on `nexora-development` only:**
1. `20261114200000_centralized_officer_account_management.sql`: reject NULL `p_action` explicitly (previously NULL could fall through to the deactivate branch); accumulate `is_sensitive` across all selected permissions (previously a later non-sensitive permission could reset the flag and bypass the mandatory reason check).
2. `20261114180000_unified_delivery_jobs_assignment.sql`: independent-provider vehicle assignment now also requires `transport_vehicles.is_available=true`, not just approved status and provider ownership.

**Confirmed dependency order:** transport provider/vehicle model (131800) precedes delivery assignment system (132200); Delivery Network partner/staff tables (141700), Commerce Orders (141400), and delivery job base tables (132200) precede unified assignment (141800); delivery tracking (141900) follows unified assignment. Product-linked conversations (141800) depend on the private communications tables (120508/120509) and marketplace products (120503), all earlier. The two 141800 migrations still share the same version and remain blocked from migration-runner use.

**Product decision mismatch to resolve before migration rehearsal:** `20261113235900_product_market_category.sql` introduces a per-product `wholesale/retail` market category, and `20261114150000_product_inventory_moq_quantity_pricing.sql` enforces Retail MOQ=1. This conflicts with the user's later decision that products are not separated into wholesale/retail visibility groups and all users can see all products; Sellers set their own price/quantity. These category-specific schema/UI rules must be removed or redesigned before staging. The `delivery_mode` / logistics `service_modes` retail/wholesale values are separate logistics concepts and are not changed by this audit.

**Correction:** the Porter migration's `profiles_market_categories_check` is not a new category restriction; the same constraint already exists in 132300 to keep deprecated legacy profile category fields empty. This is intentional and not a new conflict.

**Migration version resolution remains blocked:** local Supabase CLI and Docker Engine are unavailable on the Android-only workflow. Supabase guidance requires creating new migration files with `supabase migration new`; do not hand-invent a replacement timestamp or rename the colliding files through GitHub as a workaround. The two 141800 files remain unchanged in name. Also two exact duplicate-content pairs remain for explicit cleanup after a CLI-backed migration plan is available.

No Live database writes, migration execution, or user-row queries. The two source fixes are static edits only; SQL runtime tests and isolated disposable-database rehearsal remain pending.


- Additional UI/schema mismatch confirmed by branch source inspection: `marketplace.js` and `index.html` still expose Wholesale/Retail badges, discovery cards, filters, product insert/edit `market_category` payloads, and Retail-specific price/MOQ copy. This is inconsistent with the user's latest unified Marketplace decision. The previous Business Profile/Product Form progress note describing “Wholesale-only” is historical and superseded. Frontend and staged migration alignment remains a separate pending change; no UI/schema removal was made in this audit.


### Unified Marketplace refactor — implementation staged 2026-11-14

**Completed on `nexora-development`:**
- Removed the per-product Wholesale/Retail sale-type field from Marketplace product queries, product detail, grid cards, Buyer product discovery, Seller product search/filter, product create/edit payloads, and listing history labels.
- Replaced the separate Wholesale/Retail homepage discovery cards with one Marketplace card; updated hero, Buyer and Seller copy. Seller product filter now uses product text and approval status only.
- Removed Buyer/Seller profile sale-category columns and their registration payloads; Porter registration now creates a profile without those deprecated fields.
- Removed sale-category validation and updates from Admin listing-edit/review/history functions.
- Removed Retail-only MOQ=1 enforcement. MOQ and quantity-tier pricing remain Seller-defined; stock reservation and inventory safeguards remain.
- Buyer Demand matching now uses product category/subcategory and approved Seller/business state, without sale-type segmentation. The product matching index and approved-product routing trigger no longer depend on `market_category`.
- Retained Retail/Wholesale terms only where they describe separate transport/logistics delivery modes, not product Marketplace visibility.

**Static source verification:** fetched the updated `marketplace.js`, `index.html`, and all affected migration files from GitHub. The two frontend files contain zero `market_category` references; the complete 40-file migration directory was checked in batches and now contains zero active/runtime references to `market_category`, `buyer_category`, or `seller_categories`. The only remaining legacy profile-field mentions are three explicit cleanup statements in the profile migration (drop the old constraint, drop the two columns, and drop the old policy).

**Not yet verified:** JavaScript browser/runtime behavior, SQL parsing/runtime behavior, PostgREST/RLS behavior, Buyer Demand routing E2E, and Seller listing edit/review E2E. No local PostgreSQL/Supabase runtime is available in this Android-only workflow. Do not mark the refactor production-ready until isolated database and browser tests pass.

No Live Supabase SQL was executed. No user rows were read or changed. No `main`, Production, DNS or deployment changes.


**Additional migration source repair during this refactor:** `20261114120000_listing_edit_review_workflow.sql` contained several appended duplicate/incomplete function fragments after its first complete transaction, plus a malformed currency regex. Kept the first complete implementation (including active Seller, approved Business Profile, Admin permission and audit checks), removed the orphaned duplicate tail, and repaired the currency/price validation lines. Re-fetched source now has one `BEGIN`/one `COMMIT`, four function definitions, balanced `$$` and `$rpc$` delimiters, and no product sale-category references. This is static source validation only; no PostgreSQL parser/runtime test has run.


**Disposable database availability check (2026-11-14):** no existing Supabase development branches are present. A new isolated Supabase development branch is available as a testing route, but the current quote is **US$0.01344 per hour**. It has not been created. Explicit user approval of this recurring cost is required before provisioning; do not use the Live project for migration rehearsal. Android/Termux still has no local Supabase CLI or Docker Engine, so CLI-generated unique migration timestamps and a local disposable PostgreSQL rehearsal remain blocked until an approved test environment is available.


### Migration version reconciliation — refreshed read-only audit (2026-11-14)

**Freshly verified branch and Live ledger:**
- `nexora-development` HEAD: `8aba6fb3c4c827492aef5abe0bf395e73eaaa2cf`.
- Migration directory: 40 SQL files, 39 unique versions.
- Connected Live Supabase migration history: 24 entries.
- 13 version/name pairs match; 27 branch-only files represent 26 unique versions; 11 Live-only history entries.
- The fresh Live ledger was read through the Supabase migration-list metadata endpoint; no schema/data query or write was performed.

**Exact duplicate-content pairs (Git blob SHA verified):**
- `20261112051711_update_conversation_timestamp_on_message.sql` and `20261112051801_update_conversation_timestamp_on_message.sql` share blob `2e053e7bf7b47c089e70218c2b2397686cf153dc`. Live history contains 51711, not 51801.
- `20261112051906_fix_conversation_insert_returning_visibility.sql` and `20261112052010_fix_conversation_insert_returning_visibility.sql` share blob `bd3d3d323c81d9d265f927ffa8affca4eeb1d974`. Live history contains 51906, not 52010.
- These are redundant branch-only copies by exact content hash, but no file was deleted or moved. Preserve until a canonical migration-source/archive strategy is reviewed.

**Version collision:**
- `20261114180000_product_linked_private_conversations.sql`
- `20261114180000_unified_delivery_jobs_assignment.sql`
- They are different SQL blobs and different features sharing one version. Both remain in place; do not run the migration sequence while this collision exists.

**Timestamp mismatch:**
- Branch has `20261112153000_publish_open_demands_without_buyer_identity.sql`; Live history records `20261112153453_publish_open_demands_without_buyer_identity`.
- Catalog evidence supports a similar current public Buyer Demand projection, but does not prove exact SQL equivalence or original source identity. Do not rename the branch file or fabricate historical identity.

**Decision / safe boundary:** no migration filename has been renamed, no duplicate file deleted, no history row repaired, and no SQL executed. Supabase CLI is not available in the Android/Termux environment; per Supabase guidance, a replacement migration must be generated by `supabase migration new`, not by hand-inventing a timestamp. Continue with source-only evidence comparison and static validation until a supported CLI/runtime becomes available. Disposable Supabase branch remains declined due recurring cost.



## 2026-11-14 — Live-only migration effect recheck

- Re-read current `nexora-development` branch and confirmed HEAD before continuing.
- Latest verified branch HEAD before this tracker update: `5ebc62e1bc10a51794480f093ea9166bf2f06db4` (Migration Recovery Plan refresh).
- Re-read Live Supabase migration history: 24 entries; 40 branch SQL files; 39 unique versions; 13 matching version/name pairs; 27 branch-only files (26 unique versions); 11 Live-only entries.
- Re-ran read-only catalog metadata checks for product pricing columns/constraints, product public-read policy, anonymous column grants, public business projection, helper function security modes, cancelled profile status, AAL2 admin helper definitions, and Buyer Demand privacy projection.
- Current schema evidence supports the expected result-level behavior of all 11 Live-only migration names at the object/policy/grant level. This does not recover original SQL bodies or prove complete semantic equivalence; details and limits are recorded in `docs/NEXORA_MIGRATION_RECOVERY_PLAN.md` section 17.
- Confirmed `public_businesses` is a table with RLS and column-level anon grants; `public_buyer_demands` is a `security_invoker=true` view that omits `buyer_id`; anon has no SELECT grant on base `buyer_demands`.
- Public `is_public_business(uuid)` is SECURITY INVOKER with empty search_path; private counterpart is SECURITY DEFINER. Admin private helper functions inspected enforce JWT AAL2 and active staff/profile status.
- No private user rows, messages, Auth identities or Storage contents queried.

**Migration safety remains blocked:** the two different files `20261114180000_product_linked_private_conversations.sql` and `20261114180000_unified_delivery_jobs_assignment.sql` still share one version. Two further pairs are byte-identical duplicates. No files were renamed/deleted, no history was repaired, no migration was run, and no paid Development Branch was created.

**Verification limits:** metadata-only catalog inspection and source/document static review. No PostgreSQL parser, local DB, disposable DB, PostgREST/JWT or browser E2E test has run. Continue with branch-only migration effect/dependency audit; do not execute the migration directory until the version collision is repaired through a supported CLI-generated workflow.


## 2026-11-14 — Branch-only migration object audit

- Compared the source declarations of the branch-only feature migrations with the Live public relation inventory (metadata only).
- Confirmed Live has 20 public tables and 2 views. Core Marketplace, Buyer Demand, Seller Offers, conversations and Admin foundation relations exist.
- Confirmed the following feature tables are absent from Live metadata: `transport_providers`, `transport_vehicles`, `delivery_jobs`, `delivery_job_events`, `service_listings`, `listing_edit_requests`, `listing_edit_request_events`, `review_purchase_eligibility`, `listing_reviews`, `commerce_orders`, `commerce_order_events`, `buyer_demand_inbox`, `delivery_network_partners`, `delivery_network_staff`, `delivery_job_assignment_history`, `delivery_tracking_events`, `porter_account_reviews`, `seller_offer_negotiations`, `product_price_negotiations`, `product_price_negotiation_events`, `user_language_preferences`, and `message_translations`.
- Confirmed `20261113100000_create_porter_delivery_workflow.sql` is explicitly marked SUPERSEDED/no-op and must never be executed.
- Confirmed `20261113235900_product_market_category.sql` currently contains no product sale-category column change despite its filename; it changes public product/business policies and grants and replaces Product Inquiry RPC logic. Live already has overlapping visibility policies and an earlier Product Inquiry RPC, so this file is blocked from blind replay.
- Confirmed the `nexora-listing-images` Storage bucket was not found in Storage bucket metadata; its migration also depends on absent `service_listings`.
- Confirmed product-linked conversation migration extends an existing Live `conversations` table, while delivery migrations depend on absent delivery base tables. These are partial/new feature groups and remain unexecuted.
- Detailed per-file classification and limits are recorded in Recovery Plan section 18.

**Current status:** branch-only migration inventory and initial object mapping complete; exact function/trigger/policy/grant replacement audit remains. The `20261114180000` version collision still blocks all migration runners. No file renamed/deleted, no SQL run, no Live writes, no user data queried, no paid Development Branch created.


## 2026-11-14 — Product conversation migration effect audit

- Verified branch HEAD before audit: `3dc6b5be89254b978e864d23fbf16dedd11beef5`.
- Compared `20261114180000_product_linked_private_conversations.sql` with Live catalog metadata.
- Live `conversations` has no `context_%` columns, matching context constraints or product-context indexes.
- Live `private.create_product_inquiry(uuid,text)` is the earlier generic-thread implementation; the newer product context snapshot, active-Seller check, duplicate-thread guard and optional first message in branch source are not present in Live.
- Function privilege metadata: anon cannot execute either wrapper/private implementation; authenticated can execute. Private function is SECURITY DEFINER with empty search_path; public wrapper is SECURITY INVOKER.
- Classified the product-linked conversation migration as pending on Live (not already applied). Full comparison and limits are in Recovery Plan section 18.
- Collision at migration version `20261114180000` remains unresolved; do not run migrations or edit version filenames until a supported CLI-generated repair is available.
- No Live writes or private user/message data reads. No SQL runtime, PostgreSQL parser, JWT/RLS or E2E tests.

Documentation commit for Recovery Plan section 18: `1aee6768a2c46df557d9a5c6f45a005b480072ad`.


## 2026-11-14 — Delivery Network and Porter approval Live catalog audit

- Reverified `nexora-development` HEAD before audit: `4ecaf5223b27338e7c2b301e3e529e8b2073ace7`.
- Live catalog has no `transport_providers`, `transport_vehicles`, `delivery_jobs`, or `delivery_tracking_events` relations. These related delivery migrations remain pending.
- Provider/vehicle review RPCs, unified network job/assignment RPCs, delivery tracking status RPC, `porter_account_reviews`, and `review_porter_account` are absent from Live.
- Live profiles role constraint already includes Porter; Live role_requests requested_role constraint also includes Porter. This is only partial structural alignment and does not prove the new Porter registration + Admin review workflow is installed.
- The old individual-Porter delivery migration is a documented no-op/superseded file; do not apply it.
- Dependency sequence recorded in Recovery Plan section 19: provider/vehicle base → provider/vehicle review → delivery job base → unified network assignment → delivery tracking; Porter account approval is a distinct activation gate.
- Shared version `20261114180000` remains unresolved and blocks migration execution.
- No private data or Auth identities queried; no Live writes, migration execution or history repair. No PostgreSQL/JWT/RLS/E2E tests.

Recovery Plan section 19 commit: `cab90a9f2d52a910632ce0cfc16be1d772bc58c7`.


## 2026-11-14 — Commerce and Demand Live catalog audit

- Live base relations `buyer_demands` and `seller_offers` exist with RLS enabled.
- Live `commerce_orders`, `commerce_order_events`, `buyer_demand_inbox`, `product_price_negotiations`, and `product_price_negotiation_events` were not found.
- Commerce order create/transition and product price negotiation RPCs were not found.
- Demand inbox routing triggers and the newer subcategory/quotation extension columns were not found in the inspected metadata.
- Classified the Commerce Order, Demand Inbox/quotation extension, demand negotiation/order conversion and product price negotiation features as pending on Live. Detailed limits and dependencies recorded in Recovery Plan section 20.
- Required-by date remains a product requirement and must be preserved in Buyer Demand; its Live column was not established by this catalog check.
- No private data reads, Live writes, migration execution, or history repair. No runtime SQL, JWT/RLS or E2E tests.

Recovery Plan section 20 commit: `4b1d65a197f0415489672401aee2ad66ddf84f89`.


## 2026-11-14 — Remaining staged feature catalog audit

- Services Marketplace relation `service_listings` is absent from Live; service image bucket, `image_urls`, Storage policies and dependent seller image grant are also absent.
- Listing edit request table/functions and listing edit history events/triggers are absent.
- Verified purchase review table, private eligibility table and review RPCs are absent.
- Product commercial pricing fields `price_unit`, `minimum_order_quantity`, `price_negotiable` already exist in Live; staged stock tracking fields, trigger, inventory RPC and stock index were not found. Inventory migration classified partially represented.
- Admin base relations exist in Live, but staged officer structure columns (`position_key`, `reports_to_user_id`, `staff_email`) and officer management RPC are absent. Centralized Officer Management classified partially represented; must be additive and preserve existing Admin data.
- Multilingual Chat preference and translation tables are absent. Feature remains suspended by product decision; do not enable production translation or use private messages as test corpus.
- Full findings, dependencies and evidence limits recorded in Recovery Plan section 21.
- No Live writes, migration execution, private data or Storage object reads; no runtime SQL/RLS/Storage/E2E tests.

Recovery Plan section 21 commit: `3e66c30d4653d7ab2c963449adc713f97dc36f2a`.


## 2026-11-14 — Consolidated migration dependency map

- Added Recovery Plan section 22, mapping the ordered dependencies for core marketplace/security, product inquiry, services/media, listing governance/history, verified reviews, inventory, Buyer Demand/quotations, commerce/negotiation, delivery network, Porter activation, centralized officer management and suspended multilingual chat.
- Recorded hard execution gates: version collision, exact duplicate SQL pairs, Live-only security outcomes, CLI/runtime requirement, disposable DB rehearsal and explicit production approval.
- No migration filenames or migration-history entries changed. No migration runner invoked. No Live schema/data/DNS/paid-service changes.
- Current environment still lacks Supabase CLI, Docker Engine and local PostgreSQL; therefore no SQL runtime/parser or disposable database test is claimed.

Recovery Plan section 22 commit: `6d8f983211927625f532d5984c655194534fc7d5`.


## 2026-11-14 — Buyer Demand focused source audit and date guard

- Rechecked the Buyer Demand frontend path and staged SQL contract: required-by date form → Buyer Demand creation/dashboard/public projection → Seller Inbox/quotation → Buyer/Seller counter-offers → source-linked Commerce Order → Buyer/Seller order transitions.
- Confirmed Buyer/Seller action wiring uses `respond_to_demand_offer`; server-side checks cover active Buyer/Seller role, ownership/assignment, latest proposal turn, positive terms, offer expiry and open Demand. Order status RPC applies role/ownership and state-transition checks.
- Confirmed Buyer Demand public projection does not request Buyer identity/contact fields, and the required date is mapped to `required_date` and displayed in Buyer/Seller views.
- Added client-side local-date minimum and past-date rejection to the Demand form; DB constraint remains authoritative. Code commit: `90b923e63877f30952296f768e805ed7c93132ff`.
- Buyer Demand progress note commit: `42f27d2d6ed61693235c54d2645204027573597a`.
- Limits: source inspection only. No browser/JS runtime, SQL runtime, disposable DB, hosted JWT/PostgREST/RLS or E2E verification. No SQL migration executed; Live Supabase, Production, `main`, DNS and paid services unchanged.
- Found and fixed a Buyer/Seller order-summary mismatch: both order cards now display the delivery-inclusive `grand_total` and show the delivery-charge breakdown when non-zero, instead of displaying only `total_price`. Code commit: `5b64818391d022688c85cdd17c5d3c0092191d62`; Buyer progress note: `97b5150a5599ae2402834e50fd11620df165e5b9`.
- Repaired Buyer/Seller order-card string concatenation after the delivery-total display update. V8 syntax-only compilation of the full `marketplace.js` source and both order-card render expressions passed; no code execution/browser test is implied. Repair commit: `d839546f4a8cf602ab2da350f3989e5e8a8848ca`; Buyer progress validation note: `351bb9b9f170c24d92c39101f43d627353615197`.
- Synthetic logic checks passed for the required-by date guard (same day/future allowed; past/empty rejected) and delivery-inclusive order total calculations (including zero delivery and fractional quantities). Isolated checks only; no browser/database integration test. Buyer progress note commit: `6df04075fd73c555b92482ebe5285c2d39473968`.


## 2026-11-14 — Buyer quotation/order checklist reconciliation
- Reconciled `docs/NEXORA_BUYER_COMPLETION_CHECKLIST.md` with the current staged implementation: Buyer/Seller quotation accept/counter/reject, server-side negotiation turn checks, offer expiry/ownership checks, source-linked Buyer Demand order conversion and guarded order transitions are present in source; the older checklist wording that called this workflow unimplemented is superseded.
- Buyer/Seller order cards display delivery-inclusive `grand_total` with a separate delivery-charge breakdown when non-zero. Syntax-only JavaScript and isolated required-date/order-total checks are documented; they do not establish SQL runtime, JWT/PostgREST/RLS, concurrency or browser E2E correctness.
- Full isolated database rehearsal remains blocked by migration-history/version collision and absence of a trusted complete baseline; local reconstructed fixtures do not contain the full Commerce/Negotiation schema. No SQL or hosted migration executed; no Live Supabase, Production, `main`, DNS or deployment changed.
- Checklist correction commit: `415df2d77fc0609f203f90153adc5eba0e82dbc8`.


## 2026-11-14 — Buyer workflow static verification (not runtime test)
- Reviewed Buyer/Seller quotation UI and `20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql`: source includes active-role and participant checks, open-demand and expiry checks, negotiation turn-taking, quantity/price validation, unique source-offer order index, participant-scoped negotiation-history RLS, generated delivery-inclusive order total, and guarded Buyer/Seller order transitions.
- Corrected Buyer acceptance toast to state the newly created order awaits Seller confirmation; code commit `db377422c117cab4bf9acf851da9e1407e21cb08`.
- Verification is static source review only. No SQL runtime, disposable DB, hosted JWT/PostgREST/RLS, concurrency or browser E2E tests ran. Existing GitHub Pages workflow success is not a Buyer test suite. Migration collision and absent trusted complete local DB baseline remain blockers. No Live/Production/main changes.


## 2026-11-14 — Migration version collision source audit
- Re-fetched and inspected both complete SQL files sharing version `20261114180000`; confirmed distinct Git blob SHAs and distinct feature scopes (product-linked private conversations vs unified delivery assignment).
- Product inquiry migration depends on existing conversation/participant/message and product/business/profile foundations; Live catalog audit shows its new product-context fields/indexes and RPC behavior are pending.
- Unified delivery assignment depends on delivery job/event base, provider/vehicle and network partner/staff foundations, Admin AAL2 permission helpers and Commerce Orders. The required delivery/commerce relations are absent from the inspected Live catalog; this file cannot be treated as independently runnable.
- The dependency audit does not prove which migration should retain the shared version or justify a replacement timestamp. No timestamp invented; no migration renamed, deleted, rewritten or executed.
- Reviewed current Supabase CLI v3 migration guidance: migration files should be generated with `supabase migration new`; v3 database commands target local by default and hosted changes require explicit `--remote` plus confirmation. CLI/runtime remains unavailable here, so no migration repair command is possible or safe.
- Reconfirmed the two exact duplicate-content pairs remain unchanged pending full ledger reconciliation and a documented archive disposition.
- Recovery Plan section 22.4 records the detailed source/dependency audit. Verification remains static source + previously inspected catalog metadata only; no SQL runtime, disposable DB, JWT/RLS, PostgREST or E2E tests. No Live writes, private data reads, paid services, `main`, Production or DNS changes.

## 2026-11-14 — Exact duplicate migration copies archived and active inventory reconciled
- Re-fetched all four duplicate-pair migration paths from `nexora-development` and verified the later copies were byte-identical to the canonical earlier versions by Git blob SHA.
- Live migration history already records the canonical earlier versions 51711 and 51906, not the redundant later versions 51801 and 52010.
- Copied both redundant files without changing their bytes into `supabase/recovery-not-for-deployment/archived-duplicate-migrations/`; fetched both archives and verified exact blob SHA equality before deleting the redundant copies from `supabase/migrations/`.
- Canonical active migrations 51711 and 51906 were not modified. No SQL was executed and no migration history was changed.
- Fresh GitHub directory listing confirms 38 active SQL migration files. With one remaining shared-version collision, there are 37 unique versions. Reconciled counts: 13 matching version/name pairs; 25 branch-only files (24 unique versions); 11 Live-only entries.
- Remaining hard blocker: two different migrations still share `20261114180000`. No filename/timestamp guessed; no migration runner used. Supabase CLI and local DB runtime remain unavailable, so this collision still blocks all migration execution.
- Updated Recovery Plan section 22.5 and earlier inventory notes. No Live schema/data/history, private user data, `main`, Production, DNS or paid service changed. No PostgreSQL runtime, disposable DB, RLS/JWT or E2E test claimed.

## 2026-11-14 — Remaining migration collision: safe resolution decision

- Re-read the connected Live migration history (metadata only): 24 entries; neither migration versioned `20261114180000` is applied.
- Dependency-based preferred order: retain `20261114180000_unified_delivery_jobs_assignment.sql` because delivery tracking version `20261114190000` follows it; move only the product-linked conversation migration to a fresh CLI-generated version.
- The replacement must be created with `supabase migration new product_linked_private_conversations`, then checked to ensure its generated version is unique and sorts after `20261114190000`. If not, stop; do not hand-author a timestamp or use undocumented flags.
- No file was renamed or changed: local Supabase CLI and PostgreSQL/Supabase runtime remain unavailable in the Android/Termux workflow. No SQL, Live history, or schema write was performed.
- Next gate: obtain a supported CLI environment, create and verify the replacement filename, then run the complete sequence only in a no-cost disposable local database. Production remains blocked.


## 2026-11-14 — Product conversation deletion/FK consistency fix

- Static review found that `conversations.context_product_id` uses `ON DELETE SET NULL`, while the immutable-context trigger rejected every change to that field. This combination would block deletion of a referenced product because the FK's automatic NULL update would be rejected by the trigger.
- Updated `private.guard_product_conversation_context()` in `20261114180000_product_linked_private_conversations.sql` to permit only the one-way transition from a non-NULL product ID to NULL. It continues to reject replacing the product ID or changing any other product/seller/price snapshot field.
- Development-branch commit: `86ae1648ebcf675ca9b09b6901f5b5431a7286ee`. The updated file was fetched back and the exact trigger condition verified.
- This is source-level reasoning and re-fetch verification only; no SQL parser/runtime or deletion integration test was run. No Live database or migration history was changed.


## 2026-11-14 — Preserve Porter role through transport foundation migration

- Static dependency review found that `20261113180000_transport_provider_vehicle_model.sql` temporarily narrowed `profiles.role` to buyer/seller/admin and `role_requests.requested_role` to seller only, even though the established NEXORA account model includes Porter and the later Porter review migration restores the role.
- That intermediate constraint could reject an existing Porter profile or Porter role request during a full migration replay. Updated the transport foundation migration to preserve `porter` in both checks; Porter activation remains controlled by the later Admin-reviewed Porter workflow.
- Development-branch commit: `ee408d6685ac9495b65ced871379dd550f35016b`. The migration was fetched back and the exact replacement constraints verified.
- Source-level correction only; no SQL was executed and no Live data/schema was changed.


## 2026-11-14 — Close direct Admin UPDATE bypass in transport review tables

- Continued the transport migration security review and found that broad Admin UPDATE RLS policies on `transport_providers` and `transport_vehicles` would allow direct table updates, bypassing the dedicated review RPCs' AAL2 check and audit-log insertion.
- Removed those two direct Admin UPDATE policies from `20261113180000_transport_provider_vehicle_model.sql`. Owner updates remain available under owner-scoped policies and trigger-protected review fields; Admin review remains through the audited AAL2-gated SECURITY DEFINER review functions.
- Development-branch commit: `6a64e18f41299353d2e574674a213fbda4583eeb`. Re-fetched the migration and verified the direct Admin UPDATE policies are absent.
- Source-level only; no database migration or SQL execution performed.


## 2026-11-14 — Delivery Network static security and input validation fixes

- Transport Provider/Vehicle update guards no longer treat `logistics.assign` permission alone as a bypass. Ordinary `authenticated` table updates remain owner-scoped and cannot change review fields; privileged review RPC execution is distinguished by its SECURITY DEFINER execution context. This closes the case where an Admin who also owns a provider record could use direct table UPDATE to bypass the AAL2/audit RPC.
- Removed the previous direct Admin UPDATE RLS policies from the transport foundation migration; verified both guards and policies after re-fetch.
- Hardened `create_delivery_network_job` server-side validation for pickup/delivery city and country, contact name/phone lengths, external reference, special-instruction length, and deadline ordering. These are validated before INSERT instead of relying on lower-level NOT NULL/CHECK failures.
- Development-branch commits: `eeb31c514cc6061bc965456c7299b1c95a0c7a4c` and `493302e7f4cf79b6ffc4ae5be0f6a16d5c94d9c6`. Both changed files were re-fetched and exact blob SHAs verified.
- Static/source review only. No SQL runtime, disposable DB, hosted write, or browser test was run.
- Supabase CLI v3 changelog checked: database commands default to local; hosted changes require explicit `--remote` and confirmation/`--yes` for unattended execution. No hosted migration command was run.


- Additional guard hardening: Provider and Vehicle owner UPDATEs now also cannot alter primary IDs or original `created_at` timestamps. Re-fetched the migration and verified both immutable identity checks. Commit: `dedcd9b818e129635897a2c27a1b748dbc3bef2c`.


## 2026-11-14 — Prevent vehicle double-booking

- Static concurrency review found that the same approved/available vehicle could be assigned to multiple active delivery jobs because availability was checked without checking existing assignments.
- Added active-job conflict checks to all three assignment paths: legacy job creation, legacy reassignment, and unified Provider assignment. Each path locks the selected vehicle row `FOR UPDATE` before checking active jobs, serializing competing assignments for the same vehicle.
- Jobs in requested/assigned/accepted/picked_up/in_transit/out_for_delivery/partially_delivered/disputed states block reuse; completed, returned, failed, and cancelled work does not.
- Commits: `5db82acaa711096c3666b145b004286db9518e1e` and `63f3d467ad4bd6b7e5ef1ce02e0d747f79df86cf`. Both migration files re-fetched; guard presence verified.
- Source-level review only; no SQL concurrency test or database execution is available in the current environment.


- Compatibility fix: the original Admin Provider/Vehicle assignment RPC inserts into `delivery_jobs` after the later unified migration has removed the `assigned_at` default. Its INSERT now explicitly sets `assigned_at=now()`, preserving the assignment timestamp for legacy Admin-created jobs. Verified by re-fetching the migration. Commit: `7f998239a335784e361765bc9c1e0429adb09d0b`.


## 2026-11-14 — Buyer Demand total-price rounding correction

- Static review found that a total-price Seller quotation could lose cents when divided into a two-decimal unit price before Order conversion (example: BDT 100 / 3 units became BDT 99.99).
- Added `commerce_orders.source_offer_total` to the staged Buyer Demand conversion migration. Buyer Demand Order `grand_total` now uses the exact agreed goods subtotal plus delivery charge; other order types retain the quantity × unit-price fallback.
- Original total-price quotes are prorated against the original quoted availability and rounded once to currency precision. Negotiated per-unit counter-offers continue to calculate subtotal from quantity × unit price.
- Updated Buyer and Seller order SELECTs and delivery-charge breakdowns to display the exact source subtotal when present.
- Commits: migration `84d97644765dbcc08b63f3309a0d193f6d2f3826`; frontend `db24dec3314dee3b5b26f9b25e8bd229009ba1ec`; Buyer progress note `3404a66e7dfa528bdc93d3f77df67a45d0eb2501`.
- Re-fetched both code files and verified the exact-total column, generated-total formula, proportional calculation, INSERT mapping, both order queries and both UI breakdowns. Arithmetic spot-checks: 100/3 at 3 units = 100.00; 2 units = 66.67; +5 delivery = 105.00.
- Static verification only. No SQL execution, disposable DB, browser or order E2E test. This does not clear the outstanding migration version collision or release gate.

- Follow-up UI correction: untouched `price_basis='total'` quotations now display the exact total on Buyer and Seller quotation cards; order cards use the exact agreed subtotal rather than implying the rounded derived unit price multiplied by quantity is authoritative. Frontend commit: `db7368a9b05ffcedcebdaef69c0360271ca37f5b`; Buyer progress addendum: `9cef760d1b864beead8c2a6d069249d0f8ceb92b`.

- Migration clarity follow-up: documented `source_offer_total` as the authoritative goods subtotal for Buyer Demand quotation orders; the legacy `total_price` remains the quantity × rounded-unit-price projection. Migration comment commit: `34a650cc702304f3d7f35b80d6e89dfc1d8a5a33`.


## 2026-11-14 — Follow-up Buyer Demand quotation/order source audit

- Re-fetched the staged Buyer Demand quotation migration and current `marketplace.js` from `nexora-development` and reviewed the total-price quotation, Buyer response, Seller counter-response, order creation, and Buyer/Seller order-card paths.
- Confirmed the staged flow preserves an original total-price quotation as an authoritative `source_offer_total`, prorates it against the original offered availability when the Buyer accepts a smaller quantity, and uses negotiated quantity × unit price after a counter-offer. The Buyer and Seller order queries both select the exact subtotal and generated `grand_total`.
- Confirmed the Seller acceptance UI is shown for Buyer counter-offers and routes through the same server RPC; the SQL checks the latest negotiation actor before accepting. This is source-level review only, not proof of runtime behavior.
- No additional source change was justified by this pass. The migration version collision at `20261114180000` remains the top blocker; do not hand-invent a replacement timestamp. No SQL was executed, no Disposable Database was created, and no hosted schema/data was changed.
- Supabase CLI v3 changelog/docs rechecked on 2026-11-14: database commands default to local; hosted changes require explicit remote targeting and confirmation. Sources: Supabase CLI v3 migration guide (updated 2026-11-03) and changelog entry (2026-11-04).


## 2026-11-14 — Migration CLI runner feasibility check

- Re-read the installed Supabase skill and rechecked the official Supabase CLI v3 changelog and migration guide. The CLI migration command must generate the new version; no timestamp was hand-invented.
- Tested a no-secret, branch-scoped GitHub Actions helper workflow intended only to install Supabase CLI and run `supabase migration new product_linked_private_conversations`. The workflow file was committed temporarily to `nexora-development`, but GitHub did not create a run for it. The repository's existing Pages workflow runs from the default-branch workflow configuration; a workflow introduced only on the non-default development branch cannot be used as an executable runner in this repository's current configuration.
- Removed the temporary helper workflow immediately; no persistent workflow/configuration change remains. Removal commit: `4a24c1ef59884a7c8988058aa7618056c26d7325`. Temporary workflow commit: `0b87d56aed277270826180b7b34d4946826a292d`.
- Confirmed current branch head after cleanup and retained all existing source files. No changes to `main`, no paid service, no Development Branch, no DB connection, no SQL execution, no migration-history repair, and no Production/Live changes.
- Result: a GitHub-hosted CLI runner is not currently available without changing the default branch or obtaining another supported CLI runtime. Both are outside current authorization/constraints. Therefore the duplicate version `20261114180000` remains unresolved; do not manually rename or invent a replacement timestamp. Next safe path is to use an already-authorized supported CLI runner/runtime that can execute `supabase migration new` without touching a database, then transfer the CLI-generated filename and proceed with source-only rename.


## 2026-11-14 — Additional isolated CLI-runtime check

- Rechecked the development branch head before work: `8ecb39a223d7d1b309d8d1e69a70a6114019bd59`. Re-fetched both colliding migration files and confirmed they remain distinct SQL bodies; the Product Conversation migration is still the only candidate for a later CLI-generated version, while unified delivery assignment retains the earlier slot needed by the downstream delivery-tracking migration.
- Tested the available isolated execution container for a no-cost, database-free Supabase CLI path. It is Linux x86_64 with Node/npm, but has no Supabase CLI, Docker Engine or PostgreSQL executable; npm cache contains no Supabase CLI package. Outbound DNS resolution for GitHub fails (`curl: (6) Could not resolve host: github.com`), so the official CLI binary/package cannot be fetched in this runtime.
- This is an execution-environment limitation, not a migration error. No timestamp was guessed, no migration file was renamed, and no DB connection, SQL execution, migration-history change, paid resource, `main`, Production or Live change occurred.
- The remaining version collision is still an explicit hard stop for migration runners. Continue only when a supported Supabase CLI runtime is available; run `supabase migration new product_linked_private_conversations`, verify its generated version sorts after `20261114190000`, then perform the source move atomically on this branch. Disposable-database rehearsal remains the next gate after version uniqueness is restored.
