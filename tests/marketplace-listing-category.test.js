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
