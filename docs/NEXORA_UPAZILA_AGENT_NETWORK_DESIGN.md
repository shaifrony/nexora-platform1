# NEXORA Upazila Agent Network, Assisted Selling & Direct-Seller Fulfilment

Status: **User-approved business requirement; commission, legal, settlement and operational controls require further decisions.**
Date: 2026-11-14
Scope: Upazila Agent network, assisted selling, product handling/transport, sales proceeds and commission allocation. This is a design document only; it does not create roles, tables, RPCs, migrations, payment integrations, or operational permissions.

## 1. Approved business model

NEXORA will support two seller operating models. The system must make the distinction clear to Buyers, Sellers, Agents and Accounts staff.

### A. Agent-represented selling for low-literacy farmers/businesses

- NEXORA will appoint one or more authorized Agents in every Upazila, according to demand and service coverage.
- This model is intended for farmers and businesses who cannot independently operate the NEXORA app or manage the online selling process.
- The Agent acts on the farmer's/business's behalf for the NEXORA selling workflow: product onboarding/listing assistance, presenting the goods for sale through the Agent's designated NEXORA sales-centre workflow, receiving and coordinating Buyer orders, arranging collection, recording quantity/condition, packaging/labeling, and handing goods to the designated Drop Point or coordinating the transport network.
- The underlying farmer/business and the actual source/owner of the goods must remain recorded and traceable. Agent representation does not silently transfer ownership of the goods or make the Agent the legal merchant/seller of record; the contract and legal treatment of agency/merchant-of-record status must be expressly settled before launch.
- After the Buyer pays through an approved NEXORA payment/settlement route, NEXORA's Accounts process calculates the approved deductions and seller net proceeds. NEXORA may release the authorized seller amount to the assigned Agent for delivery to the verified farmer/business, with receipt/acknowledgement and reconciliation. The Agent cannot set or change the payable recipient, amount, currency or order.
- The Agent receives an explicitly defined commission/service share for the work performed. The exact rate, basis, payer, timing and treatment of packaging/transport costs remain open decisions.

### B. Direct selling by capable/educated farmers and businesses

- A farmer/business able to use NEXORA independently may create/manage its own Seller account, Business Profile, product listings, prices, negotiation and order workflow, subject to the normal platform approval and security rules.
- The Seller remains directly responsible for its own listing and sales decisions; the Agent does not replace the Seller in those functions.
- **Transport/collection for this model is still handled through the NEXORA Agent network.** The Seller requests/coordinates the assigned Agent; the Agent collects the sold goods, records quantity and condition, packages/labels as required, and delivers them to the designated Drop Point or coordinates the onward transport network.
- The Agent receives the approved transport/handling commission or service share, and NEXORA receives its platform charge from the sale proceeds under the agreed fee schedule. The Seller receives the net amount after disclosed and authorized deductions.
- Direct selling does not mean direct, untracked handover to an unassigned transporter. Agent collection and custody records are required unless a future explicit exception is approved.

## 2. Commission and sale-proceeds allocation

- NEXORA will deduct a defined platform charge from each completed/settled sale, calculated on a clearly defined sale-value basis.
- The Agent will receive a defined commission/service share for Agent-represented selling and/or the mandatory collection, packaging, Drop Point and transport-coordination work, according to the applicable seller model and service actually completed.
- The payout statement must separately show gross goods sale value, Buyer-paid delivery/other approved charges, NEXORA platform charge, Agent commission/service charge, approved packaging/transport deductions, refunds/adjustments, and final seller net proceeds.
- Rates must be visible to the Seller (or explained and acknowledged by the Agent on the Seller's behalf) before the order is accepted. No hidden deductions or post-sale rate changes.
- Do not assume that the same Agent commission applies to both models: assisted-selling and transport-only service may have different rates and conditions.
- The exact percentage/rate, whether calculated on gross goods value or another base, treatment of discounts/tax/refunds/partial fulfilment, and whether Buyer delivery charges are separate from commission remain undecided.
- Commission becomes payable only after a defined settlement milestone and reconciliation; an Agent cannot approve their own commission or payout.

## 3. Operational sequence

1. Seller is onboarded as either Agent-represented (assisted selling) or independent/direct Seller. This is an operating mode, not a public role change or permission to bypass Seller/business approval.
2. For Agent-represented selling, the Agent records the real farmer/business as goods owner/source and performs the agreed listing/sales tasks with the Seller's informed consent. For direct selling, the Seller controls the listing and order decisions.
3. After an order is validly accepted and payment is confirmed through an approved payment route, NEXORA creates a collection/consignment instruction.
4. Assigned Agent verifies seller/source identity, product, agreed quantity, packaging requirements and visible condition.
5. Agent records actual collected quantity, exceptions, time and custody transfer; seller and Agent receive a receipt/confirmation.
6. Agent packages and labels the goods and delivers them to the designated Drop Point, or coordinates the onward transport handover under a separately recorded event.
7. Drop Point staff verify package count, weight/quantity, seal/label and condition, then acknowledge custody. Any mismatch becomes an exception; it must not be silently overwritten.
8. Accounts calculates the sale proceeds and applicable platform/Agent charges using the versioned fee schedule and confirmed settlement records.
9. NEXORA pays the verified Seller net amount through the approved payout route. Where the Agent physically delivers the Seller's payout, the Agent accepts a specific authorized payout instruction and obtains Seller acknowledgement. The Agent commission is separately recorded and reconciled.
10. Buyer confirms actual receipt under the order-completion rule. Agent or transporter handover alone must not mark the Buyer order completed.

## 4. Role, identity and custody boundaries

- The Agent is a separately appointed NEXORA field Agent/authorized Seller representative; it is not automatically the existing Porter/Transport Provider or an Admin.
- For Agent-represented selling, the platform must retain the actual farmer/business identity, beneficial goods owner/source, Agent identity and representation/consent record. Buyer-facing disclosure must be clear about who owns/supplies the goods and that an authorized Agent is handling the sale.
- For direct selling, the farmer/business remains the Seller and retains control of listing, price, negotiation and order decisions; the Agent handles the required physical logistics only.
- The Agent must not gain unrestricted access to Buyer private profile/contact data, private conversations, Admin functions, other Agents' territories, or unrelated delivery jobs.
- Whether an Agent can be a legal merchant of record, collect payment directly, issue receipts/invoices in their own name, or act as a regulated payment intermediary requires legal/tax/payment-provider review. Do not infer these rights from the operational requirement.
- Agent and Seller must not be represented as the same account/person in audit records. Record the authenticated Agent actor separately from the Seller they are authorized to represent.

## 5. Mandatory controls before implementation

### Product custody and quantity
- Use unique order/consignment/package references and append-only custody events.
- Record expected quantity, collected quantity, packed quantity, Drop Point received quantity and onward dispatched quantity separately.
- Support partial collection, split packages, damaged/rejected goods, shortage/excess, failed pickup, returns and disputes as explicit exception states.
- Record packaging materials, packaging cost, weight/measurement method, photographs where appropriate, and who bears each cost.
- Restrict Agents to approved Upazila/territory and assigned jobs; apply least-privilege access.

### Payment, payout and commission
- Do not accept or mark an order paid based only on an Agent's statement. Payment confirmation must come from the approved provider/server-side settlement record.
- The Agent must not choose/edit Seller, recipient, amount, currency, order, commission rate or payout destination.
- Accounts/Finance owns the fee schedule, payout instruction, reconciliation, refund/adjustment and maker-checker approval.
- Prevent duplicate payouts, commission manipulation, self-approval, recipient substitution and payout to an unverified Seller.
- Keep gross sale, platform fee, Agent commission, other deductions, tax (if applicable), refund/adjustment and net payout as separate ledger entries.
- Use an immutable, effective-dated fee schedule; preserve the rate used on each order even if rates change later.
- Payout method may include approved bank/mobile financial service/cash channels only after legal/provider review. No Agent is assumed to be a wallet, bank, payment gateway or escrow provider.
- Legal, licensing, tax, consumer-protection, invoicing, cash-limit, fraud, insurance and safeguarding review is mandatory before money handling or launch.

### Agent governance
- Agent identity verification, appointment agreement, territory, service scope, training, active/suspended status, performance and complaints require authorized Admin governance.
- Agents cannot self-activate, self-assign, approve own payout/commission, edit protected records or alter custody history.
- Record Seller consent/authorization for Agent-represented sales and provide an accessible way for the Seller to understand the product, price, deductions and payout.
- Every collection, package handover, Drop Point receipt, payout receipt, Seller acknowledgement and commission settlement must be auditable.

## 6. Relationship to existing NEXORA design

- This requirement extends Delivery Network, Transport, Marketplace and Accounts/Finance; it is not already implemented.
- Existing Porter/Transport Provider, Delivery Job, assignment and tracking foundations do not establish Upazila Agent appointment, Agent-represented selling, mandatory Agent collection, packaging, Drop Point custody, commission calculation or Seller payout delivery.
- The existing Porter role is not automatically the new Agent role. An individual may hold more than one separately approved capacity only if the permission and audit boundaries are explicitly designed.
- Direct Sellers may manage their own sales, but physical collection/transport remains Agent-mediated under this approved model.
- Buyer order completion still requires Buyer confirmation after actual receipt.
- This scope applies to the Product Marketplace unless the user separately confirms that Buyer Demand quotation orders should use the same Agent selling/fulfilment model.

## 7. Open decisions (do not guess)

1. **Commission rates:** what percentage goes to NEXORA and what percentage goes to the Agent for (a) Agent-represented selling and (b) direct Seller with Agent transport? Should the two models have different rates?
2. **Commission base:** gross goods value, amount after discount, or another basis? How are VAT/tax, refunds, partial quantities and Buyer delivery charges treated?
3. **Payout trigger:** after Drop Point acceptance, onward dispatch, Buyer receipt, or provider settlement plus another condition?
4. **Payout method:** bank, mobile financial service, cash or a combination? Is Agent physical cash delivery intended, or can NEXORA pay the Seller directly?
5. **Agent role and legal status:** authorized sales representative/agent, commission agent, or merchant of record? What documents and Seller consent are required?
6. **Agent compensation and costs:** are packaging materials, pickup and local delivery paid by Seller, Agent, NEXORA or deducted from sale proceeds?
7. **Drop Point operation:** NEXORA-owned/leased, partner-operated or approved third-party hub; who verifies goods and bears custody liability?
8. **Coverage:** one Agent minimum per Upazila, demand-based multiple Agents, overlap/backup and temporary service areas.
9. **Buyer Demand scope:** does this same Agent model apply to Seller quotations against Buyer Demands, or only ordinary Product listings?
10. **Direct Seller collection:** confirm that every direct Seller's sale must be collected by an Agent, with no Seller-to-transporter direct handover exception.

Until these decisions and legal/compliance controls are settled, keep this as an approved business requirement/design only. Do not create an Agent role, permissions, fee engine, financial ledger, payout flow, migration, or live operation yet.
