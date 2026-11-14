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
