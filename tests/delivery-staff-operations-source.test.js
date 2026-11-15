const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const migrationPath = path.join(
  process.cwd(),
  "supabase",
  "migrations",
  "20261115190000_delivery_staff_status_proof_partial_and_disputes.sql"
);
const sql = fs.readFileSync(migrationPath, "utf8");

test("delivery staff operations are exposed only through guarded RPCs", () => {
  assert.match(sql, /private\.is_assigned_delivery_staff\(p_job_id\)/);
  assert.match(sql, /create or replace function private\.update_my_delivery_job_status/);
  assert.match(sql, /create or replace function public\.get_my_assigned_delivery_jobs/);
  assert.match(sql, /revoke all on function public\.update_my_delivery_job_status[^;]+from public,anon/i);
  assert.match(sql, /actor_type\)\s*values\(p_job_id,v_old,p_next_status[^;]*'delivery_staff'\)/i);
});

test("worker cannot mark a job delivered without Buyer receipt OTP", () => {
  assert.match(sql, /p_next_status not in \('accepted','picked_up','in_transit','out_for_delivery','delivery_failed'\)/);
  assert.doesNotMatch(sql, /p_next_status not in \([^)]*'delivered'/);
});

test("proof evidence is private, scoped to a job folder and append-only", () => {
  assert.match(sql, /values\('nexora-delivery-evidence','nexora-delivery-evidence',false\)/);
  assert.match(sql, /create policy nexora_delivery_evidence_upload[\s\S]*private\.can_manage_delivery_job_evidence/);
  assert.match(sql, /create policy nexora_delivery_evidence_read[\s\S]*private\.can_read_delivery_job_evidence/);
  assert.doesNotMatch(sql, /create policy nexora_delivery_evidence_(?:update|delete)/);
  assert.match(sql, /create table if not exists private\.delivery_proof_records/);
  assert.match(sql, /revoke all on private\.delivery_proof_records,private\.delivery_disputes from public,anon,authenticated/);
  assert.match(sql, /delivered quantity cannot exceed the ordered quantity/i);
});

test("dispute initiation checks Buyer, Seller, assigned worker or Admin identity", () => {
  assert.match(sql, /create or replace function private\.raise_delivery_dispute/);
  assert.match(sql, /Only the order Buyer\/Seller, assigned worker or AAL2 logistics Admin can raise a dispute/);
  assert.match(sql, /create or replace function private\.review_delivery_dispute/);
  assert.match(sql, /Active Admin MFA and logistics\.assign permission required/);
  assert.match(sql, /delivery_dispute\.reviewed/);
});

test("private proof and dispute retrieval is authorization-scoped", () => {
  assert.match(sql, /private\.get_my_delivery_proof_records/);
  assert.match(sql, /private\.get_my_delivery_disputes/);
  assert.match(sql, /private\.can_read_delivery_job_evidence\(p_job_id\)/);
});

test("unauthorized users cannot infer whether a delivery already has an active dispute", () => {
  const start = sql.indexOf("create or replace function private.raise_delivery_dispute");
  const end = sql.indexOf("create or replace function public.raise_delivery_dispute", start);
  const body = sql.slice(start, end);
  assert.ok(body.indexOf("Only the order Buyer/Seller, assigned worker or AAL2 logistics Admin can raise a dispute") <
    body.indexOf("An active dispute already exists for this delivery"));
});

test("Admin dispute queue requires AAL2 and logistics.view permission", () => {
  assert.match(sql, /create or replace function private\.get_admin_delivery_disputes/);
  assert.match(sql, /Active Admin MFA and logistics\.view permission required/);
  assert.match(sql, /create or replace function public\.get_admin_delivery_disputes/);
});
