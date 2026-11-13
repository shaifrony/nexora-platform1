# NEXORA — Buyer বিভাগ সম্পূর্ণকরণ তালিকা

Updated: 2026-11-13  
Branch: `nexora-development`  
Status: **Implementation review in progress — not complete**

এই নথি Buyer বিভাগের একক সমন্বিত checklist। এটি বর্তমান GitHub কোড ও migration chain পর্যালোচনার ভিত্তিতে তৈরি। কোনো Hosted Supabase বা Production পরিবর্তন/পরীক্ষা করা হয়নি।

## 1. Buyer-এর স্থায়ী ব্যবসায়িক নিয়ম

- Buyer নিবন্ধনের সময় Wholesale অথবা Retail—একটি ক্যাটাগরি নির্বাচন করবে।
- Buyer account তৈরি ও ব্যবহার করতে Admin approval লাগবে না (email confirmation বা platform-এর সাধারণ authentication শর্ত প্রযোজ্য)।
- Buyer Dashboard থেকে নিজের ক্যাটাগরি Wholesale/Retail-এ পরিবর্তন করতে পারবে।
- Wholesale Buyer কেবল Wholesale পণ্য এবং Retail Buyer কেবল Retail পণ্য দেখতে ও অর্ডার করতে পারবে।
- Seller প্রতিটি Product Listing-এর সময় Wholesale/Retail নির্বাচন করবে; Seller account-এর একটি global market category দিয়ে পণ্য সীমাবদ্ধ করা হবে না।
- Buyer Demand প্রকাশ্য হতে পারে, কিন্তু Buyer-এর নাম, পূর্ণ Profile, email, phone বা ব্যক্তিগত যোগাযোগের তথ্য প্রকাশ করা যাবে না।
- Buyer Demand-এ প্রয়োজনীয় পণ্যের বিবরণ, পরিমাণ, গন্তব্য এবং **প্রয়োজনের তারিখ** থাকবে।
- যোগাযোগের অনুরোধ গ্রহণ না করা পর্যন্ত ব্যক্তিগত কথোপকথন শুরু হবে না।
- Buyer নিজের অর্ডার দেখতে, অনুমোদিত অবস্থায় বাতিল করতে এবং পণ্য/সেবা পাওয়ার পর completion নিশ্চিত করতে পারবে।

## 2. বর্তমান বাস্তবায়নের পর্যালোচনা

| ক্ষেত্র | বর্তমান অবস্থা | পর্যালোচনার ফল |
|---|---|---|
| Buyer signup | Frontend staged | Wholesale/Retail নির্বাচন ও metadata পাঠানোর কোড আছে |
| OAuth signup | Migration staged | Google/Facebook signup Buyer হিসেবে শুরু করার নিয়ম আছে; final trigger chain পরীক্ষা বাকি |
| Buyer account activation | Partially verified | Buyer profile active করার migration logic আছে; hosted Auth flow পরীক্ষা বাকি |
| Category switch | Frontend + migration staged | Buyer-only category update, দুই category allowlist ও column-level grant আছে |
| Product discovery | Frontend staged | Approved products query; Buyer category অনুযায়ী client filter আছে |
| Product visibility | Database migration staged | RLS-এ active Buyer-এর buyer_category ও products.market_category মিলতে হয় |
| Product details | Frontend staged | Product ID, Business Display Name, specification, price, MOQ/stock/tiers দেখায় |
| Buyer Demand form | Frontend staged | Product, category, subcategory, description, specifications, quantity, optional budget, currency, destination এবং required date |
| Public Demand Board | Migration + frontend staged | Open demands প্রকাশ; identity/contact fields view-তে নেই বলে migration-এ নির্ধারিত |
| Buyer Demand privacy | Partially verified | Public view security_invoker; anon column grants সীমিত; hosted DB-তে grants/RLS পরীক্ষা বাকি |
| Seller quotations | Frontend + migration staged | Buyer নিজের Demand-এর জন্য Seller offers দেখতে পারে |
| Product inquiry/chat | Frontend + migration staged | Inquiry RPC conversation ও invitation তৈরি করে; গ্রহণের পর chat |
| Orders | Frontend + migration staged | Product/service order request, status, cancel ও completion confirmation |
| Verified reviews | Frontend + migration staged | Completed verified purchase ছাড়া review নয়; duplicate review block |
| Profile privacy | Foundation staged | Public identity projection সীমিত; Buyer-এর full profile অন্যদের কাছে প্রকাশ নয় |
| Wallet/payment | Not implemented / placeholder | Buyer Dashboard-এ wallet balance UI আছে, কিন্তু প্রকৃত wallet ledger/payment integration প্রমাণিত নয় |
| Delivery tracking | Not fully verified | Buyer-এর order form-এ delivery address আছে; Porter assignment/tracking Buyer UI integration আলাদাভাবে পরীক্ষা করতে হবে |
| Browser/mobile E2E | Pending | কোনো বর্তমান browser বা hosted integration test run হয়নি |

## 3. Buyer-এর কাজের সম্পূর্ণ প্রবাহ

1. Homepage থেকে Buyer নির্বাচন করে signup।
2. Signup-এ Wholesale অথবা Retail নির্বাচন।
3. Authentication সম্পন্ন করে Buyer Dashboard-এ প্রবেশ।
4. Dashboard থেকে category পরিবর্তন (প্রয়োজনে)।
5. নিজের category-র approved products খোঁজা, filter করা ও details দেখা।
6. Seller-এর সঙ্গে inquiry পাঠানো; invitation গ্রহণের পর chat/call/file sharing।
7. পণ্য অর্ডার request পাঠানো; Seller-এর order response দেখা।
8. Seller পণ্য পাঠানোর/সেবা সম্পন্নের পর Buyer receipt/completion নিশ্চিত করা।
9. Verified purchase-এর ভিত্তিতে review দেওয়া।
10. বিকল্পভাবে Buyer Demand পোস্ট করা, required date ও destination দেওয়া, Seller quotations তুলনা করা, Demand close/cancel করা।
11. Delivery/transport status ও support flow Buyer Dashboard-এ সংযুক্ত করা।

## 4. এখনো সমাধান/পরীক্ষা বাকি

### B-01 — Auth trigger ও migration chain
- [ ] Final `public.handle_new_user()` definition-এ Buyer wholesale/retail সঠিকভাবে সংরক্ষণ করে নিশ্চিত করা।
- [ ] Google/Facebook OAuth Buyer-only এবং user-editable metadata দিয়ে privileged role নেওয়া অসম্ভব—final trigger-এ যাচাই।
- [ ] Porter ও Seller registration migration-এর সঙ্গে trigger conflict নেই—পূর্ণ migration order-এ যাচাই।
- [ ] Buyer account Admin approval ছাড়াই ব্যবহারযোগ্য, কিন্তু inactive/suspended account blocked—পরীক্ষা।

### B-02 — Product visibility ও category integrity
- [ ] Buyer category পরিবর্তনের পর Marketplace ও Buyer Dashboard reload/refresh-এ নতুন category কার্যকর হয়।
- [x] Frontend category update payload থেকে অতিরিক্ত `updated_at` বাদ: migration শুধু `buyer_category` column UPDATE grant করে; DB trigger updated_at সেট করে।
- [x] Buyer category পরিবর্তনের জন্য owner-only UPDATE RLS policy যোগ; আগের baseline fixture-এ profiles-এর UPDATE policy ছিল না, তাই শুধু column grant যথেষ্ট ছিল না।
- [x] Frontend update response-এ updated row ফেরত চাওয়া ও যাচাই; RLS-এ row update না হলে আর সফলতার বার্তা দেখাবে না।
- [x] Signup role বদলানোর সময় Buyer-এর নির্বাচিত Wholesale/Retail অপশন reset না হওয়ার সংশোধন।
- [x] Market-category migration-এ baseline `protect_profile_updates` trigger-এর Buyer category পরিবর্তন নিষিদ্ধ করার conflict সংশোধন; Buyer কেবল নিজের category বদলাতে পারবে, role/status/Seller entitlements/name protected থাকে।
- [x] Auth trigger-এর provider lookup `new.raw_app_meta_data`-এ সংশোধন।
- [ ] Product Inquiry-এর SECURITY DEFINER RPC-তেও Buyer category যাচাই হয়; recovery-only draft-এ guard যোগ করা হয়েছে, কিন্তু এখনো প্রয়োগ/পরীক্ষা হয়নি।
- [x] Product Inquiry SECURITY DEFINER RPC-তে Buyer category match server-side enforce করার migration guard যোগ করা হয়েছে।
- [ ] Wholesale Buyer Retail product ID/slug সরাসরি খুললেও RLS-এ product data পাওয়া যায় না।
- [ ] Retail Buyer Wholesale product সরাসরি খুললেও একইভাবে block হয়।
- [ ] Anonymous visitor ও authenticated non-Buyer access rules স্পষ্ট করা।
- [ ] Service listing Buyer access-এর জন্য পৃথক policy/ব্যবসায়িক নিয়ম নির্ধারণ; product market_category-র সঙ্গে অযথা মিশবে না।

### B-03 — Buyer Demand privacy ও lifecycle
- [ ] Public view-তে Buyer ID, name, email, phone, profile বা contact information নেই—catalog ও API-level যাচাই।
- [ ] Buyer শুধু নিজের Demand create/read/update করতে পারে।
- [ ] Seller শুধু তার নিজের `buyer_demand_inbox`-এ routed Demand দেখতে ও quotation দিতে পারে।
- [ ] Buyer Demand close/cancel করলে নতুন quotation বন্ধ হয় এবং public board থেকে বাদ যায়।
- [ ] Required date, subcategory এবং field constraints final schema-তে মেলে।
- [ ] Buyer category অনুযায়ী Demand matching-এর আচরণ Wholesale ও Retail উভয় ক্ষেত্রেই যাচাই।

### B-04 — Orders, stock ও pricing
- [ ] Buyer-এর category মেলে না এমন product order server-side reject হয়।
- [ ] MOQ, Retail single-unit default, quantity tiers, stock reservation ও insufficient-stock rejection একই নিয়মে কাজ করে।
- [ ] Order cancel/complete শুধুমাত্র অনুমোদিত status transition-এ হয়।
- [ ] Payment না থাকলে UI স্পষ্টভাবে জানায়—order request মানেই payment বা delivery booking নয়।
- [ ] Buyer order list-এ প্রয়োজনীয় order detail ও delivery progress দেখানো।

### B-05 — Communications, reviews ও support
- [ ] Seller invitation accept না করা পর্যন্ত Buyer message পাঠাতে পারে না।
- [ ] Audio/video/file sharing এবং history শুধু conversation participants দেখতে পারে।
- [ ] Admin ব্যক্তিগত chat-এর content দেখতে পারে না—পূর্বের privacy decision অনুযায়ী।
- [ ] Verified review কেবল completed purchase-এর পর; একজন Buyer এক listing-এ একবার।
- [ ] Complaint/support escalation এবং Buyer-এর support status দেখা।

### B-06 — Dashboard completeness
- [ ] Wholesale-only লেখা, label ও demo text সব জায়গায় dual-market অনুযায়ী সংশোধন।
- [ ] Wallet balance placeholder-কে বাস্তব wallet না বলা; wallet/payment feature বাস্তবায়ন না হওয়া পর্যন্ত স্পষ্টভাবে unavailable/coming later রাখা।
- [ ] Buyer delivery tracking ও Porter handoff UI সংযুক্ত।
- [ ] Mobile responsive, keyboard accessibility, loading/error/empty states পরীক্ষা।
- [ ] Browser E2E: signup, category switch, browse, direct URL denial, demand, offers, inquiry consent, order, completion, review।

## 5. বর্তমান কোডে পাওয়া নির্দিষ্ট নোট

1. `index.html`-এ Buyer signup Wholesale/Retail option আছে।
2. `auth.js`-এ `setBuyerCategory()` উভয় category গ্রহণ করে এবং Buyer-only profile update করে।
3. `marketplace.js`-এ product query ও detail page-এ Buyer category filter আছে।
4. `20261113235900_product_market_category.sql` migration-এর product SELECT policy Buyer profile category ও listing market_category মিলিয়ে দেখে; একই migration-এ Product Inquiry SECURITY DEFINER RPC-তেও category guard যোগ হয়েছে।
5. `20261114140000_commerce_orders_and_review_completion.sql`-এর order RPC product order-এর সময় Buyer category server-side মিলিয়ে দেখে।
6. `20261112153000_publish_open_demands_without_buyer_identity.sql` public Demand-এর column-limited anonymous access তৈরি করে; পরের `20261114160000...` migration security-invoker public view ও subcategory যুক্ত করে।
7. Buyer Dashboard-এর কিছু লেখা এখনো Wholesale-only ছিল; বর্তমান কাজের অংশ হিসেবে সেগুলো generic dual-market ভাষায় সংশোধন করা হচ্ছে।
8. Signup frontend Seller-এর জন্য এখনও `seller_categories: ["wholesale"]` পাঠায়; এটি Seller বিভাগের blocker, Buyer বিভাগের scope-এ পরিবর্তন করা হয়নি। Seller-এর per-product mode rule কার্যকর করতে Seller phase-এ এটি সংশোধন করতে হবে।

## 6. সমাপ্তির শর্ত

Buyer বিভাগকে **সম্পূর্ণ** বলা হবে কেবল যখন:
- সব B-01 থেকে B-06 critical checks সমাধান হয়েছে;
- migration history নিরাপদে reconcile করে isolated DB-তে rehearsal হয়েছে;
- Buyer-এর happy-path ও negative authorization tests পাস করেছে;
- Buyer privacy, Demand privacy, product category RLS, order state এবং chat consent বাস্তব authenticated session-এ যাচাই হয়েছে;
- mobile/browser E2E-এর ফল নথিভুক্ত হয়েছে;
- কোনো unresolved blocker গোপন না রেখে চূড়ান্ত closeout report তৈরি হয়েছে।

## 7. নিরাপত্তা ও deployment সীমা

- এই checklist তৈরির সময় কোনো SQL চালানো হয়নি।
- কোনো Live Supabase, Production, DNS বা `main` পরিবর্তন করা হয়নি।
- Migration history divergence unresolved; migration replay/deploy এখনো blocked।
- Local superuser SQL tests hosted Supabase Auth/JWT/PostgREST/RLS-এর বিকল্প নয়।
