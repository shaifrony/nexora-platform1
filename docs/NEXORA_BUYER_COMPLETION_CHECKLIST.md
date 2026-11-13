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
- [ ] Public view-তে Buyer ID, name, email, phone, profile বা contact information নেই—catalog ও API-level যাচাই।
- [ ] Buyer শুধু নিজের Demand create/read/update করতে পারে।
- [ ] Seller শুধু তার নিজের `buyer_demand_inbox`-এ routed Demand দেখতে ও quotation দিতে পারে।
- [ ] Buyer Demand close/cancel করলে নতুন quotation বন্ধ হয় এবং public board থেকে বাদ যায়।
- [ ] Buyer একাধিক Seller quotation তুলনা করে একটি quotation গ্রহণ করতে পারবে কি না—business rule ও secure acceptance/order conversion workflow নির্ধারণ ও বাস্তবায়ন।
- [ ] Required date, subcategory এবং field constraints final schema-তে মেলে।
- [ ] Buyer Demand matching product category/subcategory ও approved Seller business অনুযায়ী হয়; market_category নির্বিশেষে যাচাই।

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
