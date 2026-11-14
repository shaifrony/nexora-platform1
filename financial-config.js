/* NEXORA Financial Configuration Domain
 * Pure validation/calculation only. No defaults, persistence, payment or payout actions.
 * All rates must be supplied by an approved, effective-dated server configuration.
 */
(function (root) {
  "use strict";

  const BPS_DENOMINATOR = 10000;
  const SALE_TYPES = new Set(["wholesale", "retail"]);

  function assert(condition, message) {
    if (!condition) throw new TypeError(message);
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function assertBps(value, label) {
    assert(Number.isSafeInteger(value) && value >= 0 && value <= BPS_DENOMINATOR,
      label + " must be an integer from 0 to 10000 basis points.");
  }

  function assertMinorUnits(value, label) {
    assert(Number.isSafeInteger(value) && value >= 0,
      label + " must be a non-negative safe integer in minor currency units.");
  }

  function validateSchedule(schedule) {
    assert(isPlainObject(schedule), "A financial schedule object is required.");
    assert(typeof schedule.schedule_id === "string" && schedule.schedule_id.trim(), "schedule_id is required.");
    assert(Number.isSafeInteger(schedule.version) && schedule.version > 0, "A positive schedule version is required.");
    assert(typeof schedule.currency === "string" && /^[A-Z]{3}$/.test(schedule.currency), "A three-letter uppercase currency code is required.");
    assert(typeof schedule.effective_from === "string" && !Number.isNaN(Date.parse(schedule.effective_from)), "A valid effective_from date is required.");
    assert(["draft", "pending_approval", "approved", "retired"].includes(schedule.status), "Invalid schedule status.");
    if (schedule.effective_until != null) {
      assert(!Number.isNaN(Date.parse(schedule.effective_until)), "effective_until must be a valid date.");
      assert(Date.parse(schedule.effective_until) > Date.parse(schedule.effective_from), "effective_until must be after effective_from.");
    }

    const fees = schedule.fees;
    assert(isPlainObject(fees), "fees configuration is required.");
    assert(isPlainObject(fees.marketplace_commission), "marketplace_commission configuration is required.");
    assertBps(fees.marketplace_commission.wholesale_bps, "Wholesale commission");
    assertBps(fees.marketplace_commission.retail_bps, "Retail commission");
    assert(typeof fees.marketplace_commission.wholesale_basis === "string" && fees.marketplace_commission.wholesale_basis.trim(), "Wholesale commission basis is required.");
    assert(typeof fees.marketplace_commission.retail_basis === "string" && fees.marketplace_commission.retail_basis.trim(), "Retail commission basis is required.");

    assert(isPlainObject(fees.buyer_agent_fee), "buyer_agent_fee configuration is required.");
    assert(fees.buyer_agent_fee.required_when_agent_used === true, "Buyer Agent fee must be mandatory when Buyer Agent service is used.");
    assertBps(fees.buyer_agent_fee.rate_bps, "Buyer Agent fee");
    assert(typeof fees.buyer_agent_fee.basis === "string" && fees.buyer_agent_fee.basis.trim(), "Buyer Agent fee basis is required.");

    assert(isPlainObject(fees.transport_split), "transport_split configuration is required.");
    const split = fees.transport_split;
    assertBps(split.carrier_bps, "Carrier share");
    assertBps(split.local_distribution_bps, "Local Distribution share");
    assertBps(split.nexora_bps, "NEXORA logistics share");
    assert(split.carrier_bps + split.local_distribution_bps + split.nexora_bps === BPS_DENOMINATOR,
      "Transport shares must total exactly 10000 basis points.");

    return true;
  }

  function selectEffectiveSchedule(schedules, at) {
    assert(Array.isArray(schedules), "Schedules must be an array.");
    const instant = at == null ? Date.now() : Date.parse(at);
    assert(Number.isFinite(instant), "A valid schedule-selection date is required.");
    const eligible = schedules.filter((schedule) => {
      if (schedule.status !== "approved") return false;
      validateSchedule(schedule);
      const start = Date.parse(schedule.effective_from);
      const end = schedule.effective_until == null ? Infinity : Date.parse(schedule.effective_until);
      return start <= instant && instant < end;
    });
    assert(eligible.length > 0, "No approved financial schedule is effective for this date.");
    assert(eligible.length === 1, "Multiple approved financial schedules overlap for this date.");
    return eligible[0];
  }

  function calculateBasisPoints(amountMinor, bps) {
    assertMinorUnits(amountMinor, "Fee base");
    assertBps(bps, "Fee rate");
    const amount = BigInt(amountMinor);
    const rate = BigInt(bps);
    const rounded = (amount * rate + 5000n) / 10000n;
    assert(rounded <= BigInt(Number.MAX_SAFE_INTEGER), "Calculated fee exceeds the safe integer range.");
    return Number(rounded);
  }

  function calculateOrderFees(input) {
    assert(isPlainObject(input), "Order fee input is required.");
    const schedule = input.schedule;
    validateSchedule(schedule);
    assert(schedule.status === "approved", "Only an approved financial schedule can price an order.");
    assert(SALE_TYPES.has(input.sale_type), "sale_type must be wholesale or retail.");
    assert(isPlainObject(input.amount_bases_minor), "Configurable fee amount bases are required.");
    Object.entries(input.amount_bases_minor).forEach(([key, value]) => {
      assert(key.trim(), "Fee amount-base keys cannot be empty.");
      assertMinorUnits(value, "Fee amount base " + key);
    });
    assertMinorUnits(input.transport_charge_minor, "Transport charge");
    assert(typeof input.buyer_agent_used === "boolean", "buyer_agent_used must be explicitly true or false.");

    const commissionConfig = schedule.fees.marketplace_commission;
    const commissionRate = input.sale_type === "wholesale"
      ? commissionConfig.wholesale_bps
      : commissionConfig.retail_bps;
    const commissionBasis = input.sale_type === "wholesale"
      ? commissionConfig.wholesale_basis
      : commissionConfig.retail_basis;
    assert(Object.prototype.hasOwnProperty.call(input.amount_bases_minor, commissionBasis),
      "Missing amount base for marketplace commission: " + commissionBasis);
    const commissionBase = input.amount_bases_minor[commissionBasis];
    const marketplaceCommission = calculateBasisPoints(commissionBase, commissionRate);
    const buyerFeeBasis = schedule.fees.buyer_agent_fee.basis;
    const buyerFeeBase = input.buyer_agent_used
      ? (assert(Object.prototype.hasOwnProperty.call(input.amount_bases_minor, buyerFeeBasis),
          "Missing amount base for Buyer Agent fee: " + buyerFeeBasis), input.amount_bases_minor[buyerFeeBasis])
      : 0;
    const buyerAgentFee = input.buyer_agent_used
      ? calculateBasisPoints(buyerFeeBase, schedule.fees.buyer_agent_fee.rate_bps)
      : 0;
    const transport = input.transport_charge_minor;
    const split = schedule.fees.transport_split;
    const carrierShare = calculateBasisPoints(transport, split.carrier_bps);
    const localDistributionShare = calculateBasisPoints(transport, split.local_distribution_bps);
    // Assign rounding remainder to NEXORA so the three allocations always equal the charge exactly.
    const nexoraShare = transport - carrierShare - localDistributionShare;
    assert(nexoraShare >= 0, "Rounded transport allocations exceed the transport charge.");

    return Object.freeze({
      currency: schedule.currency,
      marketplace_commission_basis: commissionBasis,
      marketplace_commission_rate_bps: commissionRate,
      marketplace_commission_base_minor: commissionBase,
      marketplace_commission_minor: marketplaceCommission,
      buyer_agent_fee_basis: input.buyer_agent_used ? buyerFeeBasis : null,
      buyer_agent_fee_rate_bps: input.buyer_agent_used ? schedule.fees.buyer_agent_fee.rate_bps : 0,
      buyer_agent_fee_base_minor: buyerFeeBase,
      buyer_agent_fee_minor: buyerAgentFee,
      transport_carrier_share_bps: split.carrier_bps,
      transport_local_distribution_share_bps: split.local_distribution_bps,
      transport_nexora_share_bps: split.nexora_bps,
      transport_charge_minor: transport,
      transport_carrier_share_minor: carrierShare,
      transport_local_distribution_share_minor: localDistributionShare,
      transport_nexora_share_minor: nexoraShare,
      schedule_id: schedule.schedule_id,
      schedule_version: schedule.version
    });
  }

  function createOrderFeeSnapshot(input) {
    const fees = calculateOrderFees(input);
    const snapshot = {
      ...fees,
      order_id: String(input.order_id || ""),
      sale_type: input.sale_type,
      schedule_effective_from: input.schedule.effective_from
    };
    assert(snapshot.order_id.trim(), "order_id is required for an order fee snapshot.");
    return Object.freeze(snapshot);
  }

  const api = Object.freeze({
    validateSchedule,
    selectEffectiveSchedule,
    calculateOrderFees,
    createOrderFeeSnapshot
  });

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (root) Object.defineProperty(root, "NEXORA_FINANCE", { value: api, configurable: false, writable: false });
})(typeof window !== "undefined" ? window : globalThis);
