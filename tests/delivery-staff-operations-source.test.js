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

const adminUi = fs.readFileSync(path.join(process.cwd(), "delivery-network-admin.js"), "utf8");
const workerUi = fs.readFileSync(path.join(process.cwd(), "transport-provider.js"), "utf8");

test("worker workspace uses scoped queue, guarded status, private evidence and dispute RPCs", () => {
  assert.match(workerUi, /get_my_assigned_delivery_jobs/);
  assert.match(workerUi, /update_my_delivery_job_status/);
  assert.match(workerUi, /record_delivery_proof/);
  assert.match(workerUi, /nexora-delivery-evidence/);
  assert.match(workerUi, /raise_delivery_dispute/);
  assert.match(workerUi, /get_my_delivery_proof_records/);
  assert.match(workerUi, /get_my_delivery_disputes/);
});

test("Admin UI loads and reviews disputes only through guarded RPCs", () => {
  assert.match(adminUi, /get_admin_delivery_disputes/);
  assert.match(adminUi, /review_delivery_dispute/);
  assert.match(adminUi, /nxDeliveryDisputesList/);
});

test("Buyer and Seller proof/dispute reads are bound to their own Commerce Order IDs", () => {
  assert.match(sql, /create or replace function private\.get_my_order_delivery_operations/);
  assert.match(sql, /o\.buyer_id=v_actor or o\.seller_id=v_actor/);
  assert.match(sql, /create or replace function public\.get_my_order_delivery_operations/);
});

const marketplaceUi = fs.readFileSync(path.join(process.cwd(), "marketplace.js"), "utf8");

test("Buyer and Seller order dashboards show scoped delivery evidence and can raise disputes", () => {
  assert.match(marketplaceUi, /get_my_order_delivery_operations/);
  assert.match(marketplaceUi, /orderDeliveryOperationsHtml/);
  assert.match(marketplaceUi, /createSignedUrl\(img\.dataset\.orderProofPath,300\)/);
  assert.match(marketplaceUi, /raise_delivery_dispute/);
  assert.match(marketplaceUi, /wireOrderDeliveryOperations\(host,loadBuyerOrders\)/);
  assert.match(marketplaceUi, /wireOrderDeliveryOperations\(host,loadSellerOrders\)/);
});

test("Admin UI cannot set Delivered through ordinary tracking status updates", () => {
  const transitionBlock = adminUi.match(/const transitions=\{([^;]+)\};/);
  assert.ok(transitionBlock, "Admin status transition map should exist");
  assert.doesNotMatch(transitionBlock[1], /out_for_delivery:\[([^\]]*\bdelivered\b)|partially_delivered:\[([^\]]*\bdelivered\b)|disputed:\[([^\]]*\bdelivered\b)/);
  assert.match(adminUi, /verify_delivery_receipt_code/);
});


const buyerOrderLoaderStart = marketplaceUi.indexOf("async function loadBuyerOrders(){");
const buyerOrderLoaderEnd = marketplaceUi.indexOf("async function updateSellerProductInventory", buyerOrderLoaderStart);
const buyerOrderLoader = marketplaceUi.slice(buyerOrderLoaderStart, buyerOrderLoaderEnd);

test("Buyer Order History uses the customer-safe own-order tracking RPC, never raw delivery tables", () => {
  assert.ok(buyerOrderLoaderStart >= 0 && buyerOrderLoaderEnd > buyerOrderLoaderStart);
  assert.match(buyerOrderLoader, /\.eq\("buyer_id",user\(\)\.id\)/);
  assert.match(buyerOrderLoader, /rpc\("get_my_order_delivery_updates",\{p_order_ids:rows\.map\(o=>o\.id\)\}\)/);
  assert.doesNotMatch(buyerOrderLoader, /\.from\(["']delivery_(?:jobs|tracking_events|customer_updates)["']\)/i);
  for (const field of ["job_reference", "customer_message", "customer_location_label"]) {
    assert.match(buyerOrderLoader, new RegExp("esc\\\\(u\\\\." + field + "\\\\)"));
  }
  assert.match(buyerOrderLoader, /esc\\(deliveryStatusLabels\\[u\\.customer_status\\]\\|\\|u\\.customer_status\\)/);
  assert.match(buyerOrderLoader, /ডেলিভারি সম্পন্নের রিপোর্ট/);
  assert.match(buyerOrderLoader, /ডেলিভারি রিপোর্ট মানেই অর্ডার সম্পন্ন নয়/);
  assert.match(buyerOrderLoader, /এখনো কোনো প্রকাশিত ডেলিভারি আপডেট নেই/);
});

test("Buyer receipt OTP is offered only for an out-for-delivery own-order job and rendered as text", () => {
  assert.match(buyerOrderLoader, /job\.job_status==="out_for_delivery"/);
  assert.match(buyerOrderLoader, /rpc\("request_delivery_receipt_code",\{p_job_id:jobId\}\)/);
  assert.match(buyerOrderLoader, /output\.textContent="আপনার রিসিপ্ট OTP: "\+data\.code/);
  assert.doesNotMatch(buyerOrderLoader, /output\.innerHTML/);
});


test("Buyer delivery status labels are mapped to Bengali and escaped, including unknown fallback values", () => {
  assert.ok(buyerOrderLoader.includes('deliveryStatusLabels={'));
  assert.ok(buyerOrderLoader.includes('preparing:"ডেলিভারি প্রস্তুতি"'));
  assert.ok(buyerOrderLoader.includes('delivered:"ডেলিভারি সম্পন্নের রিপোর্ট"'));
  assert.ok(buyerOrderLoader.includes('esc(deliveryStatusLabels[u.customer_status]||u.customer_status)'));
});
