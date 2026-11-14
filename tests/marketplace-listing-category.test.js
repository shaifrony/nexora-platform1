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
