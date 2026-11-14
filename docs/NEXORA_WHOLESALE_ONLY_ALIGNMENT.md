# NEXORA Wholesale-Only Alignment — Superseded

> **এই নথির Wholesale-Only সিদ্ধান্ত বাতিল।** 2026-11-13 তারিখে প্রকল্পের বর্তমান সিদ্ধান্ত অনুযায়ী NEXORA Wholesale এবং Retail উভয় বিক্রয়পদ্ধতি সমর্থন করবে, কিন্তু Buyer visibility-তে কোনো Wholesale/Retail বিভাজন থাকবে না।

## বর্তমান কার্যকর নীতি

- Seller প্রতিটি Product Listing তৈরি বা সম্পাদনার সময় Wholesale অথবা Retail বেছে নেবে।
- একই Seller-এর এক পণ্য Wholesale এবং অন্য পণ্য Retail হতে পারবে।
- Buyer signup বা Buyer profile-এ কোনো Wholesale/Retail account category থাকবে না।
- সব Buyer এবং public visitor সব Admin-approved Wholesale ও Retail product listing দেখতে পারবে।
- Product-এর market_category কেবল বিক্রয়পদ্ধতি ও সংশ্লিষ্ট মূল্য/MOQ নিয়মের তথ্য; এটি visibility entitlement নয়।
- Product Inquiry, Order এবং Buyer Demand matching-এ Buyer/Seller account-level market category ব্যবহার করা যাবে না।
- Buyer Demand Seller matching product category/subcategory এবং approved Business Profile-এর ভিত্তিতে হবে।
- Legacy profiles.buyer_category ও profiles.seller_categories migration compatibility-র জন্য থাকতে পারে, কিন্তু NULL/empty থাকবে এবং authorization-এ ব্যবহার করা যাবে না।

## ইতিহাস

এই নথি পূর্ববর্তী Wholesale-Only পরিকল্পনার রেকর্ড হিসেবে রাখা হয়েছে। এর কোনো নির্দেশনা বর্তমান implementation requirement নয়। বর্তমান অবস্থা দেখুন:

- `docs/NEXORA_PROJECT_STRUCTURE.md`
- `docs/NEXORA_BUYER_COMPLETION_CHECKLIST.md`
- `docs/NEXORA_WORK_TRACKER.md`

কোনো migration Live Supabase-এ প্রয়োগ করা হয়নি। Migration history reconciliation ও hosted Auth/RLS/E2E verification এখনো বাকি।
