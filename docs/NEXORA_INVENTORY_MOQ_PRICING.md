# NEXORA Product Inventory, MOQ & Quantity Pricing

This feature is staged on `nexora-development` only.

## Seller listing fields
- Wholesale listings can set a minimum order quantity (MOQ).
- Retail listings are constrained to MOQ 1.
- Sellers may optionally track stock. When disabled, stock is treated as untracked/unlimited; when enabled, a numeric stock quantity is required.
- Optional quantity-price tiers use JSON records shaped as `[{ "min_quantity": 100, "unit_price": 95 }]`. The highest qualifying tier is used as the order's unit-price snapshot.
- The Seller UI accepts one tier per line as `quantity=unit price`, for example `100=95` and `500=90`.

## Order inventory lifecycle
1. Product order creation locks the product row, validates Buyer category and MOQ, checks available stock, calculates the tier price, and reserves stock in the same transaction.
2. Seller accept / mark-ready does not change the reservation.
3. Buyer cancellation while pending or Seller rejection releases the reservation.
4. Buyer completion deducts stock and releases the reservation in the same transaction; verified-review eligibility is still created on completion.
5. Stock cannot be set below outstanding reservations. Enabling tracking on an existing product first calculates outstanding product orders and reserves their quantities.

## Security
- Browser clients cannot directly write reserved stock.
- Stock changes go through `set_product_inventory`, which verifies active Seller ownership and listing status.
- MOQ and price-tier values are validated by a database trigger.
- Order creation and state transitions remain guarded database RPCs.
- Existing Product RLS and the verified purchase review eligibility workflow are retained.

## Limitations / not yet production-tested
- No payment, escrow, refund, shipping booking, or inventory purchase/receipt workflow.
- No multi-warehouse stock, stock movement ledger, SKU/variant inventory, or automatic low-stock alerts.
- Tier prices are unit-price snapshots in the order; no currency conversion or tax/shipping calculations.
- UI stock editor currently uses a simple prompt-based control; a richer stock ledger interface can follow.
- This migration has not been applied to any hosted database. SQL execution and browser end-to-end tests remain pending.
