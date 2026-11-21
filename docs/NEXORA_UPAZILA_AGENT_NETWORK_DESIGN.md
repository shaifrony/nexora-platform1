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


## 8. Agent-to-Agent inter-area procurement (local demand collection)

The Agent network also supports a two-sided marketplace and procurement/transport coordination model. An Agent may perform a Buyer-side representative function as well as the Seller-side representative function already described.

### Example: Sirajdikhan, Munshiganj

1. A NEXORA Agent operating in Sirajdikhan Upazila, Munshiganj visits or serves local markets and collects purchase requirements from local shops/businesses (for example, product, specification/quality, quantity, target price if supplied, required-by date, delivery location and contact/authorization).
2. The Agent records each requirement in NEXORA against the actual local business that requested the goods. The Agent is the authenticated actor submitting the demand on that business's behalf; the local business remains the represented Buyer unless a separately approved principal-reseller model is chosen.
3. The Agent searches NEXORA for products/offers published by authorized Agents or Sellers in other Upazilas/areas, compares the available product details, prices, quantities, origin and fulfilment terms, and selects a suitable offer.
4. The Sirajdikhan Agent submits a purchase order/quotation acceptance against the supplying Agent's advertised goods, identifying the actual represented Buyer and the exact offer, quantity, price, delivery destination and required date. The supplying Agent acts for the actual farmer/business or supplier whose goods are being offered.
5. The supplying Agent arranges source-side collection, quantity/quality verification, packaging and handover. The Sirajdikhan Agent coordinates or accepts the inter-area transport leg and local delivery/handover to the requesting business, using the approved NEXORA transport network and custody records.
6. Both sides can see the order status and relevant transaction records within their assigned scope. The represented Buyer and represented Seller identities, Agent actors, product source, agreed price and every custody transfer remain separately auditable.
7. Payment collection, settlement, NEXORA charge, Agent commissions, transport charges and the final amount payable to each represented business are calculated from the approved transaction and fee rules. Neither Agent may change the other party's amount or recipient or self-approve settlement.

### Agent capacities in this model

An authorized Agent may be assigned one or more transaction-specific capacities, subject to permissions and conflict controls:

- **Buyer-side procurement representative:** gathers demand from businesses in the Agent's assigned territory, publishes/submits the requirement with their authority, searches supply and places/coordinates purchase orders on their behalf.
- **Seller-side sales representative:** presents products supplied by farmers/businesses in the Agent's territory, manages listing/order tasks under their authorization and coordinates source-side fulfilment.
- **Collection/transport coordinator:** arranges pickup, records quantity and condition, packaging, inter-area transport, Drop Point handover and final local delivery/receipt as assigned.
- A single Agent may act for the Buyer in one transaction and another Agent may act for the Seller in that same transaction. The same Agent must not silently represent both sides of the same transaction or approve both sides' financial settlement. Any exceptional dual representation requires explicit informed consent, disclosure and a separately approved conflict-of-interest policy.

### Demand, ordering and traceability rules

- Each market requirement needs a unique Demand ID and must preserve the requesting business, Agent submitting it, authorization/consent, origin market/Upazila, destination, required-by date, product/specification, quantity/unit and status.
- Each resulting purchase order must link to the originating Demand ID and the exact advertised product/offer version. Price, quantity, seller, buyer, currency and agreed delivery terms must be snapshotted so later listing edits do not rewrite the order.
- The Buyer-side Agent may not create an order without recorded authority from the requesting business or change its requested product/quantity/price/destination without confirmation.
- Seller-side Agent may advertise only goods it is authorized to represent and must preserve the real farmer/business/source identity, available quantity and offer validity.
- Partial fulfilment, multiple supplying areas, split shipments, substitutions, shortages, damaged goods, cancellations and returns must be explicit and traceable; no silent substitutions.
- A market Demand is not automatically a paid order. Order acceptance, payment confirmation, collection, dispatch, delivery and Buyer receipt remain separate states.
- The requesting business should receive a comprehensible order/price/fee confirmation through an accessible channel, even when the Agent operates the app on its behalf.

### Commercial treatment and safeguards

- The transaction ledger must distinguish the represented Buyer, represented Seller, Buyer-side Agent, Seller-side Agent, transport Agent(s), actual product source, and any Drop Point/operator.
- NEXORA's platform charge and each Agent's procurement, sales, collection, packaging and transport commission must be separately itemized. The same Agent may earn only for approved services actually performed; avoid duplicate commission for overlapping duties.
- Define who pays each fee (Buyer, Seller or allocated between them), the commission base, tax/refund treatment, and when each amount becomes payable before enabling the workflow.
- Use role- and territory-scoped access: a Buyer-side Agent sees only the requirements/orders assigned to them; a Seller-side Agent sees only authorized listings/orders; transport Agents see only assigned logistics data. Do not expose private profiles or unrelated buyer/seller contacts.
- Apply maker-checker and conflict-of-interest controls to Agent onboarding, order adjustments, refunds, payout, commission and dispute resolution. Agents cannot approve their own disputed transaction or financial settlement.
- The platform must clearly disclose to both businesses when an Agent is representing them. The Agent's operational ability to act as Buyer/Seller in the interface does not by itself make the Agent the legal buyer, seller, goods owner or merchant of record.

## 9. Additional open decisions

11. **Agency vs principal trading:** when an Agent gathers a local business's demand and orders from another Agent, is the first Agent always acting as the local business's disclosed purchasing representative, or may the Agent buy in its own name and resell to that business? The default design is disclosed representation; principal/reseller activity requires separate approval and legal/tax review.
12. **Demand workflow:** should the Agent submit a private/targeted business requirement to selected supplying Agents, or publish a public Buyer Demand with the requesting business's identity/contact protected?
13. **Inter-area delivery:** does the supplying Agent deliver to a Drop Point, the receiving-area Agent, or a nominated transporter? Who is responsible for final-mile delivery to the local business?
14. **Agent commission split:** how should NEXORA charge and Buyer-side, Seller-side, collection and transport Agents be paid when several Agents contribute to one order? Define no-double-charge rules.
15. **Order authority and payment:** what evidence/confirmation is required from the local business before the Agent commits to a purchase order or payment obligation?

## 10. User-confirmed Agent-to-Agent distribution and illustrative revenue allocation (2026-11-14)

**This section supersedes conflicting earlier assumptions in this document** about the unregistered supplier being a NEXORA Seller account, the Agent only acting as a disclosed sales representative, and the inter-area/final-mile responsibility being undecided.

### 10.1 Seller and distribution responsibilities

- For the small-farmer/small-business assisted route, the farmer/business does not need a NEXORA login or a separate Unregistered Seller Record. The Agent is the direct Seller on NEXORA, lists the goods through the Agent account and is accountable to NEXORA for the listing, sale, order fulfilment and supplier-side settlement/records. The Agent must keep their own lawful source, purchase, consent and supplier-payment records; this does not create a NEXORA supplier profile.
- The Agent who sells the goods is the **Selling Agent**. That Agent pays the onward transport charge for the sold order.
- NEXORA takes responsibility for arranging and coordinating movement from the Selling Agent's handover point to the receiving Agent in the destination area, including any assigned carrier/transport provider.
- The destination **Local Distribution Agent** receives the goods from the inter-area transport leg, checks and records the handover, splits/consolidates local consignments when needed, and delivers the goods to the Buyer.
- The Local Distribution Agent is paid for the local distribution/delivery work actually completed. The inter-area carrier/transport provider is paid separately for the transport leg actually completed.
- The same person may perform more than one separately assigned task, but the ledger must not pay twice for the same work. A Selling Agent is not paid a delivery share merely because they sold the goods; they can receive a transport/delivery payment only if separately assigned and the work is independently evidenced.
- For the independent Direct Seller route, the registered Seller remains the seller; NEXORA may assign Agents for collection, inter-area transport and local distribution. Direct Seller's sale proceeds and Agent service payments remain separate ledger items. The detailed direct-Seller fee schedule may use its own Admin-configured rate.

### 10.2 Example Admin-configurable rates (illustrative defaults only)

These are sample starting values for planning and UI/data configuration. They are **not approved commercial prices, not a launch commitment, and not hard-coded constants**. Authorized Admin/Accounts governance must be able to change them through a versioned, audited fee schedule.

| Configuration key | Illustrative default | Calculation base |
|---|---:|---|
| Agent-Seller marketplace commission | 3% | Goods subtotal after item discount; excludes delivery and packaging charges |
| Direct-Seller marketplace commission | 3% | Goods subtotal after item discount; excludes delivery and packaging charges |
| Inter-area transport provider share | 50% | Collected onward transport charge |
| Local Distribution Agent share | 36% | Collected onward transport charge |
| NEXORA logistics coordination margin | 14% | Collected onward transport charge |

The three transport allocation percentages must total exactly 100%. If the destination Agent also performs a separately chargeable handling task, the fee schedule may add a distinct line item or reallocate the shares; never pay an unconfigured duplicate share.

### 10.3 Example calculation (BDT)

Assume one completed order:

| Item | BDT |
|---|---:|
| Selling Agent's acquisition cost from source | 8,000 |
| Goods selling price to Buyer | 10,000 |
| Selling Agent's gross trading margin | 2,000 |
| Selling Agent's packaging/handling expense | 200 |
| NEXORA marketplace commission (3% × 10,000) | 300 |
| Onward transport charge paid by Selling Agent | 500 |

Selling Agent illustrative net contribution before their other overhead/tax: **2,000 - 200 - 300 - 500 = BDT 1,000**. Any first-mile procurement cost from source to the Selling Agent's own collection point must also be included in the Agent's acquisition/operating cost if it is not already included in the BDT 8,000 acquisition figure.

Transport charge allocation:

| Recipient | Rate | BDT |
|---|---:|---:|
| Inter-area carrier/transport provider | 50% | 250 |
| Destination Local Distribution Agent | 36% | 180 |
| NEXORA logistics coordination margin | 14% | 70 |
| **Total** | **100%** | **500** |

NEXORA illustrative gross revenue for this order is **BDT 370** (BDT 300 marketplace commission + BDT 70 logistics margin). This is gross revenue, not net profit; payment-provider fees, operations, support, technology, taxes, insurance/claims and other business costs must be deducted to calculate net profit. The transport charge is not wholly NEXORA revenue.

### 10.4 Data/configuration contract (example only; not a live fee engine)

```json
{
  "currency": "BDT",
  "status": "illustrative_default_not_for_live_settlement",
  "marketplace_commission": {
    "agent_seller_percent": 3,
    "direct_seller_percent": 3,
    "basis": "goods_subtotal_after_item_discount_excluding_delivery_and_packaging"
  },
  "onward_transport_allocation_percent": {
    "inter_area_transport_provider": 50,
    "local_distribution_agent": 36,
    "nexora_logistics_coordination_margin": 14,
    "must_total": 100
  },
  "settlement": {
    "selling_agent_pays_transport_charge": true,
    "local_agent_paid_only_after_verified_delivery": true,
    "transport_provider_paid_after_verified_transport_leg": true,
    "snapshot_rate_version_on_order_acceptance": true,
    "no_retroactive_rate_changes": true
  }
}
```

### 10.5 Required Admin controls and ledger data

- Admin/Accounts can configure separate marketplace commission rates by seller operating model and transport allocation shares. The UI must show percentage, calculation base, currency, effective-from timestamp, version, status and explanatory notes.
- Validate commission percentages are within 0–100; transport shares total exactly 100; reject negative values, invalid precision, overlapping active effective periods and incomplete configurations.
- Sensitive rate changes require authorized permission and maker-checker approval. Every change records actor, approver, before/after values, reason and timestamp.
- Each accepted order snapshots the exact rate-schedule version and all calculated BDT amounts. Later Admin edits apply only to new eligible orders; never recalculate an accepted order from the latest rate.
- Keep separate ledger lines for goods subtotal, marketplace commission, Seller net proceeds, Selling Agent-paid transport charge, carrier share, Local Distribution Agent share, NEXORA logistics margin, packaging/handling, discounts, refunds, tax (if applicable), claims and adjustments.
- Carrier and Local Distribution Agent payment eligibility depends on their own verified custody/delivery events. A delivery failure, partial delivery, return or dispute must pause or proportionally adjust affected service payments under an approved rule; no automatic full payout on assignment alone.
- No Agent may approve their own fee, payout, adjustment or dispute. Accounts/Finance and authorized Admins use maker-checker controls.
- The rates above are documentation/sample data only. No schema, migration, RPC, payment integration, wallet, payout, production pricing or live settlement has been implemented. Existing migration/foundation reconciliation and isolated replay gates still apply. Legal, tax, consumer-protection and payment-provider review is required before live collection/settlement.

## 10. User-confirmed policy updates — supersede conflicting earlier draft text

The following decisions were confirmed after the earlier sections were drafted. Where any earlier paragraph in this document conflicts with this section, this section takes precedence and the earlier paragraph must be treated as superseded.

### Seller Agent is the direct NEXORA Seller

- A Seller Agent who purchases/obtains goods from a farmer or small business for resale is the direct Seller on NEXORA, using the Agent's own approved account and business identity.
- NEXORA must not create a separate Unregistered Seller Record, Seller login, or Seller profile for the unregistered farmer/small supplier in this model.
- The Agent is responsible for maintaining their own supplier, source, procurement, ownership, purchase-cost and stock records outside the NEXORA Seller identity model, subject to applicable law and traceability requirements.
- The Agent controls their own resale listing, sale price, negotiation and Seller-side order obligations. This is distinct from a Direct Seller who operates their own Seller account and uses Agents only for physical collection/handling/transport services.
- The Agent's legal ownership, invoice/tax obligations and consumer-facing disclosure must be documented and reviewed before launch; the platform must not assume a regulated payment or escrow role.

### Wholesale and Retail listings

- Wholesale and Retail are separate Listing types. A Seller/Agent may create separate listings for the same underlying goods where both sale channels are offered.
- Each listing has its own sale type, price/terms and permanent listing identity. A buyer can browse both types; the type is not a Buyer account category or a visibility restriction.

### Buyer Agent Fee

- When a Buyer uses a Buyer Agent for the transaction, the Buyer Agent Fee is mandatory and must be disclosed before order confirmation.
- No Buyer Agent Fee is charged where the Buyer completes the transaction without using a Buyer Agent.
- The fee rate and calculation base remain configurable and are not fixed by this policy document.

### Transport and final-mile responsibility

- The Seller Agent bears/pays the applicable transport charge for the onward movement from the Seller Agent's collection point under the approved commercial terms.
- NEXORA is responsible for arranging the onward movement from the selling Agent's location and assigning the receiving-area/local distribution Agent.
- A separate Local Distribution Agent receives the goods and completes local distribution/delivery to the Buyer, unless a future explicitly approved exception applies.
- Carrier, Drop Point and Local Distribution Agent custody events, quantities, condition and handovers must be recorded separately. The same work must not be paid twice.

### Buyer receipt and Buyer Demand

- The normal settlement eligibility trigger is `buyer_received`: the Buyer must confirm actual receipt before normal settlement can complete. Any legal/provider exception must be separately approved and auditable.
- Orders created from Buyer Demand quotations use the same Agent, transport, custody, Buyer receipt and settlement workflow as Product Marketplace orders.
- Buyer Demand identity/contact privacy remains unchanged; public Demand content must not expose private Buyer identity or contact data.

### Configurable financial rates

- No commission, Agent fee, transport share, logistics margin, minimum, maximum or other financial rate may be permanently hardcoded.
- All rates and calculation bases must be managed through versioned, effective-dated, permission-controlled Financial Configuration. Every order must preserve the configuration version and calculated amount snapshot used at confirmation.
- Maker-checker approval, immutable audit history, exact allocation reconciliation and non-retroactive changes are mandatory.
- Previously shown sample rates/splits are illustrative only and are not approved permanent or launch rates.

These updates resolve the earlier draft's open questions about the Seller Agent's own-resale model, Buyer Demand workflow parity, Buyer receipt settlement trigger, separate Wholesale/Retail listings and configurable rates. Other financial details (including exact rates, calculation bases, payout rails, timeout handling, partial-delivery settlement and refund/dispute treatment) remain subject to explicit user decisions and legal/payment-provider review.
