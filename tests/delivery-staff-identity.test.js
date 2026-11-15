const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/20261115180000_delivery_staff_receipt_identity.sql"),
  "utf8"
);
const adminUi = fs.readFileSync(path.join(root, "delivery-network-admin.js"), "utf8");
const staffUi = fs.readFileSync(path.join(root, "transport-provider.js"), "utf8");

test("staff identity binding requires confirmed Auth contact and privileged Admin MFA", () => {
  assert.match(migration, /auth\.users/);
  assert.match(migration, /email_confirmed_at is not null/);
  assert.match(migration, /phone_confirmed_at is not null/);
  assert.match(migration, /auth\.jwt\(\)->>'aal'\)\s+is distinct from 'aal2'/);
  assert.match(migration, /private\.has_nexora_permission\('logistics\.assign'\)/);
  assert.match(migration, /delivery_network_staff_auth_user_uidx/);
  assert.match(migration, /staff_identity_bound/);
});

test("NEXORA team and courier field workers require an active bound account", () => {
  assert.match(migration, /v_partner_kind<>'courier_company'/);
  assert.match(migration, /worker\.account_status='active'/);
  assert.match(migration, /s\.auth_user_id=v_actor/);
  assert.match(migration, /j\.assignment_source in \('nexora_team','courier_partner'\)/);
  assert.match(migration, /actor_type[\s\S]*?'delivery_staff'/);
});

test("Admin UI can bind or unbind staff and dispatch either partner type to linked staff", () => {
  assert.match(adminUi, /rpc\("bind_delivery_network_staff_identity"/);
  assert.match(adminUi, /rpc\("unbind_delivery_network_staff_identity"/);
  assert.match(adminUi, /p_staff_id:\["nexora_team","courier_partner"\]\.includes\(source\)\?get\("staff"\):null/);
  assert.match(adminUi, /activeStaff\.filter\(s=>s\.auth_user_id\)/);
});

test("signed-in field workers receive only their own receipt queue and can verify OTP", () => {
  assert.match(staffUi, /rpc\("get_my_assigned_staff_receipt_jobs"\)/);
  assert.match(staffUi, /rpc\("verify_delivery_receipt_code"/);
  assert.match(staffUi, /data-staff-receipt-form/);
});
