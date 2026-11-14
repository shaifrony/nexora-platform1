"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const js = fs.readFileSync(path.join(__dirname, "..", "marketplace.js"), "utf8");

test("seller listing form requires an explicit wholesale or retail category", () => {
  assert.match(html, /<select name="market_category" required>/);
  assert.match(html, /<option value="wholesale">/);
  assert.match(html, /<option value="retail">/);
});

test("marketplace listing creation validates and persists market_category", () => {
  assert.match(js, /!\["wholesale",\s*"retail"\]\.includes\(v\.market_category\)/);
  assert.match(js, /market_category:\s*v\.market_category/);
});

test("public marketplace and buyer/seller views load the listing category", () => {
  assert.match(js, /product_name,category,subcategory,market_category,image_urls/);
  assert.match(js, /product_name,category,subcategory,market_category,origin,price/);
  assert.match(js, /market_category === "wholesale"/);
  assert.match(js, /market_category === "retail"/);
});

test("marketplace category filter defaults to all and can narrow by category", () => {
  assert.match(html, /id="marketCategoryFilter"/);
  assert.match(js, /const marketCategory = \$\("marketCategoryFilter"\)\?\.value \|\| ""/);
  assert.match(js, /!marketCategory \|\| p\.market_category === marketCategory/);
});

test("legacy listings remain visibly unclassified rather than being guessed", () => {
  assert.match(js, /ধরন নির্ধারিত হয়নি/);
});


test("Buyer Demand requires a required-by date in the form and rejects past dates", () => {
  assert.match(html, /<input type="date" name="requiredDate" id="requiredDate" required>/);
  assert.match(js, /requiredDateInput\.min\s*=\s*new Date\(now\.getTime\(\)\s*-\s*now\.getTimezoneOffset\(\)\s*\*\s*60000\)/);
  assert.match(js, /if\s*\(!v\.requiredDate\s*\|\|\s*v\.requiredDate\s*<\s*todayLocal\)/);
  assert.match(js, /required_date:\s*v\.requiredDate/);
});

test("public Buyer Demand projection includes the required date but excludes buyer identity and contact fields", () => {
  const query = js.match(/from\("public_buyer_demands"\)\s*\.select\("([^"]+)"\)/);
  assert.ok(query, "public Buyer Demand query must use an explicit column allowlist");
  const columns = query[1].split(",").map(value => value.trim());
  assert.ok(columns.includes("required_date"));
  for (const privateField of ["buyer_id", "full_name", "email", "phone", "contact_number", "address"]) {
    assert.ok(!columns.includes(privateField), "public projection must not expose " + privateField);
  }
});


const demandOrderSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261115100000_buyer_demand_quotation_negotiation_and_order_conversion.sql"),
  "utf8"
);

test("Buyer Demand negotiation RPCs are private SECURITY DEFINER functions with an empty search_path", () => {
  for (const signature of [
    "private.respond_to_demand_offer(",
    "private.transition_buyer_demand_order("
  ]) {
    const start = demandOrderSql.indexOf("create or replace function " + signature);
    assert.notEqual(start, -1, "missing " + signature);
    const header = demandOrderSql.slice(start, demandOrderSql.indexOf("as $$", start));
    assert.match(header, /security definer/i);
    assert.match(header, /set search_path\s*=\s*''/i);
  }
});

test("Buyer Demand negotiation private RPCs cannot be executed directly by client roles", () => {
  assert.match(demandOrderSql, /revoke all on function private\.respond_to_demand_offer\(uuid,text,numeric,numeric,text\) from public,anon,authenticated;/i);
  assert.match(demandOrderSql, /revoke all on function private\.transition_buyer_demand_order\(uuid,text,text\) from public,anon,authenticated;/i);
  assert.match(demandOrderSql, /grant execute on function private\.respond_to_demand_offer\(uuid,text,numeric,numeric,text\) to authenticated;/i);
  assert.match(demandOrderSql, /grant execute on function private\.transition_buyer_demand_order\(uuid,text,text\) to authenticated;/i);
});

test("Buyer Demand public RPC wrappers remain SECURITY INVOKER and deny anonymous execution", () => {
  for (const signature of [
    "public.respond_to_demand_offer(",
    "public.transition_buyer_demand_order("
  ]) {
    const start = demandOrderSql.indexOf("create or replace function " + signature);
    assert.notEqual(start, -1, "missing " + signature);
    const header = demandOrderSql.slice(start, demandOrderSql.indexOf("as $$", start));
    assert.match(header, /security invoker/i);
    assert.match(header, /set search_path\s*=\s*''/i);
  }
  assert.match(demandOrderSql, /revoke all on function public\.respond_to_demand_offer\(uuid,text,numeric,numeric,text\) from public,anon;/i);
  assert.match(demandOrderSql, /revoke all on function public\.transition_buyer_demand_order\(uuid,text,text\) from public,anon;/i);
  assert.match(demandOrderSql, /grant execute on function public\.respond_to_demand_offer\(uuid,text,numeric,numeric,text\) to authenticated;/i);
  assert.match(demandOrderSql, /grant execute on function public\.transition_buyer_demand_order\(uuid,text,text\) to authenticated;/i);
});

test("Buyer Demand negotiation serializes offer and demand changes with row locks", () => {
  assert.match(demandOrderSql, /from public\.seller_offers where id=p_offer_id for update/i);
  assert.match(demandOrderSql, /from public\.buyer_demands where id=v_offer\.demand_id for update/i);
  assert.match(demandOrderSql, /from public\.commerce_orders\s+where id=p_order_id and listing_type='buyer_demand' for update/i);
  const negotiation = demandOrderSql.slice(
    demandOrderSql.indexOf("create or replace function private.respond_to_demand_offer("),
    demandOrderSql.indexOf("create or replace function private.transition_buyer_demand_order(")
  );
  const demandLock = negotiation.indexOf("select * into v_demand from public.buyer_demands where id=v_offer.demand_id for update");
  const offerLock = negotiation.indexOf("select * into v_offer from public.seller_offers where id=p_offer_id for update");
  assert.ok(demandLock >= 0 && offerLock > demandLock, "Demand row must be locked before Offer row");

});


const marketplaceCoreSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261112050345_create_marketplace_core_schema.sql"),
  "utf8"
);

test("Seller cannot self-approve a Business Profile or alter its review metadata", () => {
  const policy = marketplaceCoreSql.match(/create policy business_owner_pending_update[\s\S]*?;/i);
  assert.ok(policy, "missing Business Profile owner update policy");
  assert.match(policy[0], /using\s*\(seller_id=\(select auth\.uid\(\)\) and approval_status='pending'\)/i);
  assert.match(policy[0], /with check\s*\(seller_id=\(select auth\.uid\(\)\) and approval_status='pending' and reviewed_by is null and reviewed_at is null and admin_note is null\)/i);
  assert.match(marketplaceCoreSql, /grant update \(display_name,description,country,city,sales_center_address\) on public\.business_profiles to authenticated;/i);
});

test("Seller cannot self-approve a Product Listing or alter its review metadata", () => {
  const policy = marketplaceCoreSql.match(/create policy products_owner_pending_update[\s\S]*?;/i);
  assert.ok(policy, "missing Product owner update policy");
  assert.match(policy[0], /using\s*\(seller_id=\(select auth\.uid\(\)\) and listing_status='pending'\)/i);
  assert.match(policy[0], /with check\s*\(seller_id=\(select auth\.uid\(\)\) and listing_status='pending' and reviewed_by is null and reviewed_at is null and admin_note is null\)/i);
  assert.match(marketplaceCoreSql, /grant update \(product_name,category,image_urls,description,origin,specifications_quality,price,currency\) on public\.products to authenticated;/i);
});

test("Only approved Business Profiles are copied into the public business projection", () => {
  const trigger = marketplaceCoreSql.match(/create or replace function public\.sync_public_business\([\s\S]*?\$function\$;/i);
  assert.ok(trigger, "missing public business synchronization trigger");
  assert.match(trigger[0], /if new\.approval_status <> 'approved' then[\s\S]*?delete from public\.public_businesses/i);
  assert.match(trigger[0], /insert into public\.public_businesses\(business_id,seller_id,display_name,country,city,updated_at\)/i);
  assert.match(marketplaceCoreSql, /create policy public_businesses_authenticated_read on public\.public_businesses for select to authenticated using \(true\);/i);
});

test("Product Listing creation requires an approved public Business Profile", () => {
  const policy = marketplaceCoreSql.match(/create policy products_approved_seller_insert[\s\S]*?;/i);
  assert.ok(policy, "missing approved Seller insert policy");
  assert.match(policy[0], /listing_status='pending'/i);
  assert.match(policy[0], /public\.public_businesses/i);
  assert.match(policy[0], /p\.role='seller' and p\.account_status='active'/i);
});

test("Super Admin review UI checks active Admin identity before applying approval decisions", () => {
  const start = js.indexOf("async function handleAdminDecision(e)");
  const end = js.indexOf("async function", start + 10);
  assert.notEqual(start, -1, "missing Admin review handler");
  const handler = js.slice(start, end);
  assert.match(handler, /profile\(\)\?\.role !== "admin"/);
  assert.match(handler, /profile\(\)\?\.account_status !== "active"/);
  assert.match(handler, /admin_level !== "super_admin"/);
  assert.match(handler, /is_active !== true/);
});


const listingEditSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114120000_listing_edit_review_workflow.sql"),
  "utf8"
);
const listingHistorySql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114130000_listing_edit_history.sql"),
  "utf8"
);

test("Listing change submission is limited to active Sellers editing their own approved listings", () => {
  const fn = listingEditSql.slice(
    listingEditSql.indexOf("create or replace function private.submit_listing_edit_request("),
    listingEditSql.indexOf("create or replace function private.review_listing_edit_request(")
  );
  assert.match(fn, /role='seller' and account_status='active'/i);
  assert.match(fn, /v_seller_id<>v_actor or v_listing_status<>'approved'/i);
  assert.match(fn, /An approved Business Profile is required/i);
  assert.match(fn, /from public\.products where id=p_listing_id for update/i);
  assert.match(fn, /from public\.service_listings where id=p_listing_id for update/i);
});

test("Listing change payloads use explicit allowlists and field validation for both listing types", () => {
  const submit = listingEditSql.slice(
    listingEditSql.indexOf("create or replace function private.submit_listing_edit_request("),
    listingEditSql.indexOf("create or replace function private.review_listing_edit_request(")
  );
  for (const field of ["product_name","category","image_urls","description","origin","specifications_quality","price","currency"]) {
    assert.ok(submit.includes("'" + field + "'"), "Product allowlist missing " + field);
  }
  for (const field of ["service_name","service_category","description","country","city","service_area","price_basis","price_amount","currency","availability","image_urls"]) {
    assert.ok(submit.includes("'" + field + "'"), "Service allowlist missing " + field);
  }
  assert.match(submit, /jsonb_object_keys\(p_proposed_changes\)/i);
  assert.match(submit, /jsonb_array_length\(p_proposed_changes->'image_urls'\)>5/i);
  assert.match(submit, /jsonb_array_length\(p_proposed_changes->'image_urls'\)>3/i);
});

test("Only one pending change request can exist per Product or Service listing", () => {
  assert.match(listingEditSql, /create unique index if not exists listing_edit_requests_one_pending_product[\s\S]*?where status='pending' and product_id is not null/i);
  assert.match(listingEditSql, /create unique index if not exists listing_edit_requests_one_pending_service[\s\S]*?where status='pending' and service_listing_id is not null/i);
});

test("Listing change review requires matching permission, active Admin membership and a pending request", () => {
  const fn = listingEditSql.slice(
    listingEditSql.indexOf("create or replace function private.review_listing_edit_request("),
    listingEditSql.indexOf("revoke all on function private.submit_listing_edit_request")
  );
  assert.match(fn, /private\.has_nexora_permission\(v_permission\)/i);
  assert.match(fn, /s\.is_active=true[\s\S]*?p\.role='admin' and p\.account_status='active'/i);
  assert.match(fn, /v_request\.status<>'pending'/i);
  assert.match(fn, /p_action='reject' and length\(btrim\(coalesce\(p_reason,''\)\)\)<5/i);
  assert.match(fn, /for update/i);
});

test("Approvals apply proposed listing fields, while rejections preserve live listing data and record an audit event", () => {
  const fn = listingEditSql.slice(
    listingEditSql.indexOf("create or replace function private.review_listing_edit_request("),
    listingEditSql.indexOf("revoke all on function private.submit_listing_edit_request")
  );
  assert.match(fn, /if p_action='approve' then\s*update public\.products set/i);
  assert.match(fn, /if p_action='approve' then\s*update public\.service_listings set/i);
  assert.match(fn, /update public\.listing_edit_requests\s*set status=case when p_action='approve'/i);
  assert.match(fn, /insert into public\.admin_audit_logs/i);
  assert.match(fn, /'listing_edit_request\.'\|\|p_action/i);
});

test("Listing edit history captures immutable before/after snapshots through database triggers", () => {
  assert.match(listingHistorySql, /before insert on public\.listing_edit_requests\s*for each row execute function private\.snapshot_listing_before_edit_request\(\)/i);
  assert.match(listingHistorySql, /after insert or update of status on public\.listing_edit_requests\s*for each row execute function private\.log_listing_edit_request_event\(\)/i);
  assert.match(listingHistorySql, /new\.original_data:=v_old/i);
  assert.match(listingHistorySql, /insert into public\.listing_edit_request_events/i);
  assert.match(listingHistorySql, /revoke all on function private\.snapshot_listing_before_edit_request\(\) from public,anon,authenticated/i);
  assert.match(listingHistorySql, /revoke all on function private\.log_listing_edit_request_event\(\) from public,anon,authenticated/i);
});


const productNegotiationSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261115110000_product_price_negotiation.sql"),
  "utf8"
);

test("Product price negotiations and event history are private to their Buyer and Seller participants", () => {
  assert.match(productNegotiationSql, /alter table public\.product_price_negotiations enable row level security/i);
  assert.match(productNegotiationSql, /alter table public\.product_price_negotiation_events enable row level security/i);
  assert.match(productNegotiationSql, /product_price_negotiations_participant_read[\s\S]*?buyer_id=\(select auth\.uid\(\)\) or seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(productNegotiationSql, /product_price_negotiation_events_participant_read[\s\S]*?n\.buyer_id=\(select auth\.uid\(\)\) or n\.seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(productNegotiationSql, /revoke all on public\.product_price_negotiations,public\.product_price_negotiation_events from public,anon,authenticated/i);
});

test("Only an active Buyer can start a negotiation on another Seller's approved product", () => {
  const fn = productNegotiationSql.slice(
    productNegotiationSql.indexOf("create or replace function public.start_product_price_negotiation("),
    productNegotiationSql.indexOf("revoke all on function private.respond_to_product_price_negotiation")
  );
  assert.match(fn, /listing_status='approved' for update/i);
  assert.match(fn, /v_seller=v_actor/i);
  assert.match(fn, /role='buyer' and account_status='active'/i);
  assert.match(fn, /public\.public_businesses/i);
  assert.match(fn, /p_quantity<coalesce\(v_product\.minimum_order_quantity,1\)/i);
  assert.match(fn, /p_quantity>v_available/i);
  assert.match(fn, /length\(btrim\(coalesce\(p_fulfilment_location,''\)\)\)<5/i);
});

test("Negotiation responses require the correct active participant and enforce turn-taking", () => {
  const fn = productNegotiationSql.slice(
    productNegotiationSql.indexOf("create or replace function private.respond_to_product_price_negotiation("),
    productNegotiationSql.indexOf("create or replace function public.start_product_price_negotiation(")
  );
  assert.match(fn, /where id=p_negotiation_id for update/i);
  assert.match(fn, /where id=v_n\.product_id for update/i);
  assert.match(fn, /account_status='active' and role in \('buyer','seller'\)/i);
  assert.match(fn, /v_n\.buyer_id<>v_actor/i);
  assert.match(fn, /v_n\.seller_id<>v_actor/i);
  assert.match(fn, /v_n\.negotiation_status in \('accepted','rejected','ordered'\)/i);
  assert.match(fn, /v_actor=v_n\.last_actor_id/i);
});

test("Negotiation acceptance rechecks MOQ and stock, reserves inventory and creates an order atomically", () => {
  const fn = productNegotiationSql.slice(
    productNegotiationSql.indexOf("create or replace function private.respond_to_product_price_negotiation("),
    productNegotiationSql.indexOf("create or replace function public.start_product_price_negotiation(")
  );
  assert.match(fn, /v_n\.quantity<coalesce\(v_p\.minimum_order_quantity,1\)/i);
  assert.match(fn, /v_n\.quantity>v_available/i);
  assert.match(fn, /update public\.products set reserved_quantity=reserved_quantity\+v_n\.quantity/i);
  assert.match(fn, /insert into public\.commerce_orders/i);
  assert.match(fn, /insert into public\.commerce_order_events/i);
  assert.match(fn, /set negotiation_status='ordered',order_id=v_order_id/i);
});

test("Negotiation actions append immutable event and chat history through protected server-side functions", () => {
  assert.match(productNegotiationSql, /insert into public\.product_price_negotiation_events/i);
  assert.match(productNegotiationSql, /perform private\.append_product_negotiation_chat_event/i);
  assert.match(productNegotiationSql, /revoke all on function private\.append_product_negotiation_chat_event\(uuid,uuid,jsonb\) from public,anon,authenticated/i);
  assert.match(productNegotiationSql, /revoke all on function private\.respond_to_product_price_negotiation\(uuid,text,numeric,numeric,text,text\) from public,anon,authenticated/i);
  assert.match(productNegotiationSql, /security invoker set search_path=''/i);
  assert.match(productNegotiationSql, /grant execute on function public\.respond_to_product_price_negotiation\(uuid,text,numeric,numeric,text,text\) to authenticated/i);
});


const multilingualChatSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261115120000_multilingual_chat_foundation.sql"),
  "utf8"
);

test("Language preferences are private and users can only manage their own preference row", () => {
  assert.match(multilingualChatSql, /alter table public\.user_language_preferences enable row level security/i);
  assert.match(multilingualChatSql, /revoke all on public\.user_language_preferences from public, anon/i);
  assert.match(multilingualChatSql, /language_preferences_read_own[\s\S]*?using \(user_id = \(select auth\.uid\(\)\)\)/i);
  assert.match(multilingualChatSql, /language_preferences_insert_own[\s\S]*?with check \(user_id = \(select auth\.uid\(\)\)\)/i);
  assert.match(multilingualChatSql, /language_preferences_update_own[\s\S]*?using \(user_id = \(select auth\.uid\(\)\)\)[\s\S]*?with check \(user_id = \(select auth\.uid\(\)\)\)/i);
  assert.match(multilingualChatSql, /preferred_language text not null default 'en'[\s\S]*?check \(preferred_language ~ '\^\[a-z\]\{2,3\}\(-\[A-Z\]\{2\}\)\?\$'\)/i);
});

test("Message translations are readable only by accepted conversation participants and are not client-writable", () => {
  assert.match(multilingualChatSql, /alter table public\.message_translations enable row level security/i);
  assert.match(multilingualChatSql, /revoke all on public\.message_translations from public, anon, authenticated/i);
  assert.match(multilingualChatSql, /grant select on public\.message_translations to authenticated/i);
  assert.match(multilingualChatSql, /message_translations_participant_read[\s\S]*?cp\.conversation_id = message_translations\.conversation_id[\s\S]*?cp\.user_id = \(select auth\.uid\(\)\)[\s\S]*?cp\.invitation_status = 'accepted'/i);
});

test("Translation rows are tied to the exact source message and conversation, with one translation per target language", () => {
  assert.match(multilingualChatSql, /create unique index if not exists messages_id_conversation_unique[\s\S]*?on public\.messages\(id, conversation_id\)/i);
  assert.match(multilingualChatSql, /foreign key \(message_id, conversation_id\)[\s\S]*?references public\.messages\(id, conversation_id\) on delete cascade/i);
  assert.match(multilingualChatSql, /unique\(message_id, target_language\)/i);
  assert.match(multilingualChatSql, /translated_body text not null check \(length\(translated_body\) <= 10000\)/i);
});


const marketplaceUi = fs.readFileSync(path.join(__dirname, "..", "marketplace.js"), "utf8");

test("Buyer and Seller negotiation dashboards query only their own participant records", () => {
  const buyer = marketplaceUi.slice(marketplaceUi.indexOf("async function loadBuyerPriceNegotiations()"), marketplaceUi.indexOf("async function loadBuyerOrders()"));
  const seller = marketplaceUi.slice(marketplaceUi.indexOf("async function loadSellerPriceNegotiations()"), marketplaceUi.indexOf("async function respondToProductNegotiation("));
  assert.match(buyer, /activeBuyer\(\)/);
  assert.match(buyer, /\.eq\("buyer_id",user\(\)\.id\)/);
  assert.match(seller, /activeSeller\(\)/);
  assert.match(seller, /\.eq\("seller_id",user\(\)\.id\)/);
});

test("Negotiation UI exposes response actions only to the party whose turn it is", () => {
  const buyer = marketplaceUi.slice(marketplaceUi.indexOf("async function loadBuyerPriceNegotiations()"), marketplaceUi.indexOf("async function loadBuyerOrders()"));
  const seller = marketplaceUi.slice(marketplaceUi.indexOf("async function loadSellerPriceNegotiations()"), marketplaceUi.indexOf("async function respondToProductNegotiation("));
  assert.match(buyer, /n\.negotiation_status==="seller_countered"/);
  assert.match(seller, /n\.negotiation_status==="buyer_countered"/);
  assert.match(buyer, /data-buyer-product-neg="accept"/);
  assert.match(seller, /data-seller-product-neg="accept"/);
});

test("Buyer negotiation submission validates positive quantity and price before RPC", () => {
  const start = marketplaceUi.indexOf('$("nxProductNegotiationForm")');
  const submit = marketplaceUi.slice(start, marketplaceUi.indexOf("      return;", start));
  assert.notEqual(start, -1);
  assert.match(submit, /Number\.isFinite\(quantity\)/);
  assert.match(submit, /quantity<min/);
  assert.match(submit, /available!==null&&quantity>available/);
  assert.match(submit, /Number\.isFinite\(price\)/);
  assert.match(submit, /price<=0/);
  assert.match(submit, /start_product_price_negotiation/);
});

test("Negotiation dashboard interpolates user and listing data through HTML escaping", () => {
  const buyer = marketplaceUi.slice(marketplaceUi.indexOf("async function loadBuyerPriceNegotiations()"), marketplaceUi.indexOf("async function loadBuyerOrders()"));
  const seller = marketplaceUi.slice(marketplaceUi.indexOf("async function loadSellerPriceNegotiations()"), marketplaceUi.indexOf("async function respondToProductNegotiation("));
  assert.match(buyer, /esc\(products\[n\.product_id\]/);
  assert.match(buyer, /esc\(n\.quantity\)/);
  assert.match(buyer, /esc\(n\.current_unit_price\)/);
  assert.match(seller, /esc\(products\[n\.product_id\]/);
  assert.match(seller, /esc\(n\.fulfilment_location\)/);
  assert.match(seller, /esc\(n\.quantity\)/);
});


const demandInboxSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114160000_demand_inbox_quotations_subcategories.sql"),
  "utf8"
);

test("Seller can read and quote only open Buyer Demands routed to its approved Business Profile", () => {
  const readPolicy = demandInboxSql.slice(
    demandInboxSql.indexOf("create policy demands_owner_inbox_admin_read"),
    demandInboxSql.indexOf("-- Seller quotation creation")
  );
  const insertPolicy = demandInboxSql.slice(
    demandInboxSql.indexOf("create policy offers_approved_seller_inbox_insert"),
    demandInboxSql.indexOf("grant update (subcategory)")
  );
  assert.match(readPolicy, /demand_status='open'/i);
  assert.match(readPolicy, /i\.seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(insertPolicy, /seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(insertPolicy, /p\.role='seller' and p\.account_status='active'/i);
  assert.match(insertPolicy, /public\.public_businesses b where b\.seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(insertPolicy, /i\.seller_id=\(select auth\.uid\(\)\) and d\.demand_status='open'/i);
});

test("Buyer Demand quotation UI validates amount, currency, availability and delivery charge before insert", () => {
  const submit = marketplaceUi.slice(
    marketplaceUi.indexOf("async function submitDemandQuotation("),
    marketplaceUi.indexOf("async function respondToDemandQuotationSeller(")
  );
  assert.match(submit, /activeSeller\(\)/);
  assert.match(submit, /state\.business\.approval_status!==\"approved\"/);
  assert.match(submit, /price<=0/);
  assert.match(submit, /currencyOK/);
  assert.match(submit, /available_quantity/);
  assert.match(submit, /deliveryCharge<0/);
  assert.match(submit, /demand_id:demandId,seller_id:user\(\)\.id/);
});

test("Buyer Demand inbox and dashboard load only the relevant Seller or Buyer demand records", () => {
  const inbox = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadSellerDemandInbox()"),
    marketplaceUi.indexOf("const serviceCategoryLabels")
  );
  const buyer = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadBuyerDashboard()"),
    marketplaceUi.indexOf("function renderBuyerDashboard(")
  );
  assert.match(inbox, /activeSeller\(\)/);
  assert.match(inbox, /\.eq\("seller_id",user\(\)\.id\)/);
  assert.match(inbox, /buyer_demands!inner/);
  assert.match(inbox, /\.eq\("buyer_demands\.demand_status","open"\)/);
  assert.match(inbox, /\.eq\("seller_id",user\(\)\.id\)/);
  assert.match(buyer, /activeBuyer\(\)/);
  assert.match(buyer, /\.from\("buyer_demands"\)/);
  assert.match(buyer, /\.from\("seller_offers"\)/);
  assert.match(buyer, /\.in\("demand_id", ids\)/);
});

test("Buyer Demand quotation actions are shown only to the Buyer after the Seller's latest offer", () => {
  const render = marketplaceUi.slice(
    marketplaceUi.indexOf("function renderBuyerDashboard(offers)"),
    marketplaceUi.indexOf("async function respondToDemandQuotation(")
  );
  assert.match(render, /d\.demand_status==="open"/);
  assert.match(render, /last_negotiator_id!==user\(\)\.id/);
  assert.match(render, /data-quote-action="accept"/);
  assert.match(render, /data-quote-action="counter"/);
  assert.match(render, /data-quote-action="reject"/);
});

test("Buyer Demand counter-offer form enforces Seller availability and positive price before RPC", () => {
  const respond = marketplaceUi.slice(
    marketplaceUi.indexOf("async function respondToDemandQuotation("),
    marketplaceUi.indexOf("async function updateBuyerDemandStatus(")
  );
  assert.match(respond, /maxQuantity/);
  assert.match(respond, /quantity>maxQuantity/);
  assert.match(respond, /unitPrice<=0/);
  assert.match(respond, /respond_to_demand_offer/);
  assert.match(respond, /loadBuyerOrders\(\)/);
});

test("Seller can answer only a Buyer counter-offer and refreshes its Demand inbox and orders", () => {
  const respond = marketplaceUi.slice(
    marketplaceUi.indexOf("async function respondToDemandQuotationSeller("),
    marketplaceUi.indexOf("async function loadSellerDemandInbox(")
  );
  const inbox = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadSellerDemandInbox()"),
    marketplaceUi.indexOf("const serviceCategoryLabels")
  );
  assert.match(respond, /activeSeller\(\)/);
  assert.match(respond, /respond_to_demand_offer/);
  assert.match(respond, /loadSellerDemandInbox\(\)/);
  assert.match(respond, /loadSellerOrders\(\)/);
  assert.match(inbox, /offer\.negotiation_status==="buyer_countered"/);
  assert.match(inbox, /data-seller-quote-action="accept"/);
  assert.match(inbox, /data-seller-quote-action="counter"/);
  assert.match(inbox, /data-seller-quote-action="reject"/);
});

test("Buyer Demand order conversion is idempotently limited to one order per Seller quotation", () => {
  assert.match(demandOrderSql, /create unique index if not exists commerce_orders_source_offer_unique_idx[\s\S]*?on public\.commerce_orders\(source_offer_id\) where source_offer_id is not null/i);
  assert.match(demandOrderSql, /values\s*\(\s*'buyer_demand',v_demand\.id,[\s\S]*?v_demand\.id,v_offer\.id/i);
  assert.match(demandOrderSql, /v_role='seller' then 'accepted' else 'pending' end/i);
  assert.match(demandOrderSql, /update public\.seller_offers set offer_status='accepted',negotiation_status='ordered'/i);
});

test("Buyer Demand order dashboards display the agreed quotation total and use the dedicated transition RPC", () => {
  const buyerOrders = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadBuyerOrders()"),
    marketplaceUi.indexOf("async function updateSellerProductInventory(")
  );
  const sellerOrders = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadSellerOrders()"),
    marketplaceUi.indexOf("async function transitionCommerceOrder(")
  );
  const transition = marketplaceUi.slice(
    marketplaceUi.indexOf("async function transitionCommerceOrder("),
    marketplaceUi.indexOf("async function loadListingReviews(")
  );
  assert.match(buyerOrders, /source_offer_total/);
  assert.match(buyerOrders, /grand_total/);
  assert.match(sellerOrders, /source_offer_total/);
  assert.match(sellerOrders, /grand_total/);
  assert.match(transition, /listingType==="buyer_demand"\?"transition_buyer_demand_order"/);
  assert.match(transition, /p_order_id:orderId,p_action:action,p_note:note/);
});

test("Buyer Demand order transitions enforce assigned Buyer or Seller identity and valid state changes", () => {
  const fn = demandOrderSql.slice(
    demandOrderSql.indexOf("create or replace function private.transition_buyer_demand_order("),
    demandOrderSql.indexOf("revoke all on function private.respond_to_demand_offer")
  );
  assert.match(fn, /p\.role='buyer' and p\.id=v_order\.buyer_id/);
  assert.match(fn, /p\.role='seller' and p\.id=v_order\.seller_id/);
  assert.match(fn, /p_action='accept'[\s\S]*?v_actor<>v_order\.seller_id[\s\S]*?v_order\.order_status<>'pending'/);
  assert.match(fn, /p_action='ready'[\s\S]*?v_actor<>v_order\.seller_id[\s\S]*?v_order\.order_status<>'accepted'/);
  assert.match(fn, /p_action='complete'[\s\S]*?v_actor<>v_order\.buyer_id[\s\S]*?v_order\.order_status<>'ready_for_confirmation'/);
  assert.match(fn, /p_action='cancel'[\s\S]*?v_actor<>v_order\.buyer_id[\s\S]*?v_order\.order_status<>'pending'/);
});


test("Seller cannot spoof protected Buyer Demand quotation state or agreed terms on initial insert", () => {
  const fn = demandOrderSql.slice(
    demandOrderSql.indexOf("create or replace function private.initialise_seller_offer_negotiation()"),
    demandOrderSql.indexOf("revoke all on function private.initialise_seller_offer_negotiation()")
  );
  assert.match(fn, /select \* into v_demand from public\.buyer_demands where id=new\.demand_id for update/i);
  assert.match(fn, /v_demand\.demand_status<>'open'/i);
  assert.match(fn, /new\.current_quantity:=v_qty/i);
  assert.match(fn, /new\.current_unit_price:=v_unit/i);
  assert.match(fn, /new\.negotiation_status:='open'/i);
  assert.match(fn, /new\.last_negotiator_id:=new\.seller_id/i);
  assert.match(fn, /new\.accepted_quantity:=null/i);
  assert.match(fn, /new\.accepted_unit_price:=null/i);
  assert.match(fn, /new\.demand_order_id:=null/i);
  assert.doesNotMatch(fn, /coalesce\(new\.(current_quantity|current_unit_price)/i);
  assert.match(demandOrderSql, /before insert on public\.seller_offers\s*for each row execute function private\.initialise_seller_offer_negotiation\(\)/i);
});


test("Buyer Demand negotiation caps every counter-offer and accepted order at the posted required quantity", () => {
  const fn = demandOrderSql.slice(
    demandOrderSql.indexOf("create or replace function private.respond_to_demand_offer("),
    demandOrderSql.indexOf("create or replace function private.transition_buyer_demand_order(")
  );
  assert.ok(fn.includes("v_demand_qty:=nullif(substring(regexp_replace(btrim(v_demand.required_quantity),',','','g') from '^[0-9]+([.][0-9]+)?'),'')::numeric"));
  assert.ok(fn.includes("p_quantity>least(coalesce(nullif(v_offer.available_quantity,'')::numeric,0),v_demand_qty)"));
  assert.ok(fn.includes("least(v_latest.proposed_quantity,v_demand_qty)"));
  assert.ok(fn.includes("least(nullif(v_offer.available_quantity,'')::numeric,v_demand_qty)"));
  assert.match(fn, /v_qty>v_demand_qty/i);
});

test("Buyer and Seller Demand quotation forms present and enforce the Buyer-required quantity ceiling", () => {
  const buyer = marketplaceUi.slice(
    marketplaceUi.indexOf("function renderBuyerDashboard(offers)"),
    marketplaceUi.indexOf("async function respondToDemandQuotation(")
  );
  const seller = marketplaceUi.slice(
    marketplaceUi.indexOf("async function respondToDemandQuotationSeller("),
    marketplaceUi.indexOf("async function loadSellerDemandInbox(")
  );
  const inbox = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadSellerDemandInbox()"),
    marketplaceUi.indexOf("const serviceCategoryLabels")
  );
  assert.match(buyer, /Math\.min\(qty,demandQuantity\)/);
  assert.match(buyer, /data-max-quantity=.*Math\.min\(qty,demandQuantity\)/);
  assert.match(seller, /quantity>currentQuantity/);
  assert.match(inbox, /Math\.min\(Number\(offer\.available_quantity\),requestedQuantity\)/);
});


const privateCommunicationsSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261112050854_create_private_communications.sql"),
  "utf8"
);
const hardenedCommunicationsSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261112050951_harden_private_communications_rls.sql"),
  "utf8"
);
const inviteVisibilitySql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261112051022_allow_invitees_to_view_chat_invitation.sql"),
  "utf8"
);
const productConversationSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261113203025_product_linked_private_conversations.sql"),
  "utf8"
);
const chatUi = fs.readFileSync(path.join(__dirname, "..", "chat.js"), "utf8");

test("Private Chat membership helper grants access only to accepted participants", () => {
  const helper = hardenedCommunicationsSql.slice(
    hardenedCommunicationsSql.indexOf("create or replace function private.is_conversation_member("),
    hardenedCommunicationsSql.indexOf("create or replace function private.is_conversation_creator(")
  );
  assert.match(helper, /security definer set search_path=''/i);
  assert.match(helper, /cp\.user_id=\(select auth\.uid\(\)\) and cp\.invitation_status='accepted'/i);
  assert.match(hardenedCommunicationsSql, /grant execute on function private\.is_conversation_member\(uuid\) to authenticated/i);
  assert.match(hardenedCommunicationsSql, /revoke all on function private\.is_conversation_member\(uuid\) from public,anon/i);
});

test("Chat invitations can be created only by the conversation creator and invitees start pending", () => {
  assert.match(hardenedCommunicationsSql, /create policy participants_invite_by_creator[\s\S]*?invited_by=\(select auth\.uid\(\)\)[\s\S]*?invitation_status='accepted'[\s\S]*?invitation_status='pending'[\s\S]*?private\.is_conversation_creator\(conversation_id\)/i);
  assert.match(hardenedCommunicationsSql, /create policy participants_update_own_status[\s\S]*?user_id=\(select auth\.uid\(\)\) and invitation_status in \('pending','accepted'\)[\s\S]*?invitation_status in \('accepted','declined','left'\)/i);
});

test("Private messages are readable and sendable only by accepted members of an active conversation", () => {
  assert.match(hardenedCommunicationsSql, /create policy messages_participant_read[\s\S]*?private\.is_conversation_member\(conversation_id\)/i);
  assert.match(hardenedCommunicationsSql, /create policy messages_participant_send[\s\S]*?sender_id=\(select auth\.uid\(\)\)[\s\S]*?c\.status='active'[\s\S]*?private\.is_conversation_member\(conversation_id\)/i);
  assert.match(hardenedCommunicationsSql, /grant update \(body,edited_at,deleted_at\) on public\.messages to authenticated/i);
  assert.doesNotMatch(privateCommunicationsSql, /create policy .*admin.* on public\.(conversations|conversation_participants|messages)/i);
});

test("Chat files and call signaling require accepted conversation participants", () => {
  assert.match(hardenedCommunicationsSql, /create policy attachments_participant_read[\s\S]*?private\.is_conversation_member\(conversation_id\)/i);
  assert.match(hardenedCommunicationsSql, /create policy attachments_sender_insert[\s\S]*?uploaded_by=\(select auth\.uid\(\)\)[\s\S]*?private\.is_conversation_member\(conversation_id\)/i);
  assert.match(hardenedCommunicationsSql, /create policy call_signals_sender_insert[\s\S]*?sender_id=\(select auth\.uid\(\)\)[\s\S]*?recipient_id<>\(select auth\.uid\(\)\)[\s\S]*?private\.is_conversation_member\(conversation_id\)[\s\S]*?cp\.invitation_status='accepted'/i);
  assert.match(privateCommunicationsSql, /create policy nexora_chat_files_read[\s\S]*?cp\.invitation_status='accepted'/i);
});

test("Product inquiry is limited to active Buyers and approved Products, Businesses and Sellers", () => {
  const fn = productConversationSql.slice(
    productConversationSql.indexOf("create or replace function private.create_product_inquiry("),
    productConversationSql.indexOf("revoke all on function private.create_product_inquiry")
  );
  assert.match(fn, /p\.role = 'buyer' and p\.account_status = 'active'/i);
  assert.match(fn, /p\.listing_status = 'approved'/i);
  assert.match(fn, /b\.approval_status = 'approved'/i);
  assert.match(fn, /p\.role = 'seller' and p\.account_status = 'active'/i);
  assert.match(fn, /v_product\.seller_id = v_user_id/i);
  assert.match(fn, /invitation_status, joined_at[\s\S]*?'accepted'[\s\S]*?'pending'/i);
});

test("Product inquiry stores one optional first message only for a newly created private thread", () => {
  const fn = productConversationSql.slice(
    productConversationSql.indexOf("create or replace function private.create_product_inquiry("),
    productConversationSql.indexOf("revoke all on function private.create_product_inquiry")
  );
  assert.match(fn, /on conflict \(created_by, context_seller_id, context_product_id\)[\s\S]*?do nothing/i);
  assert.match(fn, /if v_conversation_id is null then[\s\S]*?select c\.id into v_conversation_id/i);
  assert.match(fn, /else[\s\S]*?insert into public\.conversation_participants[\s\S]*?if v_message <> '' then[\s\S]*?insert into public\.messages/i);
});

test("Chat UI hides the composer and call controls until an invitation is accepted", () => {
  const open = chatUi.slice(
    chatUi.indexOf("async function openConversation("),
    chatUi.indexOf("async function respondInvite(")
  );
  assert.match(open, /mine\?\.invitation_status==="pending"/);
  assert.match(open, /chatComposer.*classList\.add\("hidden"\)/);
  assert.match(open, /chatCallPanel.*classList\.add\("hidden"\)/);
  assert.match(open, /mine\?\.invitation_status!=="accepted"/);
  assert.match(open, /await loadMessages\(id\)/);
});


const commerceOrderSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114140000_commerce_orders_and_review_completion.sql"),
  "utf8"
);
const inventoryOrderSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114150000_product_inventory_moq_quantity_pricing.sql"),
  "utf8"
);

test("Product order creation locks the approved listing and enforces MOQ and available stock", () => {
  const fn = inventoryOrderSql.slice(
    inventoryOrderSql.indexOf("create or replace function private.create_commerce_order("),
    inventoryOrderSql.indexOf("-- Replace transition logic")
  );
  assert.match(fn, /role='buyer' and p\.account_status='active'/i);
  assert.match(fn, /from public\.products pr[\s\S]*?listing_status='approved'[\s\S]*?for update/i);
  assert.match(fn, /public\.public_businesses b where b\.business_id=v_product\.business_id/i);
  assert.match(fn, /p_quantity < v_product\.minimum_order_quantity/i);
  assert.match(fn, /p_quantity > \(v_product\.stock_quantity - v_product\.reserved_quantity\)/i);
  assert.match(fn, /update public\.products set reserved_quantity=reserved_quantity\+p_quantity/i);
  assert.match(fn, /v_seller=v_buyer/i);
  assert.match(fn, /p\.role='seller' and p\.account_status='active'/i);
});

test("Product order snapshots the highest qualifying quantity-tier unit price", () => {
  const fn = inventoryOrderSql.slice(
    inventoryOrderSql.indexOf("create or replace function private.create_commerce_order("),
    inventoryOrderSql.indexOf("-- Replace transition logic")
  );
  assert.match(fn, /for v_tier in select value from jsonb_array_elements\(v_product\.price_tiers\)/i);
  assert.match(fn, /if p_quantity >= v_tier_min/i);
  assert.match(fn, /v_price := \(v_tier->>'unit_price'\)::numeric/i);
  assert.match(fn, /insert into public\.commerce_orders\(listing_type,listing_id,buyer_id,seller_id,quantity,unit_price,currency/i);
});

test("Seller inventory updates require active ownership and cannot reduce stock below reservations", () => {
  const fn = inventoryOrderSql.slice(
    inventoryOrderSql.indexOf("create or replace function private.set_product_inventory("),
    inventoryOrderSql.indexOf("revoke all on function private.set_product_inventory")
  );
  assert.match(fn, /where id=p_product_id for update/i);
  assert.match(fn, /v_product\.seller_id <> v_actor/i);
  assert.match(fn, /p\.role='seller' and p\.account_status='active'/i);
  assert.match(fn, /p_stock_quantity < v_product\.reserved_quantity/i);
  assert.match(fn, /Stock tracking cannot be disabled while orders have reserved stock/i);
  assert.match(fn, /o\.order_status in \('pending','accepted','ready_for_confirmation'\)/i);
});

test("Order transition requires an active assigned Buyer or Seller and preserves the role-specific state machine", () => {
  const fn = inventoryOrderSql.slice(
    inventoryOrderSql.indexOf("create or replace function private.transition_commerce_order("),
    inventoryOrderSql.indexOf("revoke all on function private.create_commerce_order")
  );
  assert.match(fn, /p\.id=v_actor and p\.account_status='active'/i);
  assert.match(fn, /p\.role='buyer' and p\.id=v_order\.buyer_id/i);
  assert.match(fn, /p\.role='seller' and p\.id=v_order\.seller_id/i);
  assert.match(fn, /v_actor<>v_order\.seller_id or v_order\.order_status<>'pending'/i);
  assert.match(fn, /v_actor<>v_order\.seller_id or v_order\.order_status<>'accepted'/i);
  assert.match(fn, /v_actor<>v_order\.buyer_id or v_order\.order_status<>'ready_for_confirmation'/i);
  assert.match(fn, /v_actor<>v_order\.buyer_id or v_order\.order_status<>'pending'/i);
});

test("Order cancellation/rejection releases stock and completion deducts reserved stock atomically", () => {
  const fn = inventoryOrderSql.slice(
    inventoryOrderSql.indexOf("create or replace function private.transition_commerce_order("),
    inventoryOrderSql.indexOf("revoke all on function private.create_commerce_order")
  );
  assert.match(fn, /select \* into v_product from public\.products where id=v_order\.listing_id for update/i);
  assert.match(fn, /if v_next='completed' then[\s\S]*?stock_quantity=stock_quantity-v_order\.quantity,[\s\S]*?reserved_quantity=reserved_quantity-v_order\.quantity/i);
  assert.match(fn, /elsif v_next in \('cancelled','rejected'\) then[\s\S]*?reserved_quantity=reserved_quantity-v_order\.quantity/i);
  assert.match(fn, /insert into public\.commerce_order_events/i);
  assert.match(fn, /insert into private\.review_purchase_eligibility/i);
});

test("Commerce orders cannot be inserted directly by clients and are visible only to Buyer/Seller participants", () => {
  assert.match(commerceOrderSql, /revoke all on public\.commerce_orders,public\.commerce_order_events from public,anon,authenticated/i);
  assert.match(commerceOrderSql, /grant select on public\.commerce_orders,public\.commerce_order_events to authenticated/i);
  assert.match(commerceOrderSql, /commerce_orders_buyer_seller_read[\s\S]*?buyer_id=\(select auth\.uid\(\)\) or seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(commerceOrderSql, /commerce_order_events_participant_read[\s\S]*?o\.buyer_id=\(select auth\.uid\(\)\) or o\.seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(commerceOrderSql, /revoke all on function public\.create_commerce_order\(text,uuid,numeric,text,text\) from public,anon/i);
});


const verifiedReviewSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114130100_verified_purchase_reviews.sql"),
  "utf8"
);

test("Purchase eligibility records remain private and writable only by trusted service roles", () => {
  assert.match(verifiedReviewSql, /create table if not exists private\.review_purchase_eligibility/i);
  assert.match(verifiedReviewSql, /revoke all on private\.review_purchase_eligibility from public, anon, authenticated/i);
  assert.match(verifiedReviewSql, /grant select, insert, update on private\.review_purchase_eligibility to service_role/i);
  assert.doesNotMatch(verifiedReviewSql, /grant .*private\.review_purchase_eligibility to authenticated/i);
});

test("Public reviews expose only published rows while Buyers can read their own moderation state", () => {
  assert.match(verifiedReviewSql, /listing_reviews_public_anonymous_read[\s\S]*?review_status = 'published'/i);
  assert.match(verifiedReviewSql, /listing_reviews_public_or_owner_read[\s\S]*?review_status = 'published'[\s\S]*?buyer_id = \(select auth\.uid\(\)\)[\s\S]*?public\.is_nexora_admin\(\)[\s\S]*?aal2/i);
  assert.match(verifiedReviewSql, /grant select \(\s*id, listing_type, listing_id, rating, review_title, review_body,\s*reviewer_label, purchased_quantity, review_status, created_at\s*\) on public\.listing_reviews to anon,authenticated/i);
  assert.doesNotMatch(verifiedReviewSql, /grant select on public\.listing_reviews to anon,authenticated/i);
  const publicGrant = verifiedReviewSql.match(/grant select \(([\s\S]*?)\) on public\.listing_reviews to anon,authenticated/i);
  assert.ok(publicGrant, "public review column allowlist must exist");
  for (const privateField of ["buyer_id","reviewed_by","reviewed_at","moderation_note","updated_at"]) {
    assert.ok(!publicGrant[1].includes(privateField), "public review grant must omit " + privateField);
  }
  assert.match(verifiedReviewSql, /revoke all on public\.listing_reviews from public, anon, authenticated/i);
});

test("Review eligibility lookup is authenticated and scoped to the caller's completed purchase", () => {
  const fn = verifiedReviewSql.slice(
    verifiedReviewSql.indexOf("create or replace function public.get_my_review_eligibility("),
    verifiedReviewSql.indexOf("revoke all on function public.get_my_review_eligibility")
  );
  assert.match(fn, /security definer/i);
  assert.match(fn, /v_buyer uuid := auth\.uid\(\)/i);
  assert.match(fn, /e\.buyer_id=v_buyer and e\.consumed_at is null/i);
  assert.match(fn, /not exists \([\s\S]*?r\.buyer_id=v_buyer/i);
  assert.match(verifiedReviewSql, /revoke all on function public\.get_my_review_eligibility\(text,uuid\) from public, anon/i);
  assert.match(verifiedReviewSql, /grant execute on function public\.get_my_review_eligibility\(text,uuid\) to authenticated/i);
});

test("Review submission requires an active Buyer, approved listing and matching unconsumed purchase", () => {
  const fn = verifiedReviewSql.slice(
    verifiedReviewSql.indexOf("create or replace function public.submit_verified_listing_review("),
    verifiedReviewSql.indexOf("revoke all on function public.submit_verified_listing_review")
  );
  assert.match(fn, /p\.role='buyer' and p\.account_status='active'/i);
  assert.match(fn, /listing_status='approved'/i);
  assert.match(fn, /v_seller=v_buyer/i);
  assert.match(fn, /where e\.listing_type=p_listing_type and e\.listing_id=p_listing_id[\s\S]*?e\.buyer_id=v_buyer and e\.consumed_at is null[\s\S]*?for update/i);
  assert.match(fn, /A completed verified purchase is required before reviewing/i);
  assert.match(fn, /You have already reviewed this listing/i);
});

test("A Buyer can review a listing only once and submission consumes the selected purchase eligibility", () => {
  assert.match(verifiedReviewSql, /create unique index if not exists listing_reviews_one_per_buyer_listing_idx[\s\S]*?on public\.listing_reviews\(listing_type, listing_id, buyer_id\)/i);
  const fn = verifiedReviewSql.slice(
    verifiedReviewSql.indexOf("create or replace function public.submit_verified_listing_review("),
    verifiedReviewSql.indexOf("revoke all on function public.submit_verified_listing_review")
  );
  assert.match(fn, /insert into public\.listing_reviews/i);
  assert.match(fn, /update private\.review_purchase_eligibility\s*set consumed_at=now\(\)\s*where id=v_eligibility\.id/i);
});

test("Order completion creates a private review eligibility grant only after the Buyer completes receipt", () => {
  const fn = inventoryOrderSql.slice(
    inventoryOrderSql.indexOf("create or replace function private.transition_commerce_order("),
    inventoryOrderSql.indexOf("revoke all on function private.create_commerce_order")
  );
  assert.match(fn, /if v_next='completed' then[\s\S]*?insert into private\.review_purchase_eligibility/i);
  assert.match(fn, /v_order\.buyer_id,v_order\.order_code,v_order\.quantity,now\(\)/i);
  assert.match(fn, /on conflict\(listing_type,listing_id,buyer_id,purchase_reference\) do nothing/i);
});

test("Product and Service review UI requests eligibility and submits only through the verified-review RPC", () => {
  const ui = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadListingReviews("),
    marketplaceUi.indexOf("function renderProducts()")
  );
  assert.match(ui, /get_my_review_eligibility/);
  assert.match(ui, /eligibility\.can_review/);
  assert.match(ui, /submit_verified_listing_review/);
  assert.match(ui, /only NEXORA|completed|Verified Review/i);
});


const publicIdentitySql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261112050241_secure_public_profile_identity_projection.sql"),
  "utf8"
);
const publicDemandProjectionSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114160000_demand_inbox_quotations_subcategories.sql"),
  "utf8"
);
const marketplaceCorePrivacySql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261112050345_create_marketplace_core_schema.sql"),
  "utf8"
);

test("Public profile projection exposes only identity ID and full name to authenticated users", () => {
  const view = publicIdentitySql.slice(
    publicIdentitySql.indexOf("create or replace view public.public_profiles"),
    publicIdentitySql.indexOf("grant select on public.public_profiles")
  );
  assert.match(view, /select id,\s*full_name\s+from public\.public_identities/i);
  assert.match(publicIdentitySql, /grant select on public\.public_profiles to authenticated/i);
  assert.match(publicIdentitySql, /revoke all on public\.public_profiles from public, anon/i);
  assert.doesNotMatch(view, /email|phone|address|role|account_status/i);
});

test("Public Business projection excludes private Business Profile fields and publishes approved records only", () => {
  const table = marketplaceCorePrivacySql.slice(
    marketplaceCorePrivacySql.indexOf("create table public.public_businesses"),
    marketplaceCorePrivacySql.indexOf("create table public.products")
  );
  const sync = marketplaceCorePrivacySql.slice(
    marketplaceCorePrivacySql.indexOf("create or replace function public.sync_public_business()"),
    marketplaceCorePrivacySql.indexOf("revoke all on function public.sync_public_business()")
  );
  assert.match(table, /business_id uuid[\s\S]*?seller_id uuid[\s\S]*?display_name text[\s\S]*?country text[\s\S]*?city text/i);
  assert.doesNotMatch(table, /phone|email|address|tax|bank|account_number/i);
  assert.match(sync, /if new\.approval_status <> 'approved' then[\s\S]*?delete from public\.public_businesses/i);
  assert.match(sync, /insert into public\.public_businesses\(business_id,seller_id,display_name,country,city,updated_at\)/i);
});

test("Public Buyer Demand view is security-invoker and omits Buyer identity and contact columns", () => {
  const view = publicDemandProjectionSql.slice(
    publicDemandProjectionSql.indexOf("create or replace view public.public_buyer_demands"),
    publicDemandProjectionSql.indexOf("grant select on public.public_buyer_demands")
  );
  assert.match(view, /with \(security_invoker=true\)/i);
  assert.match(view, /select id,demand_code,product_name,category,description,specifications_quality,[\s\S]*?required_quantity,budget,currency,destination_country,destination_city,[\s\S]*?required_date,demand_status,created_at,subcategory/i);
  assert.doesNotMatch(view, /buyer_id|full_name|email|phone|contact_number|address/i);
  assert.match(publicDemandProjectionSql, /grant select \(subcategory\) on public\.buyer_demands to anon/i);
  assert.match(publicDemandProjectionSql, /grant select \([\s\S]*?required_date[\s\S]*?\) on public\.buyer_demands to authenticated/i);
  assert.match(publicDemandProjectionSql, /revoke select on public\.buyer_demands from authenticated/i);
});


const dualMarketGrantSql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114175118_add_dual_listing_market_category.sql"),
  "utf8"
);
const serviceListingPrivacySql = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261114160000_demand_inbox_quotations_subcategories.sql"),
  "utf8"
);

test("Authenticated Product reads are column-allowlisted and exclude Admin review metadata", () => {
  assert.match(dualMarketGrantSql, /revoke select on public\.products from authenticated/i);
  const grant = dualMarketGrantSql.match(/grant select \(([\s\S]*?)\) on public\.products to authenticated/i);
  assert.ok(grant, "authenticated Product column allowlist must exist");
  for (const field of ["id","business_id","seller_id","product_code","slug","product_name","category","subcategory","market_category","image_urls","description","origin","specifications_quality","price","currency","listing_status","created_at","updated_at","minimum_order_quantity","stock_tracking","stock_quantity","reserved_quantity","price_tiers"]) {
    assert.ok(grant[1].includes(field), "Product read allowlist must include " + field);
  }
  for (const privateField of ["admin_note","reviewed_by","reviewed_at"]) {
    assert.ok(!grant[1].includes(privateField), "Product read allowlist must omit " + privateField);
  }
  assert.doesNotMatch(dualMarketGrantSql, /grant select on public\.products to authenticated/i);
});

test("Authenticated Service listing reads omit review metadata and Seller notes use an owner-scoped RPC", () => {
  assert.match(serviceListingPrivacySql, /revoke select on public\.service_listings from authenticated/i);
  const grant = serviceListingPrivacySql.match(/grant select \(([^)]*)\) on public\.service_listings to authenticated/i);
  assert.ok(grant, "Service listing column allowlist must exist");
  for (const privateField of ["admin_note","reviewed_by","reviewed_at","business_id"]) {
    assert.ok(!grant[1].includes(privateField), "Service listing read allowlist must omit " + privateField);
  }
  const fn = serviceListingPrivacySql.slice(
    serviceListingPrivacySql.indexOf("create or replace function public.get_my_service_listing_review_notes()"),
    serviceListingPrivacySql.indexOf("revoke all on function public.get_my_service_listing_review_notes()")
  );
  assert.match(fn, /security definer[\s\S]*?set search_path=''/i);
  assert.match(fn, /s\.seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(fn, /p\.role='seller' and p\.account_status='active'/i);
  assert.match(fn, /public\.is_nexora_admin\(\) and \(select auth\.jwt\(\)->>'aal'\)='aal2'/i);
  assert.match(serviceListingPrivacySql, /revoke all on function public\.get_my_service_listing_review_notes\(\) from public,anon/i);
  assert.match(serviceListingPrivacySql, /grant execute on function public\.get_my_service_listing_review_notes\(\) to authenticated/i);
});

test("Seller Service dashboard loads private Admin notes only through the owner-scoped notes RPC", () => {
  const ui = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadSellerServices()"),
    marketplaceUi.indexOf("async function deleteService(")
  );
  assert.match(ui, /get_my_service_listing_review_notes/);
  assert.match(ui, /service_listing_id/);
  assert.match(ui, /admin_note:noteMap\.get\(s\.id\)/);
  assert.doesNotMatch(ui, /\.select\("[^"]*admin_note/);
});


test("Product review notes are returned only to the owning active Seller or MFA-protected Admin", () => {
  const fn = dualMarketGrantSql.slice(
    dualMarketGrantSql.indexOf("create or replace function public.get_my_product_listing_review_notes()"),
    dualMarketGrantSql.indexOf("revoke all on function public.get_my_product_listing_review_notes()")
  );
  assert.match(fn, /security definer[\s\S]*?set search_path=''/i);
  assert.match(fn, /p\.seller_id=\(select auth\.uid\(\)\)/i);
  assert.match(fn, /pr\.role='seller' and pr\.account_status='active'/i);
  assert.match(fn, /public\.is_nexora_admin\(\) and \(select auth\.jwt\(\)->>'aal'\)='aal2'/i);
  assert.match(dualMarketGrantSql, /revoke all on function public\.get_my_product_listing_review_notes\(\) from public,anon/i);
  assert.match(dualMarketGrantSql, /grant execute on function public\.get_my_product_listing_review_notes\(\) to authenticated/i);
});

test("Seller Product dashboard loads and displays review notes through the scoped RPC", () => {
  const ui = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadSellerDashboard()"),
    marketplaceUi.indexOf("async function loadSellerEditRequests(")
  );
  assert.match(ui, /get_my_product_listing_review_notes/);
  assert.match(ui, /reviewNotes\.get\(p\.id\)/);
  assert.match(ui, /admin_note: reviewNotes/);
  assert.match(ui, /Admin Note:/);
  assert.doesNotMatch(ui, /\.select\("[^"]*admin_note/);
});


test("Buyer Demand negotiation RPC caps Buyer and Seller counter quantities at requested demand quantity", () => {
  const fn = demandOrderSql.slice(
    demandOrderSql.indexOf("create or replace function private.respond_to_demand_offer("),
    demandOrderSql.indexOf("revoke all on function private.respond_to_demand_offer")
  );
  assert.ok(fn.includes("v_demand_qty:=nullif(substring(regexp_replace(btrim(v_demand.required_quantity),',','','g') from '^[0-9]+([.][0-9]+)?'),'')::numeric"));
  assert.ok(fn.includes("p_quantity>least(coalesce(nullif(v_offer.available_quantity,'')::numeric,0),v_demand_qty)"));
  assert.ok(fn.includes("least(v_latest.proposed_quantity,v_demand_qty)"));
  assert.ok(fn.includes("v_qty>v_demand_qty"));
});

test("Buyer Demand requested quantity parser accepts numeric amounts followed by units", () => {
  assert.ok(demandOrderSql.includes("v_demand_qty:=nullif(substring(regexp_replace(btrim(v_demand.required_quantity),',','','g') from '^[0-9]+([.][0-9]+)?'),'')::numeric"));
  assert.match(demandOrderSql, /if v_demand_qty is null or v_demand_qty<=0 then raise exception 'Buyer Demand quantity is invalid'/i);
});


test("Seller Demand quotations must use the Buyer Demand's selected currency", () => {
  const trigger = demandOrderSql.slice(
    demandOrderSql.indexOf("create or replace function private.initialise_seller_offer_negotiation()"),
    demandOrderSql.indexOf("revoke all on function private.initialise_seller_offer_negotiation()")
  );
  assert.match(trigger, /upper\(new\.currency\)<>upper\(v_demand\.currency\)/i);
  assert.match(trigger, /Quotation currency must match the Buyer Demand currency/i);
});


test("Demand negotiation and order creation revalidate the quoted Seller's active approved Business Profile", () => {
  const fn = demandOrderSql.slice(
    demandOrderSql.indexOf("create or replace function private.respond_to_demand_offer("),
    demandOrderSql.indexOf("create or replace function private.transition_buyer_demand_order(")
  );
  assert.match(fn, /p_action in \('accept','counter'\)[\s\S]*?p\.role='seller' and p\.account_status='active'[\s\S]*?public\.public_businesses b where b\.seller_id=v_offer\.seller_id/i);
  assert.match(fn, /quoted Seller must remain active with an approved Business Profile/i);
});


test("Buyer and Seller Demand dashboards parse numeric quantities followed by units", () => {
  const buyer = marketplaceUi.slice(
    marketplaceUi.indexOf("function renderBuyerDashboard(offers)"),
    marketplaceUi.indexOf("async function respondToDemandQuotation(")
  );
  const seller = marketplaceUi.slice(
    marketplaceUi.indexOf("async function loadSellerDemandInbox()"),
    marketplaceUi.indexOf("const serviceCategoryLabels")
  );
  assert.ok(buyer.includes('Number.parseFloat(String(d.required_quantity||"").replace(/,/g,""))'));
  assert.match(buyer, /Number\.isFinite\(demandQuantity\)&&demandQuantity>0/);
  assert.ok(seller.includes('Number.parseFloat(String(d.required_quantity||"").replace(/,/g,""))'));
  assert.match(seller, /maxNegotiableQuantity>0/);
});


test("Seller quotation insert rejects a Buyer Demand with invalid or non-positive requested quantity", () => {
  const trigger = demandOrderSql.slice(
    demandOrderSql.indexOf("create or replace function private.initialise_seller_offer_negotiation()"),
    demandOrderSql.indexOf("revoke all on function private.initialise_seller_offer_negotiation()")
  );
  assert.ok(trigger.includes("v_demand_qty:=nullif(substring(regexp_replace(btrim(v_demand.required_quantity),',','','g') from '^[0-9]+([.][0-9]+)?'),'')::numeric"));
  assert.ok(trigger.includes("if v_demand_qty is null or v_demand_qty<=0 then\n    raise exception 'Buyer Demand quantity must start with a positive numeric amount'"));
});


test("Buyer Demand owners can update only demand status, not posted commercial terms", () => {
  assert.match(demandOrderSql, /revoke update on public\.buyer_demands from authenticated/i);
  assert.match(demandOrderSql, /revoke update \(subcategory\) on public\.buyer_demands from authenticated/i);
  assert.match(demandOrderSql, /grant update \(demand_status\) on public\.buyer_demands to authenticated/i);
});
