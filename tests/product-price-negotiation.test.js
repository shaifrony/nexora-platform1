"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const migration = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261115110000_product_price_negotiation.sql"),
  "utf8"
);
const marketplace = fs.readFileSync(path.join(__dirname, "..", "marketplace.js"), "utf8");

const privateStart = migration.indexOf("create or replace function private.respond_to_product_price_negotiation(");
const publicStart = migration.indexOf("create or replace function public.respond_to_product_price_negotiation(");
assert.ok(privateStart >= 0 && publicStart > privateStart, "both private and public response RPCs must exist");
const privateRpc = migration.slice(privateStart, publicStart);
const publicRpc = migration.slice(publicStart);

test("Product Price negotiation rejects NULL and unsupported actions explicitly", () => {
  assert.match(privateRpc, /if p_action is null or p_action not in \('counter','accept','reject'\) then/i);
});

test("only the other participant may reject the latest Product Price proposal", () => {
  const rejectStart = privateRpc.indexOf("if p_action='reject' then");
  const rejectEnd = privateRpc.indexOf("if p_action='counter' then", rejectStart);
  assert.ok(rejectStart >= 0 && rejectEnd > rejectStart, "reject branch must precede counter branch");
  const rejectBranch = privateRpc.slice(rejectStart, rejectEnd);
  assert.match(rejectBranch, /if v_actor=v_n\.last_actor_id then/i);
  assert.match(rejectBranch, /negotiation_status='rejected'/i);
  assert.match(rejectBranch, /product_price_negotiation_events/i);
});

test("rejection remains available when stock or MOQ changes after a proposal", () => {
  const rejectStart = privateRpc.indexOf("if p_action='reject' then");
  const availabilityCheck = privateRpc.indexOf("v_available:=case", privateRpc.indexOf("select role into v_role"));
  assert.ok(rejectStart > 0 && availabilityCheck > rejectStart,
    "current MOQ/stock validation must not block a participant from rejecting a stale proposal");
});

test("Product Price negotiation serializes concurrent changes and prevents self-acceptance", () => {
  assert.match(privateRpc, /from public\.product_price_negotiations where id=p_negotiation_id for update/i);
  assert.match(privateRpc, /if v_actor=v_n\.last_actor_id then raise exception 'The other party must accept your latest proposal'/i);
  assert.match(privateRpc, /from public\.products where id=v_n\.product_id for update/i);
});

test("accepted Product Price terms create a Commerce Order and reserve tracked stock", () => {
  assert.match(privateRpc, /update public\.products set reserved_quantity=reserved_quantity\+v_n\.quantity/i);
  assert.match(privateRpc, /insert into public\.commerce_orders\([\s\S]*?v_n\.quantity,v_n\.current_unit_price,v_n\.currency/i);
  assert.match(privateRpc, /negotiation_status='ordered',order_id=v_order_id/i);
});

test("private Product Price RPC is SECURITY DEFINER with an empty search_path", () => {
  const header = privateRpc.slice(0, privateRpc.indexOf("as $$"));
  assert.match(header, /security definer/i);
  assert.match(header, /set search_path\s*=\s*''/i);
});

test("public Product Price RPC is SECURITY INVOKER and unavailable to anonymous users", () => {
  const header = publicRpc.slice(0, publicRpc.indexOf("as $$"));
  assert.match(header, /security invoker/i);
  assert.match(migration, /revoke all on function public\.start_product_price_negotiation\(uuid,numeric,numeric,text,text\) from public,anon,authenticated;/i);
  assert.match(migration, /revoke all on function public\.respond_to_product_price_negotiation\(uuid,text,numeric,numeric,text,text\) from public,anon;/i);
  assert.match(migration, /grant execute on function public\.start_product_price_negotiation\(uuid,numeric,numeric,text,text\) to authenticated;/i);
  assert.match(migration, /grant execute on function public\.respond_to_product_price_negotiation\(uuid,text,numeric,numeric,text,text\) to authenticated;/i);
});

test("Buyer and Seller dashboards use the Product Price negotiation RPCs and participant-scoped reads", () => {
  assert.match(marketplace, /rpc\("start_product_price_negotiation"/);
  assert.match(marketplace, /rpc\("respond_to_product_price_negotiation"/);
  assert.match(marketplace, /\.from\("product_price_negotiations"\)[\s\S]*?\.eq\("buyer_id",user\(\)\.id\)/);
  assert.match(marketplace, /\.from\("product_price_negotiations"\)[\s\S]*?\.eq\("seller_id",user\(\)\.id\)/);
});
