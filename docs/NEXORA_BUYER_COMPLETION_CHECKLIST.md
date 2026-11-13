# NEXORA — Buyer বিভাগ সম্পূর্ণকরণ তালিকা

Updated: 2026-11-13  
Branch: `nexora-development`  
Status: **Implementation review in progress — not complete**

এই নথি Buyer বিভাগের একক সমন্বিত checklist। এটি বর্তমান GitHub কোড ও migration chain পর্যালোচনার ভিত্তিতে তৈরি। কোনো Hosted Supabase বা Production পরিবর্তন/পরীক্ষা করা হয়নি।

## 1. Buyer-এর স্থায়ী ব্যবসায়িক নিয়ম

- Buyer-এর কোনো Wholesale/Retail account category থাকবে না; সব Buyer সব approved Wholesale ও Retail পণ্য দেখতে ও অর্ডার করতে পারবে।
- Buyer account তৈরি ও ব্যবহার করতে Admin approval লাগবে না (email confirmation বা platform-এর সাধারণ authentication শর্ত প্রযোজ্য)।
- Buyer Dashboard-এ কোনো category switch থাকবে না; Buyer visibility সবসময় universal।
- Seller প্রতিটি Product Listing-এ Wholesale অথবা Retail নির্বাচন করবে; এই নির্বাচন Buyer-এর দেখার অধিকার সীমিত করবে না।
- Buyer Demand প্রকাশ্য হতে পারে, কিন্তু Buyer-এর নাম, পূর্ণ Profile, email, phone বা ব্যক্তিগত যোগাযোগের তথ্য প্রকাশ করা যাবে না।
- Buyer Demand-এ প্রয়োজনীয় পণ্যের বিবরণ, পরিমাণ, গন্তব্য এবং **প্রয়োজনের তারিখ** থাকবে।
- যোগাযোগের অনুরোধ গ্রহণ না করা পর্যন্ত ব্যক্তিগত কথোপকথন শুরু হবে না।
- Buyer নিজের অর্ডার দেখতে, অনুমোদিত অবস্থায় বাতিল করতে এবং পণ্য/সেবা পাওয়ার পর completion নিশ্চিত করতে পারবে।

## 2. বর্তমান বাস্তবায়নের পর্যালোচনা

| ক্ষেত্র | বর্তমান অবস্থা | পর্যালোচনার ফল |
|---|---|---|
| Buyer signup | Frontend staged | Buyer category selector নেই; universal Buyer access; tests pending |
| OAuth signup | Migration staged | Google/Facebook signup Buyer হিসেবে শুরু করার নিয়ম আছে; final trigger chain পরীক্ষা বাকি |
| Buyer account activation | Partially verified | Buyer profile active করার migration logic আছে; hosted Auth flow পরীক্ষা বাকি |
| Category switch | Removed | Buyer account-level category নেই; কোনো category-specific policy নেই |
| Product discovery | Frontend staged | সব approved Wholesale ও Retail listing সব Buyer এবং public visitor দেখতে পারে |
| Product visibility | Database migration staged | সব active Buyer উভয় market_category-এর approved listing দেখতে পারবে |
| Product details | Frontend staged | Product ID, Business Display Name, specification, price, MOQ/stock/tiers দেখায় |
| Buyer Demand form | Frontend staged | Product, category, subcategory, description, specifications, quantity, optional budget, currency, destination এবং required date |
| Public Demand Board | Migration + frontend staged | Open demands প্রকাশ; identity/contact fields view-তে নেই বলে migration-এ নির্ধারিত |
| Buyer Demand privacy | Partially verified | Public view security_invoker; anon column grants সীমিত; hosted DB-তে grants/RLS পরীক্ষা বাকি |
| Seller quotations | Frontend + migration staged | Buyer নিজের Demand-এর জন্য Seller offers দেখতে পারে; quotation compare/accept করার পূর্ণ workflow এখনো নেই |
| Product inquiry/chat | Frontend + migration staged | Inquiry RPC conversation ও invitation তৈরি করে; গ্রহণের পর chat |
| Orders | Frontend + migration staged | Product/service order request, status, cancel ও completion confirmation |
| Verified reviews | Frontend + migration staged | Completed verified purchase ছাড়া review নয়; duplicate review block |
| Profile privacy | Foundation staged | Public identity projection সীমিত; Buyer-এর full profile অন্যদের কাছে প্রকাশ নয় |
| Wallet/payment | Not implemented / placeholder | Buyer Dashboard-এ wallet balance UI আছে, কিন্তু প্রকৃত wallet ledger/payment integration প্রমাণিত নয় |
| Delivery tracking | Not fully verified | Buyer-এর order form-এ delivery address আছে; Porter assignment/tracking Buyer UI integration আলাদাভাবে পরীক্ষা করতে হবে |
| Browser/mobile E2E | Pending | কোনো বর্তমান browser বা hosted integration test run হয়নি |

## 3. Buyer-এর কাজের সম্পূর্ণ প্রবাহ

1. Homepage থেকে Buyer নির্বাচন করে signup; কোনো Wholesale/Retail account category নির্বাচন নেই।
2. Authentication সম্পন্ন করে Buyer Dashboard-এ প্রবেশ।
3. সব approved Wholesale ও Retail product খোঁজা, filter করা ও details দেখা।
4. Seller-এর সঙ্গে inquiry পাঠানো; invitation গ্রহণের পর chat/call/file sharing।
5. পণ্য অর্ডার request পাঠানো; Seller-এর order response দেখা।
6. Seller পণ্য পাঠানোর/সেবা সম্পন্নের পর Buyer receipt/completion নিশ্চিত করা।
7. Verified purchase-এর ভিত্তিতে review দেওয়া।
8. বিকল্পভাবে Buyer Demand পোস্ট করা, required date ও destination দেওয়া, Seller quotations তুলনা করা, Demand close/cancel করা।
9. Delivery/transport status ও support flow Buyer Dashboard-এ সংযুক্ত করা.

## 4. এখনো সমাধান/পরীক্ষা বাকি

### B-01 — Auth trigger ও migration chain
- [x] Final staged `public.handle_new_user()` definition Buyer-এর legacy category NULL এবং Seller-এর legacy categories empty রাখে; legacy Buyer/Seller category metadata profile-এ সংরক্ষণ করে না।
- [x] Social OAuth provider-কে Buyer-only করা হয়েছে—শুধু Google/Facebook নয়, email/phone ছাড়া যেকোনো provider Buyer হবে। Backend role allowlist শুধু Buyer/Seller/Porter; user-editable metadata দিয়ে Admin/Director role তৈরি করা যায় না।
- [x] Porter registration profile-কে pending করে এবং আলাদা pending `porter_account_reviews` row তৈরি করে; Admin approval workflow আলাদা।
- [x] Buyer ও Seller signup profile active হয়; Seller public listing/business visibility আলাদা Admin approval gate-এ থাকে।
- [x] Trigger function SECURITY DEFINER, empty search_path এবং PUBLIC/anon/authenticated EXECUTE revoke যোগ করা হয়েছে।
- [x] Frontend source review: signup role allowlist Buyer/Seller/Porter; Google/Facebook UI Buyer-only; non-active account sign-out, pending Porter exception সহ।
- [x] Local B-01 alignment/regression script চালানো হয়েছে: Buyer/Seller category metadata ignore, OAuth provider Buyer-only, Admin/Director rejection, Porter pending, trigger SECURITY DEFINER/empty search_path এবং anon/authenticated EXECUTE revoke — সব PASS; test users ROLLBACK হয়েছে।
- [ ] Real Supabase Auth signup/confirmation, JWT, hosted trigger attachment, RLS and browser E2E পরীক্ষা; migration history reconcile না হওয়া পর্যন্ত deploy নয়।

### B-02 — Product visibility ও sale-type integrity
- [x] Buyer signup ও Dashboard থেকে account-level Wholesale/Retail selector সরানো হয়েছে।
- [x] Marketplace, Product Detail এবং Buyer Dashboard থেকে Buyer-category filter সরানো হয়েছে।
- [x] Seller Product Listing-এ Wholesale/Retail দুটো sale type-ই বেছে নিতে পারে; account-level Seller category gate সরানো হয়েছে।
- [x] Product SELECT RLS-এ সব authenticated user-কে approved Wholesale ও Retail listing দেখার অনুমতি দেওয়া হয়েছে।
- [x] Anonymous visitor-এর জন্য approved listing-এর safe column projection এবং সীমিত public Business Display Name/Location access যোগ করা হয়েছে; seller_id ও admin review fields anon-এর জন্য grant করা হয়নি।
- [x] Product Inquiry RPC থেকে Buyer category matching gate সরানো হয়েছে।
- [x] পরবর্তী Inventory/MOQ migration-এর Product Order RPC-তেও থাকা legacy `buyer_category = market_category` gate সরানো হয়েছে; active Buyer, approved listing/business, MOQ ও stock validation বজায় আছে।
- [x] Local-only read-only visibility verification script তৈরি হয়েছে: `supabase/recovery-not-for-deployment/local-setup/20_dual_market_visibility_read_only_verification.sql`; সীমিত fixture-এ চালানো হয়েছে: ৭টি catalog/policy/safe-column check PASS। Active Buyer/Seller profile ও sample listing না থাকায় account-level listing count comparison SKIP; full Marketplace schema, RPC, JWT/PostgREST ও hosted RLS এতে পরীক্ষা হয়নি।
- [x] Buyer Demand matching থেকে Buyer/Seller account category condition সরানো হয়েছে; product category/subcategory ও approved Business Profile matching বজায় আছে।
- [x] সর্বশেষ কার্যকর Seller listing edit/review RPC-তে account-level `seller_categories` gate নেই; per-product sale type ও commercial validation থাকে।
- [x] Auth trigger-এ legacy Buyer/Seller account market category NULL/empty রাখা হয়েছে।
- [ ] Read-only verification script চালিয়ে anonymous, Buyer, Seller ও Admin listing counts, safe-column grants এবং policy/RPC definitions যাচাই; marketplace schema না থাকলে script নিরাপদে SKIP করবে।
- [ ] Product Inquiry, order creation, listing edit/review ও Buyer Demand routing local DB এবং real authenticated session-এ পরীক্ষা.

### B-03 — Buyer Demand privacy ও lifecycle
- [x] Staged source review: `public_buyer_demands` SECURITY INVOKER view-তে Buyer ID/name/email/phone/profile/contact fields নেই; anonymous base-table grants are column-limited and omit `buyer_id`.
- [x] Staged RLS review: Buyer Demand INSERT/SELECT/UPDATE owner-scoped; Seller can read open Demand only through own inbox; Admin path remains separate.
- [x] Staged inbox review: `buyer_demand_inbox` RLS + Seller-owned SELECT; authenticated direct INSERT/UPDATE/DELETE revoked.
- [x] Staged quotation INSERT requires active Seller, approved public Business Profile, own inbox row and open Demand; one offer per Seller/Demand unique constraint.
- [x] Buyer UI closes/cancels only own open Demand; quotation INSERT policy blocks closed/cancelled Demand; public board view filters open only.
- [x] Required date is NOT NULL and constrained to current_date or later; subcategory constraints and public projection field are present in final migration.
- [x] Demand routing source uses approved Product category/subcategory + active Seller + approved public Business Profile; no Buyer/Seller account-category or Wholesale/Retail market_category gate.
- [x] Read-only catalog audit 24 initially executed and correctly SKIPped because full Demand schema was absent from visibility fixture 21. A separate local-only Demand fixture 25, behavior tests 26 and Termux runner 27 are now staged to enable focused local validation; user execution pending.
- [ ] Run local Demand fixture 25 + audit 24 + behavior tests 26 using runner 27; inspect every PASS/FAIL.
- [ ] Verify privacy, ownership, Seller inbox, quotations and status transitions under real JWT/PostgREST sessions and browser E2E.
- [ ] Buyer quotation acceptance, counter-offer and quotation-to-order conversion workflow remains unimplemented.

### B-04 — Orders, stock ও pricing
- [ ] Buyer account category ছাড়া যেকোনো approved Wholesale/Retail product order করতে পারে যাচাই।
- [ ] MOQ, Retail single-unit default, quantity tiers, stock reservation ও insufficient-stock rejection একই নিয়মে কাজ করে।
- [ ] Order cancel/complete শুধুমাত্র অনুমোদিত status transition-এ হয়।
- [ ] Payment না থাকলে UI স্পষ্টভাবে জানায়—order request মানেই payment বা delivery booking নয়।
- [ ] Buyer order list-এ প্রয়োজনীয় order detail ও delivery progress দেখানো।

### B-05 — Quotations, communications, reviews ও support
- [ ] Buyer quotation acceptance: বর্তমানে Buyer Dashboard quotation দেখায়, কিন্তু গ্রহণ/প্রত্যাখ্যান বা quotation থেকে order তৈরির end-to-end action নেই। Seller-এর offer acceptance, quantity/price lock, order conversion এবং competing offer handling-এর নিয়ম নির্ধারণ প্রয়োজন।
- [ ] Seller invitation accept না করা পর্যন্ত Buyer message পাঠাতে পারে না।
- [ ] Audio/video/file sharing এবং history শুধু conversation participants দেখতে পারে।
- [ ] Admin ব্যক্তিগত chat-এর content দেখতে পারে না—পূর্বের privacy decision অনুযায়ী।
- [ ] Verified review কেবল completed purchase-এর পর; একজন Buyer এক listing-এ একবার।
- [ ] Complaint/support escalation এবং Buyer-এর support status দেখা।

### B-06 — Dashboard completeness
- [ ] Sale type label ও demo text product-এর নির্বাচিত Wholesale/Retail ধরন ঠিকভাবে দেখায় যাচাই।
- [ ] Wallet balance placeholder-কে বাস্তব wallet না বলা; wallet/payment feature বাস্তবায়ন না হওয়া পর্যন্ত স্পষ্টভাবে unavailable/coming later রাখা।
- [ ] Buyer delivery tracking ও Porter handoff UI সংযুক্ত।
- [ ] Mobile responsive, keyboard accessibility, loading/error/empty states পরীক্ষা।
- [ ] Browser E2E: signup, browse both sale types, direct URL, demand, offers, inquiry consent, order, completion, review।

## 5. বর্তমান কোডে পাওয়া নির্দিষ্ট নোট

1. Buyer signup-এ Wholesale/Retail account category নেই; OAuth registrations Buyer-only থাকে।
2. Buyer Dashboard-এ category switcher নেই।
3. `marketplace.js`-এর product query, detail page এবং Buyer Dashboard উভয় sale type দেখায়।
4. Product SELECT policy-তে approved public listings-এর safe columns anon visitor-কে এবং approved listings authenticated users-কে দেয়; Buyer category gate নেই।
5. Product Inquiry ও Order RPC active Buyer এবং approved listing/business যাচাই করে, কিন্তু sale type অনুযায়ী Buyer restriction নেই।
6. Buyer Demand routing approved product category/subcategory ও Seller Business Profile অনুযায়ী হয়; Wholesale/Retail category দিয়ে Demand visibility ভাগ করা হয় না।
7. Seller signup-এ account-level sale category নেই; Seller প্রতিটি Product Listing-এ Wholesale অথবা Retail নির্বাচন করে.

## 6. সমাপ্তির শর্ত

Buyer বিভাগকে **সম্পূর্ণ** বলা হবে কেবল যখন:
- সব B-01 থেকে B-06 critical checks সমাধান হয়েছে;
- migration history নিরাপদে reconcile করে isolated DB-তে rehearsal হয়েছে;
- Buyer-এর happy-path ও negative authorization tests পাস করেছে;
- Buyer privacy, Demand privacy, public product safe-column RLS, order state এবং chat consent বাস্তব authenticated session-এ যাচাই হয়েছে;
- mobile/browser E2E-এর ফল নথিভুক্ত হয়েছে;
- কোনো unresolved blocker গোপন না রেখে চূড়ান্ত closeout report তৈরি হয়েছে।

## 7. নিরাপত্তা ও deployment সীমা

- এই checklist তৈরির সময় কোনো SQL চালানো হয়নি।
- কোনো Live Supabase, Production, DNS বা `main` পরিবর্তন করা হয়নি।
- Migration history divergence unresolved; migration replay/deploy এখনো blocked।
- Local superuser SQL tests hosted Supabase Auth/JWT/PostgREST/RLS-এর বিকল্প নয়।


## 8. Updated Buyer visibility and Seller sale-type rule (2026-11-13)

- Buyer account has no Wholesale/Retail category; signup and dashboard category selectors are removed.
- Every active Buyer can discover all Admin-approved Wholesale and Retail product listings.
- Buyer product detail, inquiry, order creation and product dashboard no longer reject a listing based on Buyer category.
- Seller selects Wholesale or Retail separately on each Product Listing. This sale type remains visible as product information; it does not restrict who can view the listing.
- Buyer Demand matching is based on product category/subcategory and Seller's approved public Business Profile, not Buyer/Seller account market categories.
- Legacy profiles.buyer_category and profiles.seller_categories fields are retained only for migration compatibility, cleared to NULL/empty, and must not be used for authorization.
- The later inventory migration originally retained a legacy Buyer-category order gate; this was removed from the final Product Order RPC definition.
- A local read-only verification script is staged at `supabase/recovery-not-for-deployment/local-setup/20_dual_market_visibility_read_only_verification.sql`. It checks catalog policy/grants and, when the complete marketplace schema and an active Buyer exist, compares anon, Buyer, Seller and Admin-visible approved listings. It creates no data and changes no schema.
- This is staged source-code work only. No migration was run, no local SQL/browser tests were run in this turn, and Hosted Supabase remains untouched.



## 9. B-03 Buyer Demand local behavior verification (2026-11-13)

- User ran the immutable Termux runner at commit `f202a630dc4e2503daada8ef2130cab90f3b88a6` successfully on local `nexora_test`.
- Local Demand privacy/routing catalog audit: 8 PASS checks.
- Local transactional behavior suite: 12 PASS checks covering category/subcategory routing independent of Wholesale/Retail, approved-product update routing, anonymous safe projection, Buyer ownership/isolation, Wholesale and Retail Seller inbox access, unmatched Seller denial, direct inbox-write denial, duplicate quotation prevention, Buyer quotation visibility/isolation, Buyer ID spoof prevention, past required-date rejection, and retained RLS/private ACL boundaries.
- Final output: `=== LOCAL B-03 DEMAND BEHAVIOR TESTS PASSED; ALL TEST DATA ROLLED BACK ===` and `All runner steps completed.` Test rows were rolled back.
- A local-only policy dependency repair adds private boolean SECURITY DEFINER helpers for approved-business eligibility and Buyer Demand ownership; helper EXECUTE is restricted to authenticated and anon is denied. Seller identity remains unexposed. This is local fixture/test code, not a production deployment approval.
- B-03 local fixture logic is PASS. Hosted Supabase JWT/RLS/PostgREST, Data API exposure, Storage/Realtime/Edge Functions, and browser E2E remain unverified. Do not claim production readiness.
- No migration was applied; Live Supabase, Production and `main` remain untouched.


## 10. Product-linked private Conversation (Buyer + Seller)
- [x] Staged frontend Chat List cards show Product thumbnail, Product name, counterpart name, original price snapshot, last-message preview, and direct Product Page link for both Buyer and Seller.
- [x] Staged conversation header displays the Product thumbnail/name, price snapshot at conversation creation, and Product Page link.
- [x] Staged database source adds Product/Seller context to a private conversation and enforces one active Product conversation per Buyer + Seller + Product.
- [x] Existing Buyer-to-Seller product inquiry RPC is staged to reuse the same active thread rather than create duplicates; invitation consent remains required before the Seller can message or call.
- [x] Public Product price is not modified by private negotiation; conversation context price is a snapshot only.
- [ ] Run migration and RLS behavior tests in an isolated, reconciled development database.
- [ ] Verify Buyer and Seller each see only their own participant conversations under real Supabase JWT/PostgREST.
- [ ] Browser/mobile E2E: open Product from Marketplace, create thread, Seller accepts, both see same image/name/link, multiple products create separate threads, repeat click reuses same active thread, unrelated accounts cannot read thread.
- [ ] Verify Realtime, attachments, Audio/Video call and history in hosted-compatible environment.
- This source work is not a deployment approval. Migration history divergence remains a blocker; no Hosted Supabase/Production/main changes were made.

### 10.1 Cross-department hardening update (2026-11-13)
- [x] Product inquiry can include an optional first message; it is saved only when a new thread is created, not duplicated when an existing thread is reused.
- [x] Product conversation identity and original Product snapshot fields are guarded against participant updates by a database trigger.
- [x] Product Detail offers Buyer an optional first inquiry message field (500-character maximum).
- [x] Seller invitation remains pending until Seller accepts; existing RLS rules continue to block messaging/calling before acceptance.
- [x] Admin receives no new private-conversation content access; Porter/Delivery unchanged in this package.
- [ ] Integrate product price negotiation offers/counter-offers/acceptance into the same Buyer–Seller Product conversation message history; keep offer privacy and order conversion server-enforced.
- [ ] Review Seller chat list, Buyer/Seller consent, unread/last-message refresh, and Product deep-link behavior in an isolated DB + browser E2E.
- [ ] Rehearse migration and real authenticated RLS/JWT/PostgREST checks only after migration history reconciliation.
- Source updates are staged only; no database tests or deployment performed.


## 11. Multilingual Chat foundation — cross-department
- [x] Staged per-user preferred-language table with own-row RLS.
- [x] Staged private translation-cache schema tied to the exact message and conversation; accepted conversation participants can read translations.
- [x] Added a shared preferred-language selector in Private Chat for Buyer, Seller, Porter and Admin; preference is saved per user.
- [x] No client-side write permission to translation cache; future translation writes must use a trusted server-side path with participant validation.
- [ ] Implement and test automatic text translation while preserving original message body.
- [ ] Translate Chat List last-message previews and structured system/negotiation events for each recipient.
- [ ] Add per-message original/translated toggle and clear translation-provider/error states.
- [ ] Privacy, consent, retention, rate limits, provider cost and cross-border data handling review.
- [ ] Browser/mobile and real authenticated RLS tests after migration history reconciliation.
- Voice message transcription/translation and live audio/video translation are future phases, not part of this foundation.
- Current UI explicitly says automatic translation is not active yet. No database test, hosted test or browser E2E was run; no deployment approval.


## 12. Multilingual Chat — translation engine architecture update (2026-11-13)
- [x] Defined recipient-specific translation flow for Buyer, Seller, Porter and Admin using each recipient's saved language preference.
- [x] Original message remains the source of truth; translation is a separate cache and failures fall back to original.
- [x] Translation cache remains client read-only; future writes require a trusted server-side endpoint with JWT and accepted-participant checks.
- [x] Defined privacy boundary: no message-body logging, no provider/API secret in browser, no provider calls before provider and consent approval.
- [x] Defined first-release scope as text-only; attachments and voice/video are excluded.
- [x] Defined structured templates for negotiation/system events so prices, currency, quantities, IDs and dates are not translated or altered.
- [ ] Select and approve a provider/hosting model; verify license, language-pair quality (especially Bangla↔Arabic), retention, cross-border processing, consent and operating cost. LibreTranslate/Argos is only an evaluation candidate; self-hosting still needs compute/hosting.
- [ ] Implement authenticated server-side translation endpoint, provider adapter, idempotent cache writes, rate limits, timeouts and privacy-safe errors.
- [ ] Implement translated Chat List previews, per-message Original/Translation toggle and non-blocking fallback/error states.
- [ ] Implement structured translation for negotiation, Demand, Order and Delivery/Porter notifications.
- [ ] Run provider quality tests, local SQL/RLS tests, real JWT/PostgREST, Realtime and browser/mobile E2E across all four roles after migration history reconciliation.
- Automatic translation remains disabled. No provider, key, consent toggle or Edge Function was configured; no SQL or browser test was run. No Live Supabase, Production, DNS or `main` changed.

## 11. Multilingual Chat — provider evaluation
- [x] Shared language preference and private translation-cache foundation staged (not deployed).
- [x] Provider research recorded: Argos has Bengali/Arabic ↔ English packages; direct Bangla ↔ Arabic availability is not established; pivot route requires quality testing.
- [x] NLLB-200 distilled 600M excluded from production selection pending compatible commercial licensing (current model card is CC-BY-NC and research-only).
- [ ] Confirm a self-hosting target and operating cost before running Argos; no always-free hosting assumed.
- [ ] Build consented bilingual pilot set and human-review Bangla ↔ Arabic/English quality, especially commercial facts and negation.
- [ ] Only after provider + privacy approval: implement disabled-by-default server-side adapter, JWT/accepted-participant checks, cache writes, rate limits, fallback and original/translation toggle.
- [ ] Verify structured negotiation, Demand, Order and Porter events without translating numeric/identifier fields; run local, hosted JWT/RLS and browser/mobile E2E tests.
- **Current status:** automatic translation remains disabled; no provider has been configured and no external private chat text has been transmitted.

## 12. Bengali ↔ English translation model review
- [x] Confirm Argos `bn→en` and `en→bn` packages exist; no model-specific quality benchmark found for exact packages.
- [x] Identify IndicTrans2 as preferred Bengali-English pilot candidate; official project supports Bengali and English both directions and provides FLORES/IN22 evaluation tooling.
- [ ] Verify license and revision for both IndicTrans2 directional checkpoints before commercial deployment.
- [ ] Run same 100+ consented examples per direction through IndicTrans2 and Argos; human review plus chrF++/COMET where references exist.
- [ ] Measure server RAM, CPU/GPU, latency, throughput and hosting cost.
- [ ] Approve privacy/consent, implement trusted server adapter and test protected values (price, quantity, currency, dates, IDs).
- **Status:** research/source review only. Neither model was run here; translation remains disabled.


## 13. Bengali ↔ English pilot corpus
- [x] Added 24 synthetic bilingual seed cases for both translation directions, including commercial chat and protected values (`docs/NEXORA_BN_EN_PILOT_CORPUS.md`).
- [x] Added reviewer instructions, critical-token checks, per-direction scoring protocol and an unfilled results matrix.
- [ ] Obtain two independent bilingual reviews of seed references before model scoring.
- [ ] Execute the same frozen corpus on exact IndicTrans2 and Argos checkpoint/package versions; record raw output and hardware/runtime details.
- [ ] Compute optional chrF++/COMET and compare critical-error rate, human scores, latency and hosting cost.
- **Status:** test corpus prepared only. Neither model was run; no quality winner or score is claimed. Automatic translation remains disabled.


## 14. Bengali ↔ English exact checkpoint and local runner
- [x] Identify official IndicTrans2 En→Bn and Bn→En distilled checkpoint IDs; upstream cards display MIT license.
- [x] Record Hugging Face gating: operator must accept access conditions and pin immutable 40-character revisions before downloading.
- [x] Record Argos package index versions (1.9 / Argos 1.9.0) in both directions; artifact license is not stated in index and remains a production approval blocker.
- [x] Add local-only runner and runbook: `scripts/translation_pilot/run_bn_en_pilot.py`, `docs/NEXORA_BN_EN_MODEL_RUNBOOK.md`.
- [ ] Run on a suitable Linux/macOS host after model access, exact revisions and dependency environment are prepared; do not run on Android phone.
- [ ] Two bilingual reviewers validate references and score outputs; record latency, peak memory, critical-token errors and package versions.
- **Status:** source preparation complete; runner not executed/runtime-tested. No model winner or quality score claimed; automatic translation remains disabled.


## 15. Colab inference execution option
- [x] Add phone-friendly Colab notebook `notebooks/NEXORA_BN_EN_Model_Pilot.ipynb`.
- [x] Notebook uses synthetic corpus only, secure hidden Hugging Face token prompt, per-session immutable checkpoint SHA pinning and CSV download.
- [ ] User/operator must accept gated model access conditions and run the notebook on available free Colab resources.
- [ ] Review CSV with two bilingual reviewers and record critical errors, quality and runtime.
- **Status:** notebook prepared, not executed. Free Colab resources are not guaranteed; no paid compute or production translation enabled.
