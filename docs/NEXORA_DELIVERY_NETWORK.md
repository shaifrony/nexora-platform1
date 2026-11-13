# NEXORA Delivery Network — Phase 1 Foundation

## Policy baseline
- NEXORA controls and coordinates every marketplace product delivery.
- Delivery sources: NEXORA-owned teams, approved courier/logistics partners, and approved independent providers.
- Admin / Delivery Coordinator makes assignments in the initial operating model.
- Buyer pays the approved delivery charge.
- Initial coverage: domestic retail and wholesale.
- Courier integration starts with manual booking/tracking; API integration is an adapter added later.
- Seller's own independent delivery arrangement is not a separate untracked option in this policy.

## Phase 1 scope
- `delivery_network_partners`: NEXORA-owned team records and courier/logistics company records.
- `delivery_network_staff`: Admin-managed roster for NEXORA-employed or contracted delivery workers.
- Existing `transport_providers` remains the registration model for independent people and transport businesses.
- Partner and staff reads require `logistics.view`; changes require active Admin membership, AAL2, and `logistics.assign`.
- Every privileged change is recorded in `admin_audit_logs`.
- No public role is added for delivery staff in this phase. This avoids changing Buyer/Seller/Admin role semantics. Staff login/field app is a later phase and must use a separate scoped identity design.

## Important limitations
- Courier API credentials are deliberately not stored in this phase. Store secrets only in a server-side secret store when an actual partner integration is approved.
- API tracking mode is metadata only until a provider-specific adapter is implemented.
- The Phase 1 migration depends on the existing staged Transport Provider and Admin permission foundation. The hosted database currently does not contain those staged tables, so do not apply this migration by itself to production.
- Delivery staff records are a managed roster only; they cannot yet sign in, accept assignments, or submit proof of delivery.
- Delivery jobs are not yet linked automatically to commerce orders and no buyer delivery charge checkout exists yet.

## Remaining phases
1. Provider, own team, and courier partner foundation.
2. Admin assignment and unified delivery jobs supporting staff, independent providers, and courier partners without forcing one vehicle.
3. Retail/wholesale delivery details, buyer-paid delivery charge snapshots, and status tracking.
4. Completion report, receiver OTP / alternative verification, partial delivery and dispute handling.
5. Provider costs, NEXORA fees, payment records and settlement.
6. Courier API adapters and automation.

## Security notes
- Partner/staff tables have RLS enabled and no browser write grants.
- Public RPC wrappers are invoker-rights; privileged internal functions are in the private schema and check auth.uid(), active Admin membership, AAL2 and logistics.assign.
- No service-role key or external API secret is exposed to the browser.
