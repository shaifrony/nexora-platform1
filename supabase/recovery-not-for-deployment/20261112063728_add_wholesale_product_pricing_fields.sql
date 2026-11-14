-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from current Live catalog (columns/defaults/checks).
-- Do not move into supabase/migrations or execute without isolated testing and approval.
BEGIN;
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS price_unit text NOT NULL DEFAULT 'Piece',
  ADD COLUMN IF NOT EXISTS minimum_order_quantity numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS price_negotiable boolean NOT NULL DEFAULT true;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.products'::regclass AND conname='products_minimum_order_quantity_check') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_minimum_order_quantity_check CHECK (minimum_order_quantity > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.products'::regclass AND conname='products_price_unit_check') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_price_unit_check CHECK (length(trim(price_unit)) BETWEEN 1 AND 24);
  END IF;
END $$;
COMMIT;
