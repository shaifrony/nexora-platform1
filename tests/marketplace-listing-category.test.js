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
