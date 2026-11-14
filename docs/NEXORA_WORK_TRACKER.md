# NEXORA Work Tracker

Updated: 2026-11-14 (latest Migration reconciliation refresh)

Latest marketplace progress: [Business Profile & Product Form Progress](NEXORA_BUSINESS_PROFILE_AND_PRODUCT_FORM_PROGRESS.md). Buyer Demand review: [NEXORA Buyer Demand Progress](NEXORA_BUYER_DEMAND_PROGRESS.md). Buyer phase checklist: [NEXORA Buyer Completion Checklist](NEXORA_BUYER_COMPLETION_CHECKLIST.md).

Review RPC local validation closeout: [NEXORA_REVIEW_RPC_LOCAL_VALIDATION_CLOSEOUT.md](NEXORA_REVIEW_RPC_LOCAL_VALIDATION_CLOSEOUT.md). Base and extended local logic suites plus the focused two-session order-acceptance race passed on disposable PostgreSQL 17. The later review-column privacy candidate #31/#32 is a separate, not-yet-executed gate. Hosted deployment remains blocked.

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
| Review RPC local logic validation | Done (local only) | Base/extended local suites and two-session order-acceptance race passed on disposable PostgreSQL 17; local superuser caveat documented; hosted deployment not approved |
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
- [x] Focused two-session order-acceptance concurrency check passed on disposable PostgreSQL 17; retain as a release regression test.
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


## 2026-11-14 — User-authorized continuation: migration-version step reattempt

- User explicitly authorized continuing in the established order. Re-read the installed Supabase skill and checked the current official CLI v3 migration guide/changelog. The guide confirms CLI v3 database commands target local by default and hosted changes require explicit remote targeting/confirmation; no hosted command was needed or run for this filename-generation step.
- Rechecked the available execution container: Linux x86_64, Node v22.16.0 and npm 10.9.2 are present. No `supabase`, Docker or `psql` executable exists anywhere in the searched executable paths; npm cache has no Supabase CLI package. Attempting to reach the official GitHub release endpoint fails DNS resolution (`curl: (6) Could not resolve host: github.com`).
- The connected Supabase tools expose hosted migration listing/application, but do not expose the local CLI command `supabase migration new`; applying a hosted migration is not a substitute and is expressly out of scope.
- Therefore no supported CLI-generated version can be obtained in this turn. Both `20261114180000` migrations remain untouched. No hand-generated timestamp, source rename, database connection, SQL execution, migration-history repair, paid service, `main`, Production or Live change was made.
- Sequence gate remains: obtain a supported CLI runtime → run `supabase migration new product_linked_private_conversations` → verify the generated version is unique and sorts after `20261114190000` → atomically move the unchanged SQL body on `nexora-development` → verify inventory → only then begin disposable-database rehearsal. No later stage was started because the current gate is unresolved.
- Official references checked: Supabase CLI v3 migration guide (updated 2026-11-03) and CLI v3 breaking-change changelog (2026-11-04).


## 2026-11-14 — Supabase CLI runtime obtained through zero-cost Hobby sandbox

- Found an authorized Vercel Hobby project linked to this repository. The current public Vercel pricing page lists 5 Sandbox active-CPU hours and 420 GB-hours of provisioned memory included on Hobby; Hobby has usage caps and does not permit paid overage purchases. Used a single ephemeral, non-persistent 1-vCPU / 2-GB sandbox with a 10-minute hard timeout; it ran for 49.607 seconds and used 8.345 seconds of active CPU. The session was explicitly stopped; no persistent sandbox, snapshot, public port, or paid plan was created.
- Cloned only the public `nexora-development` branch and successfully ran Supabase CLI v3.1.0 via `npx supabase@latest`. The official CLI command `supabase migration new product_linked_private_conversations` succeeded and generated `20261113202704_product_linked_private_conversations.sql`.
- The generated timestamp sorts **before** the existing `20261114190000_delivery_tracking_status_history.sql` and therefore cannot safely host the Product Conversation migration, whose dependencies require it to sort after delivery tracking. The CLI-generated empty file and CLI temporary metadata were removed from the disposable clone; Git status returned to clean. No generated file was copied into the repository, no timestamp was edited, and no migration SQL was moved.
- This resolves the missing-CLI-runtime blocker, but not the timestamp-order blocker. A CLI-generated version after `20261114190000` is still required; do not alter timezone/system clock or hand-edit a version to force it. No database connection, SQL execution, migration-history repair, Supabase Development Branch, Production/Live, or `main` change occurred.
- Next safe action: obtain a later genuine CLI-generated timestamp (after the current time passes the existing 20261114190000 sequence point), then atomically move the unchanged Product Conversation SQL body, verify unique ordered inventory, and only then start the disposable-database rehearsal.


## 2026-11-14 — Product Conversation migration collision resolution

- Re-read the Supabase skill and current CLI v3 changelog/migration guidance. Supabase CLI v3.1.0 ran in a short-lived, non-persistent Vercel Hobby sandbox; the official `supabase migration new product_linked_private_conversations` command generated `20261113203025_product_linked_private_conversations.sql`. The sandbox was explicitly stopped.
- Read-only Supabase `list_migrations` returned 24 applied Live entries, latest `20261112162234`; neither migration using version `20261114180000` is applied. No remote history repair is needed or authorized.
- Re-audited all 199 lines of the Product Conversation SQL and its prerequisites. It uses `public.products`, `public.conversations`, `public.conversation_participants`, `public.messages`, profile fields, and the prior `private.create_product_inquiry` function. These are established by migrations through `20261112162234`. It does not reference Delivery Network, unified delivery assignment, or delivery tracking objects. The previous requirement to place it after `20261114190000` was incorrect.
- The generated version `20261113203025` sorts after all direct prerequisites and the latest Live history entry, and before the unrelated delivery-assignment migration `20261113220000`. The Product Conversation SQL body is transferred byte-for-byte to the generated CLI path; the old duplicate-version path is removed in the same commit. The unified delivery assignment remains at `20261114180000` and tracking remains at `20261114190000`.
- This is a source/version-inventory repair only. No migration was applied, no hosted DB/history/schema/data was changed, and no runtime or disposable-database test is claimed. Next gate: verify the active migration inventory has unique versions, then prepare a disposable database rehearsal.


## 2026-11-14 — Disposable local migration replay and functional validation

- Rechecked the Supabase CLI v3 skill/changelog. Supabase CLI v3.1.0 ran in a short-lived, non-persistent Vercel Hobby Sandbox using the native Linux runtime (no Docker). Auth and Storage services plus the local PostgreSQL service were enabled; REST, Realtime, Functions, Studio, Mail, Analytics and Pooler were excluded. The local stack and its synthetic data were explicitly stopped and destroyed after testing.
- Reconstructed a **test-only baseline** from read-only Live schema catalog evidence because several prerequisite objects are present in Live but their original migrations are absent from this branch. The local-only baseline included the `rls_auto_enable()` event-trigger function and `ensure_rls` trigger; profiles/admin metadata tables and helper functions; role/profile-change request tables; the admin audit-log table; and five non-personal Admin department catalog rows. No Live user rows, authentication records, private messages, calls, or storage objects were queried or copied. This is not a byte-for-byte replay of the 11 Live-only migrations; it is an evidence-based prerequisite harness for validating this branch's migration chain.
- Applied all **38 active branch migrations** successfully to the disposable local database, from `20261112045441` through `20261115120000`. Local migration history contained 38 applied versions. The active GitHub inventory also contains 38 SQL files and 38 unique versions; no duplicate version remains.
- Supabase CLI `db lint --level warning --fail-on error` completed with **No schema errors found** after the test baseline included the Live-only `public.admin_audit_logs` relation referenced by Admin/Delivery functions.
- Catalog validation found 40 public tables and zero public tables without RLS enabled. Core product, conversation, negotiation, commerce-order and delivery-tracking tables/functions were present.
- Synthetic Buyer/Seller RLS checks: each authenticated account saw only its own profile (one row each); a Seller with a pending conversation invitation saw zero messages, while the accepted Buyer saw the conversation message. A synthetic Buyer demand inserted under the authenticated Buyer role; the public demand view returned it to `anon`, while the view exposed zero Buyer ID/contact columns.
- Synthetic product-price negotiation test: Buyer started an offer, Seller countered, Buyer accepted; the product-linked conversation retained `context_type='product'` and the product ID; an order was created in pending state and inventory reservation increased. Seller then accepted the order, marked it ready, and Buyer confirmed completion; the order reached `completed` with its transition timestamps populated.
- During the disposable test, the Product Conversation migration was deliberately marked reverted locally after later versions had already been applied, then reapplied using the CLI's documented `--include-all` path for out-of-order pending migrations. This was confined to the disposable DB. The current Live migration-history maximum remains `20261112162234`, earlier than the CLI-generated `20261113203025`; no Live repair or write was performed.
- Source defects found by replay were corrected on `nexora-development`: literal newline in `20261114130000_listing_edit_history.sql`; malformed dollar-quote delimiters in `20261114130100_verified_purchase_reviews.sql`; and duplicated appended transaction fragments in `20261115110000_product_price_negotiation.sql`. The latter retains the first complete implementation, including Product Conversation and Chat event integration.
- Remaining test scope: no Browser E2E, PostgREST/HTTP JWT authorization test, actual Storage upload/download, WebRTC call, concurrency/load test, or production migration was run. No Live schema/data/history, `main`, Production, DNS, or paid service was changed.


## 2026-11-14 — Buyer Demand privacy hardening and negotiation E2E

- A targeted privacy review found that the Seller's matched-demand RLS policy allowed selecting the entire `buyer_demands` row, including `buyer_id`. The public view omitted the identity, but the underlying authenticated table path still exposed that column.
- Fixed `20261114160000_demand_inbox_quotations_subcategories.sql`: revoked table-level SELECT on `public.buyer_demands` from `authenticated` and granted SELECT only on safe demand columns. INSERT and UPDATE privileges remain; row ownership/matching is still enforced by RLS.
- Updated Buyer Dashboard queries in `marketplace.js` to stop filtering on `buyer_id`; they now rely on the existing owner RLS policy and select only safe columns. Demand status updates similarly rely on the owner RLS policy.
- Replayed all 38 migrations in a fresh disposable Native Runtime database. Local history: 38 applied, latest `20261115120000`. Latest catalog check: 41 public tables, zero without RLS. `db lint --level warning --fail-on error`: no schema errors.
- Synthetic role tests passed: Buyer insert and Buyer Dashboard read both succeeded; Seller inbox matched one approved-product demand; Seller could read its safe demand fields but direct SELECT of `buyer_id` was denied; `anon` could read the public demand projection, which exposes zero Buyer identity/contact columns. An unmatched demand was invisible to the Seller and Seller quotation INSERT was denied by RLS.
- Synthetic quotation flow passed: Seller submitted a matched quotation; Buyer countered; Seller countered; Buyer accepted. The resulting Commerce Order was 40 units × BDT 77 (goods subtotal BDT 3,080) + BDT 50 delivery = BDT 3,130. Seller accepted and marked ready; Buyer confirmed completion; all three order timestamps were populated and status became `completed`.
- Buyer closed the Demand using the revised ID-only update path; the Seller's open-demand query then returned zero rows.
- Only synthetic records were used in the disposable database. No Live user rows, auth identities, private messages, calls or storage objects were queried. The local stack and test data were stopped and destroyed.
- This closes the database-level Buyer Demand privacy/quotation/order test gate, but not full product acceptance: Browser E2E, PostgREST/HTTP JWT authorization, real Storage transfer, WebRTC, concurrency/load and broader Porter/Admin role tests remain outstanding.


## 2026-11-14 — Porter/Admin and Delivery Network disposable runtime validation

- Repeated the 38-migration local replay with a test-only baseline; latest history 38 at `20261115120000`, 41 public tables, zero without RLS, and `db lint` reported no schema errors.
- Recreated the existing Live Auth `on_auth_user_created` trigger in the disposable baseline; no Live user data was copied.
- Verified synthetic Porter signup → pending review → AAL2 Admin approval → active Porter. AAL1 Admin could not approve a second pending Porter; public `role=admin` signup was blocked.
- Verified approved Porter independent-provider application and AAL2 Admin approval.
- Verified Admin-managed NEXORA Team partner/staff/job creation and assignment, followed by five successful tracking transitions ending in `delivered`.
- All synthetic test records and local database were destroyed after the run. No Live mutation, `main`, Production or DNS change occurred.
- Remaining: independent-provider self-service tracking, external courier integration, receipt confirmation/proof, payment/settlement, dispute/return, PostgREST/HTTP and browser E2E, and concurrency/load testing.


## 2026-11-14 — Independent Provider self-service tracking validated

- In a fresh disposable Supabase CLI v3.1.0 Native Runtime database, all 38 branch migrations applied through `20261115120000`; 41 public tables were checked and zero lacked RLS; `db lint --level warning --fail-on error` reported no schema errors.
- The local-only baseline recreated the existing Live Auth `on_auth_user_created` trigger. No Live auth identities or user rows were copied.
- Synthetic Porter signup → pending review → AAL2 Admin approval → active profile succeeded. The Porter then created a `transport_providers` application; AAL2 Admin approval changed it from pending to approved.
- Admin created a Delivery Job and assigned it to the approved independent Provider. The Provider account itself (AAL1, not Admin) successfully submitted each allowed status transition: `accepted → picked_up → in_transit → out_for_delivery → delivered`.
- The final job status was `delivered`; five append-only tracking events were stored with `actor_type='independent_provider'`. The assigned Provider could read all five events under its RLS policy.
- The separate Admin-managed NEXORA Team path was also validated in an earlier disposable run: approved team partner, staff roster, job assignment and five Admin-authored tracking transitions through delivered.
- Disposable stack and all synthetic records were stopped and destroyed. No Live database mutation, `main`, Production, DNS or paid resource was used.
- Remaining release work: approved-vehicle assignment/availability, courier-partner operational tracking, delivery receipt OTP/digital proof, delivery charge/payment/settlement, disputes/returns, external courier APIs/webhooks, PostgREST/HTTP and browser/device E2E, and concurrency/load testing.


## 2026-11-14 — Frontend role-routing and form smoke checks

- Ran `node --check` on all seven project JavaScript files: all passed.
- Parsed the current `index.html` with JSDOM: 13 forms, no duplicate element IDs, 68 buttons, and no empty/unlabelled buttons.
- Public signup role selector contains exactly Buyer, Seller and Porter.
- Product Listing form remains limited to the agreed initial information: product name, category, images, description, origin, specifications/quality, and price/currency. No MOQ, stock, supply-capacity or delivery fields were added to that initial form.
- Buyer Demand required-date control is required; the Marketplace runtime sets its minimum to the local current date.
- Executed auth/Marketplace/Porter/Delivery/Chat scripts in JSDOM with a synthetic Supabase client stub. Synthetic Buyer and Seller loaded their own dashboards; Seller Business Profile card was created. Pending Porter stayed out of the Porter workspace; active Porter reached it. Admin at AAL1 remained blocked from Administration; synthetic active super-admin at AAL2 reached it.
- Attempted cross-role dashboard navigation (Buyer→Seller, Seller→Buyer, Porter→Buyer, AAL1 Admin→Administration); each unauthorized route was redirected to Account. No application JS exceptions occurred in the guarded run.
- **Test boundary:** this was DOM/runtime smoke testing with a mocked Supabase client, not a real browser engine or authenticated Supabase API. It does not verify hosted JWT/PostgREST/RLS, Storage, Realtime, WebRTC, device behavior, or concurrency. Prior disposable SQL workflow results remain separately documented above.
- No source code, hosted database, user data, `main`, Production, DNS or paid resource was changed in this check.


## 2026-11-14 — Private communications security source audit

- Reviewed `chat.js` and the private communications schema/RLS migrations on `nexora-development` at commit `4c8bea266ad1d7122d21a5e0e3dca585066e8fd2`.
- `node --check chat.js` passed.
- Source inspection confirms RLS is enabled on conversations, participants, messages, attachments, call sessions and call signals; public/anon table privileges are revoked. The private chat Storage bucket is configured as non-public with a 20 MB limit and an explicit MIME allowlist. Storage object reads/inserts are scoped to accepted conversation participants; signed URLs expire after one hour.
- Message send/read, attachment metadata, call creation and call signaling policies require accepted conversation membership. Admin has no explicit read policy on private conversation tables. Incoming-call Realtime subscription filters by the authenticated recipient ID.
- **Hardening follow-up before release:** the current `calls_participant_update` policy permits any accepted participant to update call status/timestamps, and column grants expose those fields without a database-enforced state-transition/actor rule. Review whether this should be narrowed to caller/callee-specific transitions or moved behind a guarded RPC. The participant self-status update policy also permits an already accepted participant to transition to declined/left; confirm the intended lifecycle.
- **Test boundary:** this is a source-level security audit plus JavaScript syntax check only. No disposable Postgres policy execution, Storage upload/download, Realtime delivery, WebRTC media, browser/device E2E, JWT/PostgREST or concurrency test was run in this pass. No private messages, calls, attachments, user rows or Live data were read.
- No application code, hosted database, `main`, Production, DNS or paid service was changed.


## 2026-11-14 — Private Chat/File Sharing hardening; Calling paused

- Per user direction, Audio/Video Calling is paused for now, not removed. The calling UI is hidden, incoming-call Realtime subscription is disabled, and the start-call handler reports that calling is paused. Existing calling code, tables and migrations are retained for later reactivation.
- Hardened chat attachment upload flow: capture the target conversation before upload; reject zero-byte and over-20-MB files; sanitize and cap stored file names; reject completion if the user switches conversations during upload; and clean up a partially-created message and uploaded object when later upload steps fail.
- `node --check chat.js` and `git diff --check` passed in the disposable Vercel Sandbox before applying the same source patch to this branch.
- No Live/hosted database, private message, user row, Storage object, `main`, Production or DNS was accessed or changed. No migration was added or modified.
- **Remaining validation:** disposable Postgres/PostgREST RLS test for Chat/File, Storage upload/download and signed URL behavior, browser/device E2E, and file cleanup behavior against actual Storage. Calling remains explicitly out of scope until user reactivates it.


## 2026-11-14 — Disposable Chat / File privacy verification

- Replayed all **38 active migrations** on an isolated Vercel Sandbox Supabase native PostgreSQL stack; latest applied version: `20261115120000`. The disposable database used the repository's explicitly synthetic local foundation fixture plus local-only compatibility helpers; it is not a faithful copy of hosted schema or data. The fixture's admin authorization helper stubs always return false.
- `supabase db lint --level warning --fail-on error`: **No schema errors found**. `node --check chat.js` and `git diff --check`: passed.
- RLS is enabled on `conversations`, `conversation_participants`, `messages`, and `message_attachments`.
- Synthetic Buyer created a conversation and invited a Seller. Buyer could read/send messages. Pending invitee, unrelated Buyer and Admin test identity could not read message content. Pending invitee could not send a message or read attachment metadata / Storage object rows; attempted pending upload was rejected with RLS SQLSTATE `42501`.
- After Seller accepted the invitation, Seller could read and send messages and insert attachment metadata. Accepted Buyer and Seller could read the synthetic Storage object row; unrelated Buyer and Admin test identity saw zero rows. Spoofing `uploaded_by` in attachment metadata was rejected with `42501`.
- Anonymous role saw zero rows in the private chat bucket and could not query `public.messages` (permission denied). Bucket metadata confirmed `public=false`, 20 MiB limit and the configured MIME allowlist (JPEG, PNG, WebP, PDF, TXT, DOCX, XLSX).
- Supabase Storage prevents direct SQL deletion from `storage.objects` (its guard instructs callers to use the Storage API). This pass tested PostgreSQL RLS and a synthetic Storage object row, **not** actual binary upload/download, signed-URL issuance/expiry, Storage API deletion, browser/device E2E or Realtime delivery. Those remain pending. File cleanup behavior after real Storage API failure also remains pending.
- No hosted/Live database, user rows, real auth identities, private messages, real attachments, calls, `main`, Production, DNS or paid service was accessed or changed. All test identities/content were synthetic. Disposable native stack and Vercel Sandbox were stopped after the run.
- Audio/Video Calling remains paused and untouched; its earlier source-audit findings are deferred until the user authorizes reactivation.

## 2026-11-14 — Actual Chat Storage API verification

- Recreated a short-lived Vercel Hobby Sandbox and Supabase CLI v3.1.0 native stack. Runtime versions observed: PostgreSQL 17.11, Auth v2.197.0 and Storage v1.90.1. Storage 1.81.0 included a security fix for signed resumable/TUS upload authorization; the test stack was newer than that release. **TUS/resumable upload itself was not exercised.**
- Replayed all **38 active migrations** successfully on the disposable database, through `20261115120000`. The active repository inventory contained 38 SQL files and 38 unique versions. The local foundation remained synthetic and evidence-based, not a copy of hosted rows/schema. Only the sandbox clone received temporary Supabase CLI configuration and test-only baseline helpers; no migration or application source file was changed.
- Created four synthetic users through the local Supabase Auth API (Buyer, Seller, unrelated Buyer and pending invitee), then used their real local Auth access tokens against the actual Storage HTTP API.
- **Binary transfer:** accepted Seller upload returned HTTP 200; accepted Buyer download returned HTTP 200 and the downloaded bytes matched the uploaded SHA-256.
- **Access control:** unrelated Buyer and pending invitee could neither upload nor download (HTTP 400). Both were also denied signed-URL creation (HTTP 400).
- **Signed URLs:** accepted Buyer created the app's 3,600-second signed URL (HTTP 200); the URL downloaded the file without an Authorization header (HTTP 200). A 1-second URL was rejected after 2.3 seconds (HTTP 400), confirming expiry enforcement.
- **Deletion/cleanup:** an accepted non-uploader Buyer's DELETE request returned HTTP 200 but the object remained readable; this is an RLS no-op, so HTTP 200 alone must not be interpreted as deletion. The uploader Seller's Storage API delete removed the object (subsequent read HTTP 400) and invalidated the previously issued signed URL (HTTP 400). A separate simulated later-step failure cleanup passed: upload HTTP 200, Storage API remove HTTP 200, subsequent read HTTP 400.
- **Bucket restrictions:** `application/octet-stream` was rejected (HTTP 400); a 20 MiB + 1 byte upload was rejected (HTTP 400). Catalog confirmed `nexora-chat-files` is private, limited to 20,971,520 bytes, with JPEG/PNG/WebP/PDF/TXT/DOCX/XLSX allowlist. `storage.objects` RLS was enabled and the expected participant-read, participant-insert and uploader-delete policies were present. Final query found **zero remaining test objects** for the synthetic conversation.
- `supabase db lint --level warning --fail-on error`: **No schema errors found**. `node --check chat.js` and `git diff --check`: passed.
- **Remaining limits:** standard binary Storage upload/download and signed URL behavior were tested; TUS/resumable uploads, full browser/device E2E, Realtime, and the complete browser Chat flow (PostgREST message + attachment metadata creation and an injected metadata-failure cleanup) were not tested. The 3,600-second URL was proven usable; full one-hour elapsed expiry was not waited for.
- No Live/hosted database, real user rows, private messages, real attachments, calls, `main`, Production, DNS or paid service was accessed or changed. All test identities and files were synthetic. The native stack and Vercel Sandbox were stopped after the run.
- Audio/Video Calling remains paused and untouched.

## 2026-11-14 — Chat browser E2E and attachment realtime fix

- Created a separate short-lived Vercel Hobby Sandbox with Supabase CLI v3.1.0 native runtime, PostgreSQL 17.11, Auth v2.197.0, Realtime v2.154.0 and Storage v1.90.1. Replayed all 38 active migrations in the synthetic disposable DB. REST, Auth, Realtime and Storage services were healthy.
- Installed Playwright Chromium in the disposable sandbox and served the static app locally. Patched only the sandbox clone's `auth.js` and `admin/admin.js` to use the local Supabase URL and local publishable key; no hosted Supabase endpoint/key was used by the browser test. These temporary configuration edits were not committed.
- Created synthetic Seller and Buyer accounts through the actual browser Sign Up UI; both profile rows were created and had `account_status=active`. Created one synthetic direct conversation with both participants accepted.
- **Browser Chat E2E:** Seller and Buyer logged in through the UI and opened the same private conversation. Seller sent a text message; Buyer received the message through Realtime once the channel subscription had joined.
- **Browser file E2E:** Seller selected a TXT file through the Chat file input. The UI completed Storage API upload, message insertion, attachment metadata insertion and signed-link creation. Buyer received the file message, displayed the attachment link, and fetched the signed URL successfully (HTTP 200); downloaded text matched the exact synthetic upload content.
- **Issue found and fixed:** before the fix, the Chat Realtime channel subscribed to `message_attachments`, but the table was absent from `supabase_realtime` publication (the publication contained `messages` only). Realtime returned a system error for that unsupported subscription and the Buyer could miss the attachment link while the message itself arrived. To avoid changing migration history or creating a timestamp-order conflict, `chat.js` now removes that unsupported subscription and retries the attachment metadata lookup up to five times at 250 ms intervals after a file/image message event. After this source fix, the browser E2E passed for live attachment-link display and signed download; Realtime reported `Subscribed to PostgreSQL` without the prior subscription error.
- Source fix committed on `nexora-development`: `66742fdc7511b2c4f1ab32dbb5ce8bd7759a7fb8` (`Fix realtime chat attachment metadata race`). `node --check chat.js` and `git diff --check` passed. No SQL migration or database schema was changed for this fix.
- **Separate background issue:** browser page load also returned HTTP 401 for `/rest/v1/service_listings` on both test roles. This request was outside the Chat flow and did not block Chat/file tests; investigate the Services Marketplace read policy separately before calling the whole page clean.
- **Remaining limits:** test used desktop headless Chromium, not a physical Android/mobile browser. Realtime message delivery was verified after subscription establishment; immediate-send-before-subscription-readiness was not exhaustively load-tested. Pending-invite UI, concurrent users, mobile upload picker behavior, Realtime reconnect, and full cross-browser compatibility remain untested.
- No Live/hosted database, real user rows, private messages, real attachments, calls, `main`, Production, DNS or paid services were accessed or changed. Browser identities, messages and files were synthetic and confined to the disposable sandbox.
- Audio/Video Calling remains paused and untouched.

## 2026-11-14 — Prevent anonymous service_listings request

- Investigated the HTTP 401 observed during the previous Chat browser test. The `20261114090000_services_marketplace.sql` migration explicitly revokes all privileges from `anon,authenticated`, then grants Data API table access to `authenticated` only. The `service_listings_owner_or_public_read` policy is also `TO authenticated`; it intentionally does not permit anonymous reads. Thus an anonymous homepage request to this table is not authorized by the current schema design.
- Root cause in the frontend: `loadServicesMarketplace()` was invoked on initial page load even when no user session existed, although the SQL policy requires authentication. This caused a predictable unauthorized request and a misleading "marketplace unavailable" message.
- Fixed `marketplace.js`: before issuing the `service_listings` query, the loader now checks `signedIn()`. Anonymous visitors receive a clear "লগইন করুন" notice and the function returns without making a Data API request; authenticated users continue to use the existing RLS-protected query. No database grants or RLS policies were broadened.
- Commit on `nexora-development`: `2d251e42043ccdf06712e78c49e29c1a84a4f2dd` (`Avoid anonymous service listing API request`).
- Verified in a fresh Vercel Hobby Sandbox clone: `node --check marketplace.js` passed; `git diff --check` passed; reviewed the resulting loader guard in the checked-out source. A full authenticated/anonymous browser regression against the disposable Supabase stack has not yet been run for this particular change.
- No SQL migration, Data API grant, RLS policy, Live/Production database, `main`, DNS, or paid service was changed. Android viewport E2E has since been completed in emulation; physical Android device E2E remains pending.

## 2026-11-14 — Android viewport E2E (device emulation)

- Ran a fresh, disposable Vercel Hobby Sandbox using Supabase CLI 3.1.0 and the native local Supabase runtime. The clone's auth.js and admin/admin.js were temporarily pointed only at the local stack URL and local publishable key; those edits were not committed. No browser request was sent to the hosted Supabase project.
- Replayed all **38 active migrations** successfully into the disposable local database. Verification: 38 active files / 38 applied versions; **41 public tables, all 41 with RLS enabled**. The command supabase db lint --level warning --fail-on error reported **No schema errors found**.
- The local test database needed a synthetic foundation baseline because the active migration set expects the existing NEXORA foundation (profiles, Admin lookup tables and related functions). Used the repository's explicitly local-only foundation fixture with its guard adapted only in the disposable clone, plus a local-only RLS event-trigger helper and a false-returning Admin permission stub for test isolation. These are **not** deployable migrations and were not committed. The local baseline is not a copy of hosted schema or user data.
- Browser runtime: headless Chromium with Android 16 / Vivo V70 FE-style user-agent, **393 × 873 CSS-pixel viewport, DPR 3, mobile and touch emulation**.
- **Anonymous Services Marketplace:** opening the Services section displayed the Bangla login-required notice and generated **zero** /rest/v1/service_listings requests. No browser JavaScript errors.
- **Authenticated Services Marketplace:** a synthetic Buyer signed in through the app; the authenticated service_listings REST query returned **HTTP 200** and the expected empty-list state. The prior anonymous 401 regression did not recur.
- **Chat invitation and text E2E:** synthetic Buyer and Seller accounts were created through the local Auth UI. Buyer initiated a Chat request through the UI; Seller accepted it through the UI. Buyer sent a text message and Seller received it through Realtime.
- **Chat file E2E:** Buyer selected a synthetic TXT file through the app's file input. The actual local Supabase Storage API upload, message and attachment metadata flow completed; Seller received the attachment link, fetched its signed URL with **HTTP 200**, and the downloaded content exactly matched the uploaded bytes. No browser page errors were recorded.
- **Mobile layout check:** at 393 px width, neither the Services section nor Chat section caused horizontal document overflow. JavaScript syntax checks passed for auth.js, marketplace.js, chat.js, app.js and admin/admin.js; git diff --check passed.
- **Scope limits:** this is Android-sized Chromium emulation, **not a physical Android phone/browser test**. It does not verify the native Android file picker, on-screen keyboard behavior, device background/resume, real network transitions, or all Android browsers. The empty authenticated service response did not test rendering a real approved service card. Audio/Video Calling was not tested and remains paused.
- All test users, messages and files were synthetic and local. The native Supabase stack and Vercel Sandbox were stopped after testing. No hosted/Live DB, real user data, private conversations, real attachments, calls, main, Production, DNS or paid service was accessed or changed. No application source or SQL migration was committed as part of this E2E run.


## 2026-11-14 — Migration version inventory rechecked

- Fresh branch scan: **38 active SQL migration files / 38 unique versions**, no active version collision and no identical active SQL-content hashes. The two redundant conversation migration copies remain safely preserved in the recovery archive.
- The former shared version is resolved: product-linked conversations uses CLI-generated version `20261113203025`; unified delivery assignment retains `20261114180000`. Product-linked conversations has no Delivery Network/assignment/tracking references.
- Supabase CLI 3.1.0 naming probe in a disposable sandbox: UTC clock `2026-11-14T01:12:10Z`; official `supabase migration new version_order_probe` generated `20261114011211`. Probe file was deleted immediately; no repository change or DB operation.
- Latest active migration is `20261115120000`; the generated timestamp is earlier. Do not create a new migration until CLI naturally generates a version later than `20261115120000`. Do not hand-edit timestamps or set the clock. Existing source review and tests can continue without adding migrations.
- Sandbox stopped. No Live/hosted DB, migration history, user data, `main`, Production, DNS or paid services touched.
- Physical Android-device E2E remains pending; prior Android-sized Chromium emulation is not represented as a real phone test.


## 2026-11-14 — Physical Android E2E access/safety gate

- Read-only Vercel deployment inventory confirms a READY preview deployment for `nexora-development`; however, the current frontend source still contains the hosted Supabase project URL and publishable key in `auth.js`. Vercel project environment-variable listing returned no preview overrides.
- Therefore, the preview cannot be treated as an isolated backend for Android Chat/Auth/Storage testing. Do **not** ask the user to sign up, send messages, upload files, or otherwise exercise authenticated flows against that preview.
- Physical Android testing remains blocked until an isolated test Supabase backend is provided and wired into a non-production preview (or the user explicitly approves a separately scoped test project). No new Supabase project or paid service was created.
- This is distinct from the completed Android-sized Chromium emulation against the disposable local Supabase stack. No physical-device test is claimed.


## 2026-11-14 — Separate NEXORA-TEST Supabase project created

- User explicitly approved creating a separate Free Supabase Test Project under the NEXORA organization.
- Supabase quoted the project cost as **$0/month**; zero-cost confirmation was obtained before creation.
- Created project **NEXORA-TEST** in Singapore region `ap-southeast-1`; project ref: `lhxmqoyxoywntmkmmnjb`; status verified **ACTIVE_HEALTHY**; PostgreSQL 17.11.
- The new project has its own API URL and publishable key. Do not expose keys in this tracker or in chat; only a publishable key may be used by a browser client after test-environment isolation is established. No service-role/secret key was retrieved or exposed.
- No Live/Production database schema, rows, Auth identities, Storage objects or private conversations were copied. No migration has yet been applied to the new hosted Test Project.
- Vercel Preview environment inspection found no existing branch-scoped variables. The current `auth.js` still hardcodes the original hosted Supabase URL and publishable key; therefore, do not use the existing Preview for authenticated testing yet.
- Next safe step: design and implement an explicit branch-only Test backend configuration for `nexora-development`, verify Production/main cannot select the Test backend, then apply/rehearse schema only after establishing a safe isolated migration baseline. Do not set ineffective Vercel env variables for this static frontend without first adding a supported build-time configuration path.
- No Vercel environment variables, deployment, repository application source, SQL migration, main, Production, DNS or paid service changed during project creation.


## 2026-11-14 — Isolated Test backend routing staged on Development

- Added shared `supabase-config.js` with an explicit hostname allowlist:
  - Exact Development branch alias `nexora-platform1-git-nexora-development-shaifrony-7200.vercel.app` selects only the separate `NEXORA-TEST` project (`lhxmqoyxoywntmkmmnjb`).
  - Verified Production project domain `nexora-platform1-mu.vercel.app` retains the existing production backend.
  - Every other host fails closed and blocks Auth/Data API initialization; unknown per-deployment Preview URLs and localhost are not silently routed to Live.
- Loaded the shared config before Auth on both `index.html` and `admin/index.html`; updated `auth.js` and `admin/admin.js` to use the selected config. The only Test credential embedded is the Supabase **publishable** key, which is intended for browser use; no service-role/secret key or database password is present.
- Changes are confined to `nexora-development`; no `main` or Production source/config changes. No Vercel environment variables were changed. No Supabase migration/schema/data operation was performed.
- Disposable Vercel Sandbox source checks: `node --check auth.js`, `node --check admin/admin.js`, `node --check supabase-config.js`, `git diff --check` all passed. Confirmed both HTML pages load the config before their Auth script. Node VM routing tests: exact Development alias -> Test; a different Vercel Preview host -> blocked; unapproved non-Vercel host -> blocked; exact verified Production domain -> Production.
- Vercel automatically built the earlier source commits as READY Preview deployments and the stable branch alias was attached to the Development commit. A raw unauthenticated HTTP probe to that alias was redirected by Vercel Deployment Protection; no protection setting was weakened. Final fail-closed allowlist commit: `7bff5370c1d6c2da6f9efa1190996581931078f5`; its Preview build/alias must be rechecked before any authenticated use.
- **Not yet verified:** authenticated browser login, REST/PostgREST, Storage, Realtime, and actual Android device flows against the hosted Test Project. No user should sign in or upload anything until the latest Preview is confirmed READY on the branch alias and isolated DB schema is safely prepared.
- No Live data was copied; no hosted Test migrations applied yet. Calling remains paused.


## 2026-11-14 — Preview deployment quota blocks final rollout

- Attempted to create a Preview deployment for the latest `nexora-development` source after the fail-closed allowlist update. Vercel returned **402 payment_required**: Free daily deployment API quota exceeded (>100); retry available after **24 hours**.
- No billing/plan setting was changed, no paid service enabled, and no further deployment retries will be attempted during the quota window.
- The earlier Preview deployment `dpl_8hDqLCsi3tiAxXeTjX2QdkqwJpEs` (commit `aaefd128542d6d75ac01a9292c9b366b016104c1`) was READY and had the stable Development alias, but it predates the final Admin-file and fail-closed allowlist commits. Do not treat the alias as fully validated for authenticated use until a fresh deployment of the current branch head succeeds.
- Current source-level configuration and sandbox syntax/routing tests are complete; physical Android and authenticated Test Project E2E remain blocked by deployment quota and the need to verify the final Preview.
- Wait 24 hours or ask the user to resolve the Vercel plan/quota requirement. Do not automatically upgrade the plan or spend money.


## 2026-11-14 — NEXORA-TEST database and migration readiness audit (read-only)

### Test project state
- Confirmed project `NEXORA-TEST` (`lhxmqoyxoywntmkmmnjb`) is `ACTIVE_HEALTHY`, PostgreSQL 17.11.0.019.
- `list_migrations` returns **zero application migrations**.
- Read-only catalog query confirms **0 public application base tables, 0 public columns, 0 public RLS policies**. Auth/Storage platform schemas are provisioned by Supabase; these platform-internal tables are not NEXORA application tables.
- Supabase Security, Performance and Health advisors currently return **no lint findings** for this empty project. This does not validate the NEXORA schema because no application tables/migrations are installed.
- No SQL DDL/DML, migration, Auth user, Storage object or test data was written to the hosted Test Project.

### Current repository migration inventory
- Rechecked current `nexora-development` tree at HEAD `2dae7431a5fa9d428369bc98565ef6bbd48716eb`.
- Active `supabase/migrations/`: **38 SQL files, 38 distinct version prefixes**; newest is `20261115120000_multilingual_chat_foundation.sql`.
- The active sequence has no duplicate version collision. Two archived duplicate conversation migration pairs and the 11 missing-history recovery drafts remain outside the active migrations directory.
- `supabase/config.toml` is not present in the tracked `supabase/` directory, so a reproducible CLI project config still needs to be prepared and reviewed before a hosted migration workflow.
- Current Supabase CLI v3 behavior was rechecked against the Nov 4 changelog: DB commands target local by default; hosted target requires explicit `--remote`; hosted mutations require confirmation and `--yes` for unattended runs. Sources: Supabase changelog Nov 4 2026 and CLI v3 migration guide.

### Critical bootstrap/dependency finding
- The 38 active SQL files are **feature/incremental migrations, not a complete clean-database bootstrap**.
- Earliest migration `20261112045441_revoke_public_rls_auto_enable_execute.sql` assumes `public.rls_auto_enable()` already exists.
- Core Marketplace migration `20261112050345_create_marketplace_core_schema.sql` assumes existing `public.profiles`, `public.is_nexora_admin()`, and Supabase Auth identity context.
- Follow-up RLS migration `20261112050553_optimize_marketplace_rls_and_fk_indexes.sql` assumes `profiles`, `role_requests`, `profile_change_requests`, and related admin helpers.
- Communications migrations require `profiles`, existing conversation prerequisites and the `supabase_realtime` publication.
- Transport, Porter, officer-management and later commerce migrations depend on the missing foundation tables/functions: `profiles`, `admin_staff`, `admin_departments`, permission catalogue/grants, audit logs, `is_nexora_admin()`, `has_nexora_permission()`, and Auth trigger function `handle_new_user()`.
- The source tree does not contain the original foundational DDL. The existing `local-setup/06_local_foundation_baseline_fixture.sql` is explicitly a **new local-only test fixture**, not recovered original SQL and not deployable; it targets a local PostgreSQL compatibility environment, not a hosted Supabase project. Do not execute it against NEXORA-TEST as-is.
- Eleven historical Live migration versions have no exact source in the repository. Ten are catalog-reconstructed drafts; one Buyer Demand body is source-recovered with a version mismatch (repository `153000`, Live history `153453`). The recovery README explicitly says none of these drafts has been executed or certified as exact historical SQL. Keep all recovery drafts outside active migrations and do not replay them to manufacture history.

### Audit conclusion / safe next gate
- **BLOCKED: direct `supabase db push --remote` of the 38 migrations to the empty NEXORA-TEST project is unsafe and expected to fail at the missing foundation prerequisites.**
- The empty project's zero advisor findings are not evidence of application-schema safety.
- Before applying anything, create a separately reviewed, clearly labelled **Test-only foundation baseline** for the hosted Supabase platform (Auth, roles, schemas, Admin authorization, Auth trigger, RLS and Realtime prerequisites). Compare it with the local-only fixture and schema-only catalog evidence; do not copy any Live user rows, auth identities, private messages, calls, or Storage objects. Keep recovered-history drafts excluded.
- Only after that baseline is independently reviewed should we rehearse the 38 active migrations in a disposable local Supabase stack and then on NEXORA-TEST, using explicit project targeting and synthetic identities/data. Calling remains paused.
- This was a read-only audit: no migration, hosted schema/data, `main`, Production, DNS or paid plan was changed.


## 2026-11-14 — NEXORA-TEST Foundation Baseline design v1

- Created the current authoritative Test-only foundation contract:
  `supabase/recovery-not-for-deployment/local-setup/09_nexora_test_foundation_baseline_spec.md`.
- The specification consolidates identity/profile lifecycle, Buyer/Seller/Porter/Admin role boundaries, Porter approval, Admin hierarchy/permissions, audit, Auth provisioning, private-schema helpers, RLS/grants and privacy requirements, migration prerequisites and validation gates.
- **Corrected a stale business-model contradiction:** current Marketplace is unified. No Buyer/Seller Wholesale/Retail category fields or category-based visibility. Sellers set their own prices/quantities; everyone sees approved marketplace listings. Logistics delivery modes remain a separate concept. This supersedes the old Wholesale-Only category model in `05_foundation_design_proposal.md`.
- Marked `05_foundation_design_proposal.md` as superseded historical context and `06_local_foundation_baseline_fixture.sql` as a superseded local compatibility fixture. Do not use the old fixture as the current baseline; it still contains the obsolete market-category model.
- Updated `supabase/recovery-not-for-deployment/README.md` to point to the current specification.
- Commits on `nexora-development`:
  - Specification: `c2f491c3eb9ce827a0237eb1f0504e1a7d7d6276`
  - Old proposal marked superseded: `d10c3817ab3d12aa2d2a8f0df7dffcf14e78ca7d`
  - Old local fixture marked superseded: `d92fd37c4beff0701b694c9ef0824ecb1ecafe67`
  - Recovery README updated: `6a7d35f9a4a484ec27d0a725d663de27aaa60420`
- This is design/documentation only. No SQL was generated or executed, no hosted Test schema/data changed, no Live/Production/ `main` / DNS / paid service changed. No real users or private content used. Calling remains paused.
- Supabase CLI v3 breaking behavior rechecked: hosted database commands require explicit `--remote`; hosted mutations prompt for confirmation and require `--yes` when unattended. References: Supabase CLI v3 migration guide and Nov 4, 2026 changelog.
- **Next gate:** produce a full dependency/compatibility matrix for all 38 active migrations and frontend dependencies, then write a new Test-only SQL baseline only after all required columns, permission keys, trigger behavior and function signatures are confirmed. Migration timestamp generation gate still applies; do not invent or rename timestamps.


## 2026-11-14 — 38-Migration + Frontend compatibility audit v1

- Completed a source-level dependency inventory of all **38 active SQL migration files** on `nexora-development`, plus frontend call-surface scan of `auth.js`, `marketplace.js`, `chat.js`, `app.js`, `admin/admin.js`, `delivery-network-admin.js`.
- Added authoritative working matrix: `supabase/recovery-not-for-deployment/local-setup/10_migration_frontend_compatibility_matrix.md`.
- Confirmed no active Foundation migration creates `profiles`, role/profile request tables, Admin staff/departments/catalog/grants/audit tables, or the main Admin permission resolver. First migration expects `public.rls_auto_enable()` to pre-exist; Marketplace migrations expect `profiles` and `is_nexora_admin()`; Admin/Transport/Listing/Delivery/Porter expect additional Admin and permission helpers.
- Confirmed #15 `20261113100000_create_porter_delivery_workflow.sql` is a documented no-op. Current frontend still references legacy `porter_delivery_jobs`, `porter_delivery_job_events`, and legacy Porter RPCs not created by the active migration set. These need reconciliation against the approved unified Transport Provider + Vehicle + `delivery_jobs` model before SQL is authored; do not create duplicate legacy tables by assumption.
- Recorded required Admin permission keys observed in active migration SQL: `logistics.view`, `logistics.assign`, `products.edit`, `services.edit`; migration #34 adds further department catalogue seeds requiring exact frontend cross-check.
- The matrix lists each of the 38 migrations with its principal objects and Foundation/platform/earlier-migration dependencies, plus Auth trigger, Realtime/Storage, RLS, Demand privacy, role lifecycle, Calling pause and Translation restrictions.
- Audit was static only. No SQL generation/execution, no NEXORA-TEST schema/data mutation, no Live/Production/`main`/DNS/paid services touched. No user rows or private content used.
- Supabase CLI v3 changelog checked: hosted DB mutations require explicit `--remote` and `--yes` in noninteractive runs; new migrations must be created by `supabase migration new`, never by inventing timestamps.
- Matrix commit: `c51c7247573f9535ad20278d5bd0578c276d61c7`.
- README link commit: `5c911e87789d35db14931bfd72ca31763176cf1b`.
- **Next blocker:** reconcile legacy Porter frontend RPC/table paths and formalize Admin/role-request RPC contracts; only then prepare Test-only Foundation SQL. No hosted SQL operation is authorized by this audit.


## 2026-11-14 — Buyer-stage safety and frontend entry-point repair

- Reconfirmed the active product focus: **Buyer Module first**. Seller/Porter/Admin feature work is deferred unless a prerequisite is required to unblock safe Buyer work.
- Buyer-facing source inspection covered registration/login/profile entry, public Marketplace discovery/search, product detail, Seller contact request, product price negotiation, order request/history, Buyer Demand creation with required-by date, public Demand board and private Buyer Demand/quotation dashboard. This was a static source review, not a runtime acceptance test.
- Fixed the environment-routing fail-open condition:
  - `supabase-config.js` now supplies explicit URL and publishable key for both the allowlisted Test host and the explicit Production host.
  - `auth.js` and `admin/admin.js` now require a valid, explicit `test` or `production` configuration with URL and publishable key. Missing, blocked, malformed or unknown configuration stops before client creation; there is no fallback to Live credentials.
- Repaired missing closing `</script>` tags for `supabase-config.js` in both `index.html` and `admin/index.html`. Previously, the subsequent application scripts were nested as script text rather than separate script elements, preventing the intended loading sequence.
- Commits on `nexora-development`:
  - Explicit environment routing: `0397886de8332554c7bbf37c45ff39fe4e43d579`
  - Buyer authentication fail-closed guard: `dec70226c4b3e3c49cf2463346e75ab784efef51`
  - Admin authentication fail-closed guard: `bb6202d66906cfa31f69c5062d77ec16e2091503`
  - Main page script closure: `38af2e9e2c17afafe61fb8234cf54339e031461f`
  - Admin page script closure: `14a5e14877a33e39dbc585c9e7dd62b47985c9b5`
- No database schema/data, SQL migrations, Test project, Live/Production data, `main`, DNS or paid service was changed. No login or real-user testing was attempted.
- **Validation still required:** browser/runtime test of script loading and explicit host routing; Test-host deployment is currently constrained by Vercel deployment quota/protection and NEXORA-TEST remains empty. Do not ask the user to log in on an unverified preview.
- **Next Buyer gate:** complete a focused Buyer acceptance checklist and identify any remaining Buyer UX/security gaps across Marketplace browse/search/detail, Buyer Demand, Seller inquiry, quotation negotiation, orders, Buyer profile and chat. Use only synthetic identities/data in the disposable local test environment; do not apply migrations to empty NEXORA-TEST until the Foundation baseline is reconciled and separately authorized.


### Buyer workflow source inventory — follow-up
- Static HTML check after the repair confirms balanced script tags: public app `index.html` has 7 opening / 7 closing script tags; Admin page has 3 / 3. This confirms tag balance only, not browser execution or JavaScript syntax/runtime.
- Buyer-facing paths currently present in source:
  - Email/password Buyer signup and login; Google/Facebook OAuth is limited to Buyer in the current UI.
  - Buyer profile summary and Buyer Center entry.
  - Public approved-product grid, search/filter, permanent product detail URL, price/MOQ/price tiers/stock display.
  - Product detail Seller inquiry via `create_product_inquiry`, private Chat handoff, price negotiation and separate order request.
  - Buyer Demand form includes required-by date; client validates today/future date and persists it as `required_date`.
  - Public open-Demand board reads the safe `public_buyer_demands` projection and displays required date without Buyer identity/contact fields.
  - Buyer Dashboard reads own Demands and associated Seller offers, supports accept/counter/reject and close/cancel; separate product negotiation and order history/status actions are present.
- UI caveat: Buyer Center currently displays a Wallet Balance placeholder (`৳ —`) without a verified live balance source in the reviewed Buyer code. Do not treat this as a working wallet or enable payment claims; defer/label clearly until an approved wallet/payment implementation exists.
- This inventory is source-only. It does not prove signup/Auth trigger behavior, API permissions, RLS, Realtime, Storage, or browser UX after the script repair.


## 2026-11-14 — Buyer Module completion execution started

- Reconfirmed scope: Buyer Module first. Seller, Porter and Admin feature changes are deferred unless a concrete Buyer prerequisite requires them.
- Re-read the current Buyer completion checklist and inspected the current branch source for index.html, auth.js, marketplace.js, chat.js, and supabase-config.js.
- Confirmed the core Buyer UI/source paths exist for account signup/login, product discovery, product details, Buyer Demand with required date, own Demand/quotation view, product-price negotiation, order list and participant-consent Chat. This is a source inventory only; it does not establish end-to-end functionality.
- Identified a misleading Buyer Dashboard wallet presentation: it displayed WALLET BALANCE, a placeholder amount and Available Balance even though no wallet ledger/payment integration is implemented. Updated the Buyer shell to explicitly say “WALLET & PAYMENTS — এখনো চালু হয়নি — Order request মানেই Payment নয়”.
- Commit: 7c79161248193c2aac996e968d4897bc850dab37 (index.html).
- Remaining critical gates are unchanged: trusted Foundation/schema and migration-history reconciliation; isolated full-chain rehearsal; real Supabase Auth/JWT/PostgREST/RLS verification; two-session concurrency; Buyer browser/mobile acceptance tests; order delivery tracking integration; support/complaint path; and verified-review E2E.
- Do not claim Buyer Module complete. The current action is a source-level accuracy fix; no runtime test was run in this step.
- No SQL or migration was generated or executed; NEXORA-TEST remains empty; no Live/Production, main, DNS, paid service or deployment was changed.

- Follow-up Buyer gap audit added to docs/NEXORA_BUYER_COMPLETION_CHECKLIST.md (commit 4618133a6888b9e728268bb3bd08d6ae98d1defc): Buyer profile editing/request flow is absent; Buyer order delivery tracking is not yet proven; wallet/payment remains unavailable and is now disclosed honestly. These gaps are explicitly open, not marked complete.

- Buyer account settings implementation: Buyer-only login email change (confirmation required) and password change forms/handlers added. Commits: index.html e48a5da4409ee388fcfaeb3fad62f2bc8011cc02; auth.js b7d81c66c769c4a96f2d3154344500240fd589c1. JavaScript syntax and static guards verified; Supabase Auth runtime/E2E still pending. Legal/display name change request remains blocked by missing Foundation table/RPC contract; no direct profiles update added. Checklist update commit 1e94ddef8798eb630e52a9646f6df8865a19466c.


### 2026-11-14 — Buyer password rule adjusted
- User-selected minimum password length is **6 characters**, not 10.
- Updated Buyer password form HTML minimum and client validation to 6; mismatch blocks update and status feedback remains. Password recovery/reset validation also uses 6 for consistent password-setting behavior.
- Static source checks passed for both forms, minimums, mismatch guard and result feedback. Supabase Auth runtime test remains pending.
- Commits: `460dffab7fad5828fbbd424560347d8b236fab2b` (`auth.js`), `17aad13356b613e1f56c4d90f77464c7502019ee` (`index.html`), checklist update recorded separately.


## 2026-11-14 — Buyer-first / Seller-funded product principle

User-defined governing principle: NEXORA earns revenue from Sellers, but Sellers need Buyers; therefore Buyer acquisition, trust, repeat use and ease of use take priority. This is now a product-wide decision rule for architecture, UX, feature order, QA and monetization.

- Keep Buyer browsing/discovery low-friction and free; do not force account creation merely to browse where safe.
- Do not charge Buyers for platform access, posting Demands or receiving/responding to quotations unless a separately approved model changes this.
- Minimize mandatory fields/steps; explain why necessary data is requested; use mobile-first Bengali-friendly UX, clear validation/status and duplicate-submit protection.
- Show full price context, currency, quantity, delivery charge, required date and order status clearly. Never imply wallet/payment/delivery booking exists when it does not.
- Protect Buyer identity/contact and preserve consent-based Seller communication. Ease cannot weaken privacy, security or transaction correctness.
- Seller monetization should be transparent and value-linked, without interrupting Buyer journeys.

Source audit surfaced UX friction to address next: multiple competing CTAs on Product Detail; many required Buyer Demand fields; and browser prompt/confirm dialogs for quotation acceptance/counter-offers. No flow changes were made yet because schema constraints and runtime behavior must be verified first. Detailed notes added to Buyer completion checklist.


### Buyer Demand form friction reduction — 2026-11-14
- Made Subcategory, Description and Specifications optional, preserving required product name, category, quantity, currency, destination and required-by date. Budget remains optional.
- Confirmed active source schema permits empty description, nullable specifications and nullable/blank subcategory; the Seller routing function treats blank subcategory as category-wide matching. No DB/schema change.
- Static checks passed: marketplace.js syntax, form constraints, script tag balance. Browser/runtime remains pending.
- Commit: `7f9249e406a87dc1c5b583e224375ffda48212fc`.


### Buyer quotation response made easier — 2026-11-14
- Buyer quotation acceptance and counter-offer now use inline forms instead of browser prompt dialogs. Quantity is bounded by Seller's available amount; counter price validated; optional note supported; busy/error feedback and cancel action included. Reject confirmation remains.
- Existing server-side RPC and permission/state checks unchanged. Static JS compilation and source guards passed; browser runtime remains untested.
- Commit: `19e3e553a80ffb891df954c12a984fd05d69245f`.


### 2026-11-14 — Product Detail contact consent safeguard
- Removed direct Product Detail Chat creation because the available source evidence did not prove that `create_product_inquiry` requires Seller acceptance before a conversation opens. Replaced it with a clear notice; Buyers retain explicit price-negotiation and order-request routes.
- Static JavaScript syntax and source checks passed. Runtime/browser/DB tests remain blocked pending Foundation and safe NEXORA-TEST setup.
- Checklist updated. Commit: `89a78e69f9e53b5db7a94e092114b714335ee3a7`.
- No SQL, NEXORA-TEST, Live/Production, `main`, DNS, paid service or deployment change.


## 2026-11-14 — Buyer Order Dashboard clarity pass

- Improved Buyer order cards with plain-language status labels and a next-step explanation for each supported order state: pending, accepted, ready for confirmation, completed, cancelled and rejected.
- Added a real timestamp timeline from the existing Commerce Order fields: created_at, accepted_at, ready_at, completed_at and cancelled_at. No synthetic events or guessed dates are displayed.
- Made the financial summary explicit: agreed/item subtotal, delivery charge (including zero), and delivery-inclusive grand total with currency. The order card states clearly that an order request is not payment and does not imply delivery booking.
- Added a safety reminder that the Buyer should confirm completion only after actually receiving the product/service. Seller note is shown as Seller update, not as verified courier tracking.
- Delivery tracking remains unavailable in the Buyer order card: the staged delivery_tracking_events policy currently exposes events to authorized Admin/provider roles, not Buyers. No Buyer tracking query was added and no privacy/RLS policy was weakened. The UI discloses that separate Delivery Tracking is not currently shown.
- Static validation: marketplace.js compiles with `new Function`; the query uses only columns present in the Commerce Order table plus the later staged delivery-charge/total extension; state actions remain the existing server-validated cancel/complete RPCs. No browser, Auth, PostgREST, RLS or DB runtime test was performed.
- Source commit: fc7e9d0a6d2f2d440110f8b6198bb70f1d6c4dc0.
- No SQL/migration, NEXORA-TEST, Live/Production, main, DNS, paid service or deployment changed. Buyer Module remains incomplete and not acceptance-tested.


## 2026-11-14 — Buyer Order History filters & safe Delivery Tracking design

- Buyer Order panel now shows a compact summary and filters for all, pending, accepted, ready for Buyer confirmation, completed, cancelled and rejected orders. The UI explicitly labels the result set as the latest 50 orders, newest first; it does not imply the summary is a lifetime count. Empty filter results are handled.
- Existing real order timestamps and Seller update remain visible. No product title, Seller identity or delivery state is fabricated; the polymorphic listing schema does not currently provide a safe product-title snapshot on the order row.
- Added `docs/NEXORA_BUYER_DELIVERY_TRACKING_ACCESS_DESIGN.md` defining a customer-safe, append-only tracking projection, narrow Buyer-owned-order RPC, split-shipment handling, no raw contact/address/internal-note exposure, and synthetic negative authorization tests.
- Tracking is intentionally not enabled in UI or SQL: current raw tracking policies are Admin/Provider only and raw operational tables contain private contact/address fields. The design does not weaken those policies.
- Static verification: `marketplace.js` compiles with `new Function`; latest-50 label/limit, seven filter states, real status filtering, empty state, timeline fields, Seller update and no raw delivery table query verified. No browser, PostgREST, RLS, Auth or database runtime tests performed.
- Buyer source commit: cce44c4359ad6429192198dcd429aac8c7f2a793. Tracking design commit: 825e1390b180de253bec5ab949a54e75add22672.
- No SQL/migration, NEXORA-TEST, Live/Production, `main`, DNS, paid service or deployment changed. Foundation/migration-history blockers remain.


## 2026-11-14 — Buyer Order identity snapshots
- Buyer Order History still lacks immutable item-name and Seller public Business Display Name snapshots. The current polymorphic `listing_id` is not sufficient for a safe historical join.
- Added `docs/NEXORA_BUYER_ORDER_IDENTITY_SNAPSHOT_DESIGN.md` (design only). It specifies server-captured immutable names, safe public Business projection only, NULL legacy fallback, and required Product/Service/Demand conversion + privacy tests.
- Frontend remains unchanged until the snapshot schema and final Demand conversion RPC are verified. No guessed query or private `profiles` lookup was introduced.
- Status: **Design documented; implementation blocked** by Foundation/migration reconciliation and final Demand conversion/public projection source verification. No SQL or database mutation performed.


## Buyer Department progress snapshot — 2026-11-14
- B-01 to B-06 checklist: **29/51 = 57% staged-source checklist completion**. This is not production acceptance or test-pass percentage.
- 22 checks remain open, including migration/Foundation reconciliation, integration/security/E2E, orders/inventory, communications/reviews/support, payments/wallet and delivery integration.
- Latest Buyer Order identity snapshot: design documented; code/schema implementation remains blocked pending exact final Demand conversion RPC and public Business projection verification plus the migration/Foundation gate.


## 2026-11-14 — Buyer Order identity source verification

- Completed source-level verification for all three Commerce Order creation paths: Product/Service via latest `private.create_commerce_order` in migration #29; Buyer Demand conversion via `private.respond_to_demand_offer` in migration #36.
- Verified item-name sources: `products.product_name`, `service_listings.service_name`, and `buyer_demands.product_name`.
- Verified Seller public identity source: `public.public_businesses.display_name`, requiring exact Business + Seller match. Private profile identity must never be used as a fallback.
- Replaced the earlier incomplete snapshot design with a source-verified contract covering the three paths, immutable server-side snapshots, legacy NULL values, unchanged order logic and synthetic security tests.
- Design document: `docs/NEXORA_BUYER_ORDER_IDENTITY_SNAPSHOT_DESIGN.md`; source verification and commit: `12590b6b2f2daf394ae1c6bafdf7f3f15e146cfc`.
- Buyer checklist update: `a3b9faa264354052ff782e07e7e27c32da090faa`.
- **Not implemented yet:** snapshot columns/RPC updates and Buyer card UI. The Foundation baseline and complete migration history remain unreconciled; NEXORA-TEST is empty. Do not create/apply an active migration or update frontend selects until that gate is cleared.
- No SQL, database, NEXORA-TEST, Live/Production, `main`, DNS, paid service or deployment changed. No runtime/DB test was run in this pass.


## 2026-11-14 — Continued Foundation / delivery dependency audit

- Re-read the Supabase skill and checked the current Supabase changelog. CLI v3 changes defaults: database commands target local by default; hosted mutations require explicit targeting/confirmation. No CLI command or hosted mutation was run.
- Read-only NEXORA-TEST check reconfirmed project ref `lhxmqoyxoywntmkmmnjb`, ACTIVE_HEALTHY / PostgreSQL 17.11, zero migration history rows, zero public/private application tables, and zero security advisor lints. The project remains intentionally empty.
- Source-inspected delivery migrations #19, #31 and #32. The active model uses `delivery_jobs`, `delivery_job_events`, `delivery_job_assignment_history`, approved transport providers/vehicles and delivery-network partners/staff.
- Confirmed `marketplace.js` Admin Logistics monitor is stale: it still reads absent `porter_delivery_jobs` / `porter_delivery_job_events`, queries private `profiles.full_name`, and calls absent legacy Porter RPCs. Porter workspace itself already says the old job table is not used. Do not create duplicate legacy tables/RPCs; Admin monitor needs a separately reviewed migration to the unified delivery network model and must remain blocked/hidden until replaced.
- Added §9 to `supabase/recovery-not-for-deployment/local-setup/10_migration_frontend_compatibility_matrix.md` with the verified evidence and safe replacement contract. Commit: `10ee4e89e5a12cfd116acd20251df8ec3c67ceea`.
- No source application code was changed in this pass. No SQL, NEXORA-TEST schema, Live/Production, `main`, DNS, paid service or deployment changed.
- Next priority remains Buyer Department and the Foundation gate; do not spend Buyer-critical time implementing the legacy Admin Logistics panel until the Buyer Order/Delivery contracts and Foundation replay are ready.


## 2026-11-14 — Foundation role-request & Admin contract reconciliation

- Read Supabase skill before the Supabase-related work. All source operations were GitHub branch reads/writes; no hosted SQL was executed.
- Inspected exact current frontend Seller request contract: owner submits only Seller/pending; pending uniqueness constraint expected; Admin review calls `review_role_request(request_id, decision)` with `approved|rejected`. The historical migration defining this RPC/table is absent from the 38 active migrations, so this is a confirmed UI contract but not recovered SQL.
- Inspected #34 Director officer-management implementation and recorded its exact staff/grant/audit column requirements, Director representation (`super_admin` + `director`), department/position constraints, and transactional grant replacement behavior.
- Identified an additional stale frontend mismatch: `marketplace.js` calls `manage_nexora_user`, while newer Admin paths call `admin_manage_user`; neither exists in the active migration set. They must be reconciled into one server-authorized, audited contract rather than implemented as blind aliases.
- Expanded Foundation spec §11 with exact frontend-derived contracts, permission resolver minimum semantics, Admin compatibility requirements, mismatch list and synthetic security tests. Spec remains design-only / not SQL / not deployable / not applied. Commit: `7b95b2206d5b4f2fa553f293e63e2fd63351c58f`.
- Expanded compatibility matrix §10 with the same evidence. Commit: `1571e45045aac6c3d492592e213332e5d7c92881`.
- No app JS/HTML, SQL migration, NEXORA-TEST schema/data, Live/Production, `main`, DNS, paid service or deployment changed. No runtime tests were claimed.
- Next: source-audit the remaining Admin user-management actions/permission seeds against every active migration, then build a local-only Foundation candidate only after the complete contract is closed. Do not touch NEXORA-TEST until disposable local Supabase Auth/RLS tests pass and explicit approval is given.


## 2026-11-14 — Admin permission inventory follow-up

- Inspected current Admin UI grant checks and Logistics / listing-edit migration sources. Recorded the current UI permission keys (`users.*`, `products.suspend|restore|cancel`, `businesses.suspend`), listing edit keys (`products.edit`, `services.edit`), Logistics keys (`logistics.view|assign`) and #34 Marketing/Transport/Finance seed keys in Foundation spec §11.6.
- Added compatibility matrix §11. Exact permission requirements for legacy `manage_nexora_user`, newer `admin_manage_user`, and `manage_marketplace_listing` remain unresolved; do not enable them or add aliases until the server-side contract is reconciled. Client-side grant lookups are presentation only.
- Foundation spec commit: `a760d5ff8e56849aed809584da4ee00979c840a2`; compatibility matrix commit: `543329a1a10a6e4fc39cdf8858e7e06be7767757`.
- No app code or SQL changed; no database, deployment, production or DNS mutation. All work remains docs-only and source-level.


## 2026-11-14 — Auth trigger, RLS bootstrap and permission seed audit

- Scanned the 38 active migration files and directly inspected the Auth signup function and Admin permission seed sources.
- Confirmed #19 defines Buyer/Seller-only `handle_new_user()`; #35 replaces it with a Buyer/Seller/Porter allowlist, OAuth Buyer default and pending Porter review. Admin signup remains blocked. The Auth trigger binding on `auth.users` still needs explicit Foundation verification; defining the function alone is not proof the trigger is installed.
- Confirmed `public.rls_auto_enable()` has no definition in the active migration set; only an EXECUTE revoke references it. This remains an unresolved historical/Foundation dependency. No no-op function was created and no revoke was removed.
- Consolidated active permission seeds: Logistics `logistics.view|assign` (#19), `services.edit` (#24), Marketing/Transport/Finance keys (#34). #34's duplicate Logistics seed under Transport uses `ON CONFLICT DO NOTHING`, so the earlier Logistics department mapping remains unchanged.
- Identified frontend permission keys not seeded by the active migrations: `users.view|suspend|restore|cancel`, `products.suspend|restore|cancel`, `businesses.suspend`, and `products.edit`. They must be reconciled before authoring the Foundation seed set.
- Confirmed feature migrations consume `is_nexora_admin()`, `is_nexora_super_admin()` and `has_nexora_permission(text)`; canonical definitions and fail-closed semantics remain Foundation blockers.
- Updated Foundation spec §12 and compatibility matrix §12. Both remain design/recovery documents, not deployable SQL.
- No app code or SQL migration changed. No database, NEXORA-TEST, Live/Production, main, DNS, paid service or deployment mutation. No runtime/Auth trigger test was run.
- Next: resolve the Auth trigger owner/binding and RLS event-trigger dependency from authoritative baseline evidence, then reconcile all permission keys and RPC enforcement before preparing a local-only Foundation candidate.

## 2026-11-14 — Auth trigger binding and Admin resolver follow-up

- Re-scanned all 38 active migration sources, distinguishing application triggers from Auth/RLS infrastructure triggers.
- Confirmed there are triggers for public identity projection and business identity synchronization, but no active migration installs an `auth.users` trigger for `public.handle_new_user()`. The function body is defined/replaced by #19/#35 only.
- Confirmed no active migration creates the RLS auto-enable event trigger; #1 only revokes EXECUTE on `public.rls_auto_enable()`, whose implementation/binding is absent.
- Inspected #12: `private.is_nexora_active_admin_staff()` checks AAL2 + active Admin profile + active staff row, but is not a full Director/permission resolver. Existing policies OR this helper with missing `public.is_nexora_super_admin()`; multiple workflows depend on missing `private.has_nexora_permission(text)`.
- Added Foundation spec §13 and compatibility matrix §13. No code, SQL, migration, trigger, database or deployment changed; no runtime tests were run.
- Next: establish an authoritative Auth/RLS infrastructure baseline (historical recovery or explicitly new design), then create a local-only Foundation candidate only after complete dependency reconciliation and disposable replay.

## 2026-11-14 — Auth/RLS Foundation design v1

- Added Foundation spec §14 and compatibility matrix §14 with a non-deployable design for the missing Auth signup trigger, RLS auto-enable event trigger, canonical Admin resolver, explicit Data API grants, replay ordering and verification gates.
- Auth trigger design: exactly one AFTER INSERT trigger on `auth.users` invokes #35 `handle_new_user()`; no client EXECUTE; profile + Porter pending review atomic; Admin/unknown roles rejected; failures roll back signup.
- RLS event-trigger design: implement real `public.rls_auto_enable()` expected by #1; owner-controlled DDL event trigger only for table creation tags; enable RLS on new ordinary/partitioned `public` tables, but do not invent policies/grants or FORCE RLS.
- Admin resolver design: canonical private AAL2 + active profile/staff + protected Director + active catalog + explicit department grant; deny wins; compatibility wrappers cannot bypass.
- New platform constraint recorded: Supabase Data API auto-exposure for new public tables was disabled/enforced by 2026-10-30; explicitly audit GRANTs + RLS on a fresh project.
- Important replay finding: a new timestamped Foundation migration after latest feature migration cannot repair earlier timestamp-ordered dependencies. Do not fabricate history. Recovery-only bootstrap may be considered only in a disposable local DB before full feature replay.
- Design/documentation only. No SQL, code, migration, trigger, DB, NEXORA-TEST, Production, main, DNS or deployment changed; no runtime tests performed.
- Next: search any remaining authoritative baseline source; if unavailable, create a clearly labeled recovery-only bootstrap candidate after completing exact dependency inventory and local environment availability check.

## 2026-11-14 — Admin permission catalog + RPC reconciliation audit

- Re-read all current Admin UI key consumers in `auth.js`, `marketplace.js`, `admin/admin.js`; confirmed frontend-only keys without migration seeds: `users.view/suspend/restore/cancel`, `businesses.view/suspend`, `products.view/suspend/restore/cancel/edit`, `security.audit_logs.view`.
- Reconciled actual migration seeds: #19 `logistics.view/assign`; #25 `services.edit`; #34 Marketing, Transport, Logistics and Finance key set.
- Found material department conflict: #19 inserts Logistics keys under `logistics`; #34 attempts same keys under `transport` with `ON CONFLICT DO NOTHING`, leaving the original department unchanged. #34 officer grant validation requires department match, so Transport staff cannot receive these keys. #25 seeds `services.edit` under `product_business`, but #34 does not seed that department; #25 references unseeded `products.edit`.
- Confirmed missing frontend RPCs: `review_role_request(request_id,decision)`, `manage_nexora_user(p_user_id,p_action,p_reason)`, alternate `admin_manage_user`, and `manage_marketplace_listing(p_target_type,p_target_id,p_action,p_reason)`. Do not add aliases or generic mutation without action/permission contract.
- Recorded exact Seller role request owner contract and requirements for row lock, pending uniqueness, active Buyer precondition, atomic approval/rejection and audit.
- Added Foundation spec §15, compatibility matrix §15 and tracker. No SQL, code, seed, RPC, DB, NEXORA-TEST, Production, main or deployment changed. No runtime tests.
- Next: decide canonical department ownership and reconcile missing UI RPCs; only then prepare recovery-only Foundation bootstrap candidate.

## 2026-11-14 — Foundation environment readiness recheck

- Confirmed current tool container has no `supabase` CLI, Docker or `psql`; repository is not mounted locally, so disposable local replay cannot be performed in this session.
- Read-only NEXORA-TEST recheck: 0 migration-history rows, 0 tables in inspected `public`/`private` schemas, 0 security advisor lints. No hosted schema mutation.
- Added Foundation spec §16 with remaining department/governance decisions: Logistics vs Transport, Product/Business department, User/Business/Product moderation ownership, Audit Log access and listing approval powers.
- Foundation recovery-only SQL is not yet safe to author/apply: department scope conflicts remain and no local runtime is available. Do not substitute hosted NEXORA-TEST for disposable local testing.

## 2026-11-14 — Recommended Admin department governance proposal

- Added Foundation spec §17 and Compatibility Matrix §17 as a conservative proposal, not approved policy and not SQL.
- Recommendation: keep Logistics separate from Transport; explicitly seed `logistics` and `product_business`; Transport manages providers/vehicles/staff; Trust & Safety owns user/business/product moderation; Marketing remains leads/campaigns only; Accounts retains finance.
- Proposed Trust & Safety keys: `users.view/suspend/restore/cancel`, `businesses.view/suspend`, `products.view/suspend/restore/cancel`; reversible cancellation only, never Auth hard-delete. Product/Service edit keys belong to Product & Business.
- Director-only initial boundary: public Seller/Business/Product/Service approval, Admin appointment, Buyer→Seller role review and audit log viewing. No default staff audit-log permission.
- Documented restrictions: no private Buyer contact/profile dump, no private chat/call access, no finance cross-access, no implicit cross-department grants, no generic mutation RPC and no alias-by-guessing.
- Await explicit owner confirmation before executable SQL. No SQL, source code, migration, database or deployment changed.

## 2026-11-14 — Owner-approved Admin Governance / Foundation Bootstrap preparation

- Owner explicitly approved the proposed Admin Governance structure.
- Canonical departments: `managing_director`, `marketing`, `transport`, `logistics`, `product_business`, `trust_safety`, `accounts`.
- Approved boundary: Logistics separate from Transport; Product/Service listing edits in Product & Business; user/business/product moderation in Trust & Safety; Marketing leads/campaigns only; Accounts finance only. Director-only initial audit-log viewing, public listing/business activation approvals, Admin appointment and Buyer→Seller role review.
- Documented Trust & Safety permission seed intent. Mutation permissions remain nonfunctional until narrow audited server RPCs and their exact action/target/state transitions are implemented; `users.cancel` is reversible deactivation, not Auth deletion.
- New source blocker: active migration #34 `manage_nexora_officer` hard-codes non-MD departments to `marketing|transport|accounts`, omits `logistics|product_business|trust_safety`, and attempts to seed `logistics.*` under `transport`. This must be reconciled before staff permissions can be assigned correctly.
- Added Foundation spec §18 with owner approval, approved catalogue, source blockers, recovery-only bootstrap dependency order and stop conditions; updated compatibility matrix §18.
- No SQL/migration/code/DB mutation performed. Current environment lacks Supabase CLI, Docker and psql, so no local parser/replay/runtime test is possible here. NEXORA-TEST remains untouched; no Live/Production/main/DNS/deployment changes.
- Next: resolve #34 source compatibility on `nexora-development`, obtain a disposable local Supabase runtime, then author a recovery-only Foundation SQL candidate outside `supabase/migrations/` and validate Foundation + all 38 feature migrations with synthetic security tests.

## 2026-11-14 — Migration #34 Governance compatibility repair contract

- Owner-approved seven-department Governance was rechecked against the exact #34 SQL source.
- Chose not to edit the historical timestamped migration in place or invent a forward migration timestamp. The source may already have been applied in an environment; changing its file would not update that database and could make fresh replay diverge.
- Added a recovery-only repair contract to Foundation spec §19 and Compatibility Matrix §19: canonical department upserts; deterministic Logistics permission ownership; six operational department allowlist; Product & Business and Trust & Safety catalog ownership; inactive/ungrantable moderation mutation permissions until narrow RPCs exist; active catalog + department checks in server-side grant validation; Director/AAL2, transaction, row-lock and audit invariants.
- Specified positive and negative synthetic tests for every department, cross-department permission attempts, inactive permission grants, Director-only boundaries, AAL1/inactive staff, invalid targets and transaction/audit consistency.
- No SQL candidate or active migration was created. No repository application source was modified. No NEXORA-TEST, Live/Production, `main`, DNS, paid service or deployment mutation occurred.
- Environment gate remains: no local Supabase CLI, Docker, `psql` or checked-out working tree. Generate and test the recovery-only SQL only in a disposable local Supabase environment; do not substitute the empty hosted NEXORA-TEST project.

## 2026-11-14 — Disposable local Foundation replay preflight

- The old `nexora-disposable-db-preflight` Sandbox was non-persistent and had no snapshot; resume failed with `snapshot_not_found`. Reused the existing persistent `nexora-backend-routing-check` Sandbox instead; no new Sandbox was created.
- Checked out `nexora-development` and verified the repository worktree remained clean. Active migration count remains 38.
- Copied the active migrations to isolated `/tmp/nexora-replay`, initialized a separate local Supabase config, and started a disposable native-runtime replay with Supabase CLI v3.1.0.
- Runtime replay failed at the first active migration (`20261112045441_revoke_public_rls_auto_enable_execute.sql`) because `public.rls_auto_enable()` does not exist (PostgreSQL 42883). This validates the known Foundation blocker only; later migrations and security/E2E tests remain untested.
- Did not stub or fabricate the missing function, rewrite migration #1, or alter active SQL. Destroyed the disposable local stack and verified no local stack remained. No applied-migration count is claimed because the failed stack was not running when queried.
- No repository source/migration, NEXORA-TEST, Live/Production, `main`, DNS or deployment changed. No hosted mutation occurred.
- Next: author a recovery-only Foundation bootstrap candidate outside `supabase/migrations/` from the reviewed §14 contracts and §19 governance repair, then validate it on a fresh disposable native stack before replaying all 38 migrations.


## 2026-11-14 — RLS helper candidate verified; replay advances to Foundation dependency

- Resumed the existing persistent `nexora-backend-routing-check` Sandbox; no new Sandbox was created. Worked only on `nexora-development`.
- Built `supabase/recovery-not-for-deployment/local-setup/12_rls_auto_enable_recovery_candidate.sql` from approved Foundation §14.2. It is explicitly recovery-only, not recovered historical SQL, not an active migration and not deployable.
- Disposable PostgreSQL 17 / Supabase CLI v3.1.0 runtime: 12/12 assertions passed (ordinary tables, multi-statement creation, CTAS, SELECT INTO, partitioned parent/child, non-public exclusion, trusted owners, trigger enabled, no API EXECUTE, no-policy `anon` read denied, no recursive trigger creation). Extension-owned table behavior is still an explicit untested case.
- Fresh replay with the candidate preinstalled: migration `20261112045441` passed; migration `20261112050241` then failed because `public.profiles` is missing. Verified exact local migration history count = 1. This is progress past the first blocker, not a full replay.
- Destroyed the disposable replay stack and verified `stack list` is empty. No active migration was changed; no NEXORA-TEST, Live/Production, `main`, DNS or deployment mutation occurred.
- Next: build the approved Foundation baseline in the disposable local environment, including profiles, governance/auth prerequisites and fail-closed security contracts; then rerun all 38 migrations and synthetic security tests. Do not use hosted NEXORA-TEST as a substitute for local validation.


## 2026-11-14 — Foundation replay and Admin Governance local validation

- Added recovery-only candidate #13 for Foundation baseline; it is not historical SQL, not an active migration and not deployable. Added public `is_nexora_super_admin()` wrapper after fresh replay identified active migration #12's direct dependency.
- On a fresh disposable native PostgreSQL 17 stack, installed RLS helper #12 and Foundation #13, then replayed **38/38 active migrations** successfully (first `20261112045441`, last `20261115120000`).
- Foundation synthetic suite: 15/15 assertions passed (Auth role provisioning, Porter pending approval, no public Admin signup, Director AAL2, permission scope, Buyer privacy, Seller role request uniqueness, protected role, atomic approval and audit).
- Added recovery-only candidate #14 for migration #34 Governance compatibility. It allows the six approved operational departments, checks active catalog/exact department, keeps Trust & Safety mutation keys inactive, accumulates sensitive-permission requirements and preserves audit reasons.
- Governance suite: 16/16 assertions passed (six department appointments, correct grants, cross-department rejection/rollback, inactive permission rejection, audit reason, reversible deactivation). Update/AAL1/sensitive-reason suite: 3/3 passed.
- Supabase `db lint`: no schema errors. Public tables: 41/41 RLS enabled. SECURITY DEFINER functions: 46/46 explicit search_path. Exactly one Auth signup trigger; no API EXECUTE on internal trigger functions.
- Total local assertions across RLS helper, Foundation and Governance suites: 46 passed. Final local stack destroyed; stack list empty.
- Remaining: extension-owned DDL test; protected first Director bootstrap; non-Director cross-department exception (currently fail-closed); missing Admin RPC contracts; complete Buyer browser journey. No hosted DB, `main`, Live/Production, DNS or deployments changed.


## 2026-11-14 — Buyer Demand quotation privacy policy fixed in local recovery test

- Continued Buyer-first validation on the existing persistent Sandbox and only on nexora-development.
- Fresh disposable local native PostgreSQL 17 stack: Foundation/RLS candidates #12/#13, all 38 active migrations, and Admin Governance recovery candidate #14 applied successfully.
- Audit 24 first revealed stale policy-name expectations; corrected the recovery-only audit to match the final active policy names. The audit then passed.
- Behavior suite 26 was aligned with the final schema (business_profiles.id, public_businesses sync trigger, no Product sale-channel field, numeric available_quantity string).
- The behavior suite exposed a real quotation SELECT RLS defect: the Seller-offer policy queried private buyer_demands.buyer_id directly although authenticated intentionally lacks that column privilege. This broke offer SELECT during policy evaluation.
- Added recovery-only patch 30 with a narrow SECURITY DEFINER private.is_buyer_demand_owner(uuid) helper; empty search_path, active Buyer check, explicit owner, anon/PUBLIC EXECUTE revoked, authenticated-only EXECUTE. Buyer identity remains private.
- After patch 30, read-only audit 24 and transactional behavior suite 26 both passed. Synthetic checks cover Demand routing, anonymous projection, Buyer ownership, Seller inbox isolation, quotation creation/read, unrelated Buyer denial, unmatched Seller denial, duplicate offer denial, Buyer-ID spoof denial, required-date validation and grants.
- No active migration was edited; #30 remains recovery-only until a natural forward-migration timestamp can be generated after the current latest version. Real JWT/PostgREST/browser/mobile tests remain open.
- No hosted NEXORA-TEST, Live/Production, main, DNS or deployment changes.


## 2026-11-14 — Buyer Demand negotiation and order conversion tests passed

- Expanded recovery-only behavior test 26 to cover both order conversion paths: Seller acceptance of a Buyer counter creates an accepted order with an accepted event; Buyer acceptance of a Seller counter creates a pending order, then the assigned Seller confirms it.
- Added counter-turn-taking checks, same-side repeat-counter denial, Buyer rejection, expired-quotation denial and negotiation-history visibility isolation.
- Local PostgreSQL 17 test suite completed with 27 PASS notices; all test data was rolled back and post-test counts for synthetic Auth users, Demands and offers were zero.
- A second private-column policy dependency was found in seller_offer_negotiations_participant_read. Recovery patch #30 now uses the same private ownership helper for both offer and negotiation-history SELECT policies; no Buyer ID grant was added.
- Termux runner #27 was updated to fetch immutable current commits for audit #24, behavior #26 and patch #30; fixture-only patch #28 is skipped when the full migration schema already exists.
- Remaining: duplicate-order/concurrency tests, inactive participant tests, broader order-state transitions, real JWT/PostgREST and browser/mobile E2E. Patch #30 remains recovery-only pending a genuine forward migration timestamp.
- No active migration was edited; no hosted database, Live/Production, main, DNS or deployment changed.


## 2026-11-14 — Buyer Demand lifecycle and concurrent order tests passed

- Extended recovery-only behavior test 26 to verify inactive Buyer negotiation denial, inactive Seller order-acceptance denial, Seller pending → accepted → ready transitions, Buyer ready → completed transition, Buyer cancellation of pending order, and Seller rejection with a mandatory reason.
- Re-ran read-only privacy/routing audit 24 and behavior suite 26 on a fresh disposable PostgreSQL 17 stack after all 38 active migrations and recovery candidates #12–#14. All 34 PostgreSQL PASS notices succeeded; the behavior suite rolled back and synthetic Auth users, Demands and offers returned to zero.
- Ran a separate two-session row-lock race test on one quotation. Concurrent Buyer acceptance yielded exactly one commerce order, one accepted negotiation turn and one `created` order event. The second transaction waited for the first lock, then was rejected because the quotation had already been ordered.
- Found and corrected test-harness issues without weakening policies: test role SQLSTATE expectations now match `42501`; verified-review private table is not queried under `authenticated`; lifecycle test uses a dedicated Demand to respect the one-offer-per-Seller/Demand unique key.
- Repaired Termux runner #27: corrected malformed curl/download quoting, added the recovery-only patch #30 download, preserved strict `nexora_test` target and prerequisite/session checks, and pinned immutable behavior-test revision.
- Verified runner shell syntax with `bash -n`. Full real JWT/PostgREST/browser/mobile E2E remains pending.
- Buyer Demand verified-review eligibility remains deliberately unasserted: existing review schema supports product/service/logistics subjects, while a Demand quotation order does not guarantee a linked Seller product ID. Do not fabricate a listing subject or widen review types; design a business-level review subject or explicit product association first.
- Destroyed the disposable native stack and verified `stack list` returned empty. No active migration changed; no NEXORA-TEST, Live/Production, `main`, DNS or deployment changed.


## 2026-11-14 — Real Auth JWT and PostgREST Buyer journey passed

- Started a separate disposable native Supabase stack with PostgREST and Auth enabled. Used synthetic Auth signup/password sessions only; signup trigger created Buyer profiles with active status by default.
- Replayed the RLS helper + Foundation + all 38 active migrations + Admin Governance recovery candidate, then applied recovery-only Buyer ownership patch #30 locally.
- Real Auth JWT/PostgREST checks passed: Buyer Demand insert (201), Buyer own read/update, unrelated Buyer read/update denial, anonymous safe public Demand view, Buyer ID column denial (403), approved Seller inbox routing, Seller quotation insert (201), Buyer quotation read, unrelated Buyer quotation denial, Buyer counter RPC, Seller acceptance RPC, Buyer order read, Seller ready RPC, Buyer completion RPC, completed order read, unrelated Buyer order denial, repeat completion denial (403), and Seller direct Inbox insert denial (403).
- Final direct catalog audit: 41 public tables, 0 public tables without RLS, 0 SECURITY DEFINER functions without explicit search_path; Buyer ID SELECT denied to anon/authenticated; anon cannot execute private Buyer ownership helper; authenticated cannot directly INSERT/DELETE Demand Inbox; public Demand view is SECURITY INVOKER.
- Local SQL behavior suite 26 also passed all 34 PostgreSQL PASS notices; two-session concurrent Buyer acceptance produced exactly one order, one accepted negotiation turn and one created event.
- Supabase CLI `db lint` did not attach to the named native stack despite `stack status` reporting ready; direct catalog/security checks and the API integration suite were run instead. `db advisors` was not counted as passed.
- Remaining: Browser/mobile UI E2E; Buyer Demand verified-review subject design (no guaranteed Seller product ID on a Demand quotation); recovery patch #30 must become a genuine forward migration after a natural CLI timestamp; repeat tests after forward migration.
- All test accounts and rows existed only in the disposable local stack. No hosted NEXORA-TEST, Live/Production, `main`, DNS or deployment changed.

### 2026-11-14 — Corrected Buyer frontend audit
- Correction: the previous appended note incorrectly said the Buyer Demand UI was absent. Inspection of the actual `marketplace.js` confirms the `demandForm` submit handler, Buyer Demand insert/dashboard, Seller Demand Inbox, Seller quotation insert, and public projection query already exist.
- Active migration `20261112153000_publish_open_demands_without_buyer_identity.sql` provides the anon open-Demand RLS policy and column-limited public grants excluding `buyer_id`.
- Active migration `20261114160000_demand_inbox_quotations_subcategories.sql` adds Buyer Demand subcategory and creates/recreates `public_buyer_demands` with `security_invoker=true`, including subcategory, with restricted view and base-table grants.
- Static checks: seven frontend JS files parse; HTML parses with 175 unique IDs; all local script paths resolve; Demand form field names and the active subcategory schema addition align. Submit, Buyer dashboard, Seller inbox, quotation and public view code paths are present.
- Browser/mobile E2E remains open; sandbox has no browser binary or Playwright/Cypress runtime. Do not infer runtime UI success from static checks.
- Recovery patch #30 is not the public Demand projection; it is a separate local-only offer SELECT-policy patch and remains outside active migrations.
- Review subject for Buyer Demand orders remains an unresolved design item; no fabricated product association or review schema change.
- Migration CLI 3.1.0 is available from the sandbox's npx cache. Current UTC is 2026-11-14 12:17; latest active migration is timestamped 20261115120000. A newly generated timestamp now would sort before that migration, so no new migration was generated or renamed artificially. Wait for the CLI's natural timestamp to exceed the latest migration before adding a forward migration.
- No Production, Live, NEXORA-TEST, `main`, deployment, DNS, or paid-service changes.

### 2026-11-14 — Business Verified Review design and privacy gate
- Created `docs/NEXORA_BUSINESS_VERIFIED_REVIEW_DESIGN.md` (design only; no SQL or frontend change). Buyer Demand orders use `commerce_orders.listing_type='buyer_demand'` and have no guaranteed Product ID; proposed review subject is the Seller's unique `business_profiles.id`, never a fabricated Product ID.
- Confirmed current review UI helpers in `marketplace.js` are generic and call `get_listing_review_summary`, `get_my_review_eligibility`, and `submit_verified_listing_review`; Business detail invocation remains to be implemented after schema/API gate.
- **New critical review privacy finding:** `listing_reviews` grants table-level SELECT to anon/authenticated. Its published-row RLS policies do not hide columns, so direct PostgREST selection can request `buyer_id`, `reviewed_by`, and `moderation_note`. Frontend selecting only safe columns is not a security boundary. Forward migration must revoke table-level SELECT and grant only explicit public columns, then test denied access to private columns.
- Business eligibility design: create private eligibility only on actual Buyer Demand order transition to completed, resolve Business ID server-side from unique `business_profiles.seller_id`, make insert idempotent, backfill already-completed Demand orders, and preserve one review per Buyer/Business using the existing unique review index.
- Design doc defines trigger/RPC extension, privacy grants, frontend contract and 20 isolated replay/API regression cases. No review schema, frontend, hosted DB or deployment change made.
- Latest active migration remains `20261115120000_multilingual_chat_foundation.sql`; natural CLI timestamp is not yet later, so no migration file was generated or manually renamed.
- Next: when timestamp is naturally later, implement a forward migration only after Foundation/history reconciliation; run clean disposable replay, concurrency, Auth JWT/PostgREST column-grant tests, then Business detail UI tests. Browser/mobile E2E remains open.
- Prepared recovery-only review privacy patch `31_listing_reviews_column_grants_recovery_candidate.sql` and read-only grant test `32_listing_reviews_column_grants_recovery_test.sql`. Not executed: full Foundation/migration replay is not yet certified. These files are not active migrations and do not mean the privacy issue is fixed.


## 2026-11-14 — Review privacy recovery candidate tightened

- Re-reviewed the active staged review schema and frontend query. The public review UI selects only `id`, `rating`, `review_title`, `review_body`, `reviewer_label`, `purchased_quantity`, and `created_at`, while filtering on `listing_type`, `listing_id`, and `review_status`; the column allowlist includes those required fields plus the summary RPC's required `rating`/filter columns.
- Tightened recovery-only candidate #31: revoke all table-level privileges from `PUBLIC`, `anon`, and `authenticated`; explicitly revoke separate column-level SELECT on every current private/internal column (`buyer_id`, `reviewed_by`, `reviewed_at`, `moderation_note`, `updated_at`); then grant only the ten public columns.
- Expanded recovery test #32 to assert that all five withheld columns are inaccessible to both API roles, all ten allowlisted columns remain readable, table-level SELECT is absent, and the SECURITY INVOKER summary RPC still executes under `anon`.
- Updated the Business review design gate to document why table-level REVOKE alone is insufficient when independent column grants exist.
- `git diff --check` passed. No SQL execution or database verification was attempted because the Foundation/migration replay gate remains unresolved. Candidate/test remain recovery-only; no active migration, hosted database, Live/Production, `main`, DNS or deployment changed.


## 2026-11-14 — Review privacy recovery test strengthened

- Revisited recovery-only candidate #31 and test #32 against the exact `listing_reviews` schema and `get_listing_review_summary` SECURITY INVOKER query. The current schema has ten intended public columns and five private/internal columns; the summary reads only `rating`, `listing_type`, `listing_id`, and `review_status`.
- Strengthened test #32 to check all table-level privilege classes (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER), inspect every live column against the explicit public allowlist (so future columns default to denied), and execute the safe-column query plus summary RPC under both `anon` and `authenticated`.
- Static review confirms the recovery candidate revokes table-level privileges and the five existing private-column SELECT grants before granting only the ten allowlisted columns. The patch and expanded SQL test have **not** been executed against PostgreSQL in this resumed session: this Sandbox has no local PostgreSQL client or running database service, and Docker/Podman are unavailable. The previous disposable PostgreSQL replay and Buyer JWT/PostgREST tests remain valid for the state tested at that time, but do not verify this later review-grant patch.
- No active migration or frontend code changed. Candidate #31/#32 remain recovery-only and unexecuted; no hosted DB, `main`, Live/Production, DNS, deployment, or paid service changed.


## 2026-11-14 — Upazila Agent network and direct-seller fulfilment requirement

- Added user-approved product requirement/design: NEXORA will appoint one or more authorized Agents per Upazila to collect goods from farmers/businesses, record receipt and quantity, package/label goods, deliver them to NEXORA-designated Drop Points, and deliver NEXORA-authorized seller payouts with recipient acknowledgement.
- Sellers may alternatively fulfil orders directly; Agent-assisted collection is optional, not a mandatory marketplace gate.
- Agent is a distinct field-operations/payout role, not automatically equivalent to the existing Porter/Transport Provider. Onward transport from Drop Point remains a separately assigned leg.
- Added `docs/NEXORA_UPAZILA_AGENT_NETWORK_DESIGN.md` covering operational sequence, custody and quantity reconciliation, partial/damaged/short goods, least-privilege territory access, seller payout controls, audit, governance, and unresolved operational/compliance decisions.
- Existing Delivery Network foundations do not establish that Agent collection, packaging, Drop Point custody, seller payout delivery or payout reconciliation are implemented. This is a new requirement; implementation remains pending.
- Open decisions include payout method and trigger, Agent compensation and packaging cost, Drop Point ownership/operation/liability, Upazila coverage, whether Buyer Demand orders are included, and direct-seller handover route.
- No role, SQL/schema/RPC/migration, payment or payout integration, database, frontend, deployment, Production, `main`, DNS or paid service was changed. This commit records requirements/design only.

## 2026-11-14 — Upazila Agent assisted-selling and commission model expanded

- Updated `docs/NEXORA_UPAZILA_AGENT_NETWORK_DESIGN.md` to distinguish two seller operating models:
  1. **Agent-represented selling:** for low-literacy farmers/businesses, an authorized Upazila Agent performs the NEXORA selling workflow on the actual farmer/business's behalf, including sales-centre/listing support, order coordination, collection, quantity/condition records, packaging and Drop Point/transport handover. The underlying goods owner/source and Seller consent remain traceable.
  2. **Independent/direct Seller:** capable farmers/businesses manage their own Seller account, listings, prices, negotiation and orders; the NEXORA Agent is still responsible for collection, packaging, Drop Point handover and transport coordination.
- Added the approved commercial principle that NEXORA receives a defined platform charge from each sale and the Agent receives a defined commission/service share for the applicable assisted-selling and/or logistics work. Seller net proceeds and every deduction must be transparently itemized before order acceptance.
- Explicitly separated gross sale value, NEXORA charge, Agent commission, delivery/packaging costs, adjustments/refunds and Seller net payout. Fee rates, calculation base and the two models' commission schedules remain undecided.
- Clarified that the Agent is not automatically the legal merchant of record, goods owner, Porter/Transport Provider, or Admin. The real farmer/business identity, Agent representation/consent and audit actor must remain distinct; legal/payment/tax review is required before money handling.
- Added effective-dated fee schedule, maker-checker, payout reconciliation, custody/quantity exceptions, Seller acknowledgement and territory-scoped Agent controls. No payment gateway, fee engine, payout ledger, role, SQL/schema/RPC/migration or frontend has been implemented.
- Open decisions include commission percentages/basis, payout trigger/method, legal agency status, packaging/transport cost allocation, Drop Point liability, Upazila coverage, Buyer Demand applicability and whether direct Sellers have any exception to mandatory Agent collection.
- Documentation only on `nexora-development`; no NEXORA-TEST, Live/Production, `main`, DNS, deployment or paid service changed.


## 2026-11-14 — Agent-to-Agent procurement and Buyer-side agency added

- Added an inter-area procurement model to `docs/NEXORA_UPAZILA_AGENT_NETWORK_DESIGN.md`, using the user's Sirajdikhan, Munshiganj example: a local Agent collects purchase requirements from local market businesses, records them with the actual represented Buyer and required-by details, searches products/offers advertised by supplying Agents in other areas, and places/coordinates purchase orders against those offers.
- Clarified that Agents can operate in distinct transaction capacities: Buyer-side procurement representative, Seller-side sales representative, and collection/transport coordinator. In one inter-area transaction, one Agent may represent the local Buyer and another Agent may represent the supplying Seller.
- Added source-to-destination fulfilment: supplying-side collection/verification/packaging, inter-area transport coordination, receiving-area Agent/Drop Point handover, and local delivery/receipt, with separate custody events and quantity reconciliation.
- Added unique Demand-to-order linkage, offer/price/quantity snapshots, business authorization, protected identity/contact, explicit partial fulfilment/shortage/damage/substitution/return states, transparent NEXORA and multi-Agent commission allocation, and conflict-of-interest/maker-checker controls.
- Defaulted the design to disclosed agency: the local business remains the represented Buyer and the underlying farmer/business remains the represented Seller; Agent action does not automatically make the Agent the legal Buyer, Seller, goods owner or merchant of record. Whether an Agent may instead buy in its own name and resell remains an open business/legal decision.
- Open decisions now include disclosed agency versus principal/reseller trading, private/targeted versus public Demand, inter-area and final-mile delivery responsibility, multi-Agent commission split, and proof of Buyer authorization/payment commitment.
- Design/tracker documentation only on `nexora-development`; no roles, permissions, SQL/schema/RPC/migrations, payment/payout/commission engine, frontend, hosted database, Live/Production, `main`, DNS, deployment or paid services changed.

## 2026-11-14 — Agent-to-Agent distribution and illustrative fee allocation

- Updated `docs/NEXORA_UPAZILA_AGENT_NETWORK_DESIGN.md` with the latest user-confirmed model: for the small-supplier assisted route, no NEXORA Unregistered Seller Record/login is required; the Agent is the direct Seller on NEXORA and keeps their own source/purchase/supplier-payment records.
- Confirmed the Selling Agent pays the onward transport charge; NEXORA arranges the inter-area transport to the destination-area Agent; the Local Distribution Agent receives, checks and delivers the goods to the Buyer. Carrier and Local Distribution Agent are paid separately for verified work.
- Added illustrative, Admin-configurable defaults only: Agent-Seller marketplace commission 3%; Direct-Seller marketplace commission 3%; onward transport allocation 50% inter-area carrier / 36% Local Distribution Agent / 14% NEXORA logistics coordination margin. Example calculation uses BDT 10,000 goods value and BDT 500 transport charge; these are not approved launch rates or live settlement rules.
- Added JSON sample configuration, calculation bases, 100% transport-share validation, effective-dated/versioned rates, maker-checker approval, immutable order rate snapshots, separate ledger lines and verified-delivery payout gates.
- Documentation/configuration example only. No app/frontend/backend/SQL/schema/RPC/migration/payment/payout code or live fee engine implemented. Do not bypass migration-history/Foundation reconciliation, isolated replay, legal/payment-provider review or explicit release approval. No NEXORA-TEST, Live/Production, `main`, DNS, deployment or paid service changed.

## 2026-11-14 — Configurable financial calculation core (initial code)

- Added `financial-config.js` as a pure financial domain module. Rates are supplied as approved, effective-dated configuration; no commission or transport rate defaults are embedded in the module.
- Added validation for versioned schedule metadata, Wholesale/Retail commission basis, mandatory Buyer Agent fee when the service is used, and transport allocation totaling exactly 10000 basis points.
- Added effective-schedule selection, integer-minor-unit/basis-point calculations, and order fee snapshots carrying the schedule ID/version.
- Loaded the module before `marketplace.js` so later integration can use `window.NEXORA_FINANCE`.
- Verified locally with Node: valid schedule, Wholesale/Retail fee calculation, Buyer Agent fee on/off behavior, exact transport-share validation, and order snapshot checks passed.
- This is domain logic only: no persistent configuration UI/API, Database table, RLS, RPC, migration, payment, wallet, escrow, payout or settlement integration has been implemented. Existing migration-history/Foundation blockers remain. No Live/Production, `main`, DNS, deployment or paid service changed.

## 2026-11-14 — Financial core hardening and latest business decisions

- Made Wholesale, Retail and Buyer Agent fee calculation bases configuration-driven rather than fixing a commission base in code.
- Rejects overlapping approved fee schedules instead of silently choosing one.
- Ensures rounded transport allocations reconcile exactly to the transport charge by assigning the minor-unit rounding remainder deterministically.
- Updated the Agent Network design with the user's latest superseding decisions: Seller Agent resells as own NEXORA Seller (no unregistered Seller record/profile); separate Wholesale/Retail listings; mandatory Buyer Agent fee only when that service is used; Seller Agent pays onward transport; NEXORA assigns receiving-area Local Distribution Agent; `buyer_received` settlement trigger; Buyer Demand orders use the same fulfilment path.
- Financial rates and calculation bases remain unapproved and must be supplied through versioned, effective-dated configuration; no default rates are embedded in the financial module.
- Local Node checks passed for configurable bases, Wholesale/Retail calculation, Buyer Agent fee on/off, exact transport allocation reconciliation, overlapping schedule rejection and invalid split rejection.
