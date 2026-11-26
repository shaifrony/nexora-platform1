const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const ui = fs.readFileSync(path.join(root, "delivery-network-admin.js"), "utf8");
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/20261115170000_admin_delivery_order_linking.sql"),
  "utf8"
);

test("Admin Delivery Network loads only server-authorized ready Order candidates", () => {
  assert.match(ui, /rpc\("get_admin_delivery_order_candidates"\)/);
  assert.match(migration, /o\.order_status='ready_for_confirmation'/);
  assert.match(migration, /o\.listing_type='product'/);
  assert.match(migration, /private\.has_nexora_permission\('logistics\.assign'\)/);
  assert.match(migration, /auth\.jwt\(\)->>'aal'\)\s+is distinct from 'aal2'/);
});

test("Order-linked Delivery Job creation carries the selected Commerce Order ID", () => {
  assert.match(ui, /rpc\("create_delivery_network_job_from_order",\s*\{p_commerce_order_id:orderId,\.\.\.p\}\)/);
  assert.match(migration, /where o\.id=p_commerce_order_id\s+for update/i);
  assert.match(migration, /v_order_status<>'ready_for_confirmation' or v_listing_type<>'product'/);
  assert.match(migration, /p_special_instructions,p_delivery_mode,p_commerce_order_id/);
});

test("Manual Delivery Request clears every Order-prefilled address and reference", () => {
  assert.match(ui, /if\(!order\)\s*\{[\s\S]*?\["external_reference",""\][\s\S]*?\["pickup_address",""\][\s\S]*?\["delivery_address",""\]/);
  assert.match(ui, /rpc\("create_delivery_network_job",\{\.\.\.p,p_commerce_order_id:null\}\)/);
});
