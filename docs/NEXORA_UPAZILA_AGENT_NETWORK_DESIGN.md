# NEXORA Upazila Agent Network & Direct-Seller Fulfilment Design

Status: **User-approved functional requirement; operational and financial controls require further decisions.**
Date: 2026-11-14
Scope: Product Marketplace fulfilment and seller payout. This is a design document only; it does not create roles, tables, RPCs, migrations, payment integrations, or operational permissions.

## 1. Approved business requirement

NEXORA will support two fulfilment paths. Sellers/farmers may choose the suitable path for a product/order; using an Agent is not mandatory.

### A. NEXORA Agent-assisted path
- NEXORA will appoint one or more authorized Agents in each Upazila, according to operational demand and coverage.
- An Agent will collect the relevant goods from a participating farmer/business/seller.
- The Agent will take responsibility for receiving, counting/weighing as applicable, recording condition, packaging/labeling, and handing the packed goods to the NEXORA-designated Drop Point.
- NEXORA will provide the seller's approved payout amount to the Agent through a separately authorized payout process; the Agent is responsible for delivering that amount to the correct seller and obtaining verifiable acknowledgement.
- Agent activity must be linked to a specific seller, order/consignment, quantity, Drop Point and auditable handover records.

### B. Direct-seller path
- A farmer/business may sell directly without an Agent.
- The seller may prepare and hand over the goods through the separately defined direct dispatch/drop-off process.
- The Agent-assisted path must not be a mandatory condition for listing or selling.

## 2. Keep Agent distinct from existing roles

- The Agent is a NEXORA field-operations and seller-payout role, not automatically the existing Porter/Transporter role.
- A Porter/Transport Provider handles the onward transport leg only when assigned under the transport workflow.
- An Agent may perform collection and local delivery to a Drop Point; do not silently grant the Agent access to Buyer contact details, marketplace moderation, Admin functions, or unrelated delivery jobs.
- Whether an existing Porter can separately qualify as an Agent must be decided through explicit appointment and permissions; role equivalence must not be assumed.
- The seller remains the seller and retains ownership/authority over the listing and sale. The Agent is not the merchant of record merely because they hold goods or payout funds.

## 3. Proposed operational sequence

1. Seller chooses Agent-assisted fulfilment or direct fulfilment for the relevant order.
2. NEXORA creates an authorized collection/consignment instruction tied to the confirmed order.
3. Assigned Agent verifies seller/collection identity, product, agreed quantity, packaging requirements and visible condition.
4. Agent records actual collected quantity, exceptions, time, and custody transfer; both parties receive a receipt/confirmation.
5. Agent packages and labels goods according to the product-specific handling standard and delivers them to the designated Drop Point.
6. Drop Point staff verify package count, weight/quantity, seal/label and condition, then acknowledge custody. Any mismatch is recorded as an exception; it must not be silently overwritten.
7. The onward transporter receives the consignment from the Drop Point using a separate handover record and continues the delivery workflow.
8. Seller payout is released only against an approved, reconciled payout instruction. The Agent delivers it to the verified seller and records delivery acknowledgement; failed/partial delivery returns to an exception/reconciliation queue.
9. Buyer confirms actual receipt under the existing order-completion rule. A transporter scan or Agent handover alone must not mark the Buyer order completed.

## 4. Mandatory controls before implementation

### Goods custody and quantity
- Use unique order/consignment/package references and append-only custody events.
- Record expected quantity, collected quantity, packed quantity, Drop Point received quantity and onward dispatched quantity separately; never replace expected quantity with an unverified actual.
- Support partial collection, split packages, damaged/rejected goods, shortage/excess, failed pickup and return-to-seller as explicit exception states.
- Capture packaging/handling requirements and responsibility for packaging material/cost as a separate business rule; do not invent who pays.
- Restrict each Agent to assigned Upazila/territory and assigned collection jobs. Apply least-privilege access and protect Buyer address/contact information.

### Seller payout and money custody
- The Agent must not choose or edit the seller, amount, currency, order, or payout destination.
- NEXORA's Accounts/Finance process must create and authorize the payout instruction; Agent access is limited to assigned payout tasks.
- Record payout amount/currency, source transaction/reference, recipient verification, Agent receipt/acceptance, delivery status, seller acknowledgement, timestamp, and exception/refund/reconciliation status.
- Prevent duplicate payout, amount alteration, self-approval and payout to an unverified recipient. Use maker-checker approval and reconciliation.
- No payout method is assumed: cash, bank, mobile financial service, or another approved channel remains a separate decision.
- No Agent should be treated as a wallet, bank, payment gateway, escrow provider, or unrestricted custodian. Legal, licensing, tax, fraud, cash-limit, insurance and safeguarding review is required before enabling Agents to carry or disburse funds.
- Do not release seller funds to an Agent before the payment/settlement source and the exact condition for payout are defined and verified.

### Agent governance
- Agent registration/appointment, identity verification, agreement, territory, active/suspended status, training and performance review require an authorized NEXORA Admin process.
- Agent must not self-activate, self-assign jobs, edit protected records, approve own payout, or alter custody history.
- Every collection, package handover, Drop Point receipt, payout receipt and seller acknowledgement must be auditable.
- Define dispute escalation, loss/damage liability, insurance, service-level expectations, commission/fees and agent compensation before launch.

## 5. Relationship to existing NEXORA design

- This requirement extends the existing Delivery Network, Transport and Accounts/Finance workstreams; it is not already fully implemented.
- Existing staged Partner/Provider, Delivery Job, assignment and tracking foundations do not prove that seller-side collection, packaging, Drop Point custody, Agent payouts or reconciliation exist.
- The existing Porter role is not automatically the new Agent role.
- Direct seller fulfilment remains available alongside Agent-assisted fulfilment.
- Existing Buyer order completion must continue to require Buyer confirmation after actual receipt.
- This Product Marketplace flow must not be silently applied to Buyer Demand quotation orders until the user confirms whether both flows share the same Agent network.

## 6. Open decisions (do not guess)

1. **Agent payment delivery method:** cash, bank transfer, mobile financial service, or multiple approved methods?
2. **Payout trigger:** after Drop Point acceptance, after onward dispatch, after Buyer receipt, or another settlement milestone? This must align with refunds/disputes and payment-provider settlement.
3. **Agent compensation:** salary, per-pickup/per-package commission, percentage, or another model; who pays packaging and collection costs?
4. **Drop Point operation:** NEXORA-owned/leased, partner-operated, or approved third-party hubs; who verifies quantity and bears custody liability?
5. **Coverage:** one Agent per Upazila minimum, demand-based multiple Agents, overlap/backup, and temporary service areas.
6. **Buyer Demand scope:** does Agent-assisted collection also apply to Seller quotations against Buyer Demands, or only ordinary Product listings?
7. **Direct path handover:** does a direct seller deliver to a Drop Point, hand directly to the assigned transporter, or use another approved route?

Until these decisions and compliance controls are settled, keep this as an approved product requirement/design only. Do not create an Agent role, payout flow, financial ledger, migration, or live operation yet.
