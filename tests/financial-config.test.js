"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const finance = require("../financial-config.js");

function schedule(overrides = {}) {
  return {
    schedule_id: "test-schedule-v1",
    version: 1,
    currency: "BDT",
    effective_from: "2026-01-01T00:00:00+06:00",
    effective_until: null,
    status: "approved",
    fees: {
      marketplace_commission: {
        wholesale_bps: 250,
        retail_bps: 400,
        wholesale_basis: "gross_sale",
        retail_basis: "gross_sale"
      },
      buyer_agent_fee: {
        required_when_agent_used: true,
        rate_bps: 200,
        basis: "gross_sale"
      },
      transport_split: {
        carrier_bps: 5000,
        local_distribution_bps: 3600,
        nexora_bps: 1400
      }
    },
    ...overrides
  };
}

function input(overrides = {}) {
  return {
    order_id: "order-1",
    schedule: schedule(),
    sale_type: "wholesale",
    amount_bases_minor: { gross_sale: 100000 },
    transport_charge_minor: 10001,
    buyer_agent_used: true,
    ...overrides
  };
}

test("accepts a structurally valid financial schedule", () => {
  assert.equal(finance.validateSchedule(schedule()), true);
});
test("rejects unknown sale types", () => {
  assert.throws(() => finance.calculateOrderFees(input({ sale_type: "mixed" })), /sale_type/);
});
test("calculates wholesale commission and Buyer Agent fee only when used", () => {
  const result = finance.calculateOrderFees(input());
  assert.equal(result.marketplace_commission_minor, 2500);
  assert.equal(result.buyer_agent_fee_minor, 2000);
});
test("does not charge Buyer Agent fee when no Buyer Agent is used", () => {
  const result = finance.calculateOrderFees(input({ buyer_agent_used: false }));
  assert.equal(result.buyer_agent_fee_minor, 0);
  assert.equal(result.buyer_agent_fee_basis, null);
});
test("selects retail commission independently from wholesale", () => {
  const result = finance.calculateOrderFees(input({ sale_type: "retail" }));
  assert.equal(result.marketplace_commission_rate_bps, 400);
  assert.equal(result.marketplace_commission_minor, 4000);
});
test("transport allocation preserves every minor currency unit", () => {
  const result = finance.calculateOrderFees(input());
  const parts = result.transport_carrier_share_minor + result.transport_local_distribution_share_minor + result.transport_nexora_share_minor;
  assert.equal(parts, 10001);
  assert.deepEqual([result.transport_carrier_share_minor, result.transport_local_distribution_share_minor, result.transport_nexora_share_minor], [5001, 3600, 1400]);
});
test("rejects transport shares that do not total 100 percent", () => {
  const bad = schedule();
  bad.fees.transport_split.nexora_bps = 1399;
  assert.throws(() => finance.validateSchedule(bad), /total exactly 10000/);
});
test("rejects rates outside the allowed basis-point range", () => {
  const bad = schedule();
  bad.fees.marketplace_commission.retail_bps = 10001;
  assert.throws(() => finance.validateSchedule(bad), /basis points/);
});
test("rejects missing calculation bases rather than silently using zero", () => {
  assert.throws(() => finance.calculateOrderFees(input({ amount_bases_minor: {} })), /Missing amount base/);
});
test("rejects negative and unsafe monetary minor-unit inputs", () => {
  assert.throws(() => finance.calculateOrderFees(input({ transport_charge_minor: -1 })), /non-negative safe integer/);
  assert.throws(() => finance.calculateOrderFees(input({ amount_bases_minor: { gross_sale: Number.MAX_SAFE_INTEGER + 1 } })), /non-negative safe integer/);
});
test("rejects an unapproved schedule for order pricing", () => {
  assert.throws(() => finance.calculateOrderFees(input({ schedule: schedule({ status: "draft" }) })), /Only an approved/);
});
test("rejects overlapping effective approved schedules", () => {
  const a = schedule();
  const b = schedule({ schedule_id: "test-schedule-v2", version: 2, effective_from: "2026-02-01T00:00:00+06:00" });
  assert.throws(() => finance.selectEffectiveSchedule([a, b], "2026-03-01T00:00:00+06:00"), /overlap/);
});
test("does not select a schedule outside its effective interval", () => {
  const a = schedule({ effective_until: "2026-02-01T00:00:00+06:00" });
  assert.throws(() => finance.selectEffectiveSchedule([a], "2026-02-01T00:00:00+06:00"), /No approved financial schedule/);
});
test("creates an immutable order fee snapshot tied to schedule version", () => {
  const snapshot = finance.createOrderFeeSnapshot(input());
  assert.equal(snapshot.order_id, "order-1");
  assert.equal(snapshot.schedule_version, 1);
  assert.equal(snapshot.sale_type, "wholesale");
  assert.equal(Object.isFrozen(snapshot), true);
});
test("rejects a snapshot without an order id", () => {
  assert.throws(() => finance.createOrderFeeSnapshot(input({ order_id: " " })), /order_id is required/);
});
