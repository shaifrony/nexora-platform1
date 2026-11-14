-- Adds per-listing Wholesale/Retail classification without introducing account categories.
-- Existing records are preserved as legacy_unclassified; no historic sale type is guessed.
BEGIN;

ALTER TABLE public.products
  ADD COLUMN market_category text;

UPDATE public.products
SET market_category = 'legacy_unclassified'
WHERE market_category IS NULL;

ALTER TABLE public.products
  ALTER COLUMN market_category SET DEFAULT 'legacy_unclassified',
  ALTER COLUMN market_category SET NOT NULL;

ALTER TABLE public.products
  ADD CONSTRAINT products_market_category_check
  CHECK (market_category IN ('wholesale', 'retail', 'legacy_unclassified'));

COMMENT ON COLUMN public.products.market_category IS
  'Per-listing sale channel. New listings must be wholesale or retail; legacy_unclassified preserves historical rows without guessing.';

CREATE INDEX products_market_category_status_created_idx
  ON public.products (market_category, listing_status, created_at DESC);

-- anon has column-scoped SELECT on products; authenticated has table SELECT.
GRANT SELECT (market_category) ON public.products TO anon, authenticated;
-- Existing products_owner_pending_update RLS policy restricts Seller updates to pending listings.
GRANT UPDATE (market_category) ON public.products TO authenticated;

CREATE OR REPLACE FUNCTION private.guard_product_market_category()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.market_category IS NULL
     OR NEW.market_category NOT IN ('wholesale', 'retail') THEN
    RAISE EXCEPTION 'New or reclassified listings must use wholesale or retail market_category'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.listing_status = 'approved'
     AND NEW.market_category IS DISTINCT FROM OLD.market_category THEN
    RAISE EXCEPTION 'Published listing market_category is immutable; create a separate listing'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.guard_product_market_category()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER products_guard_market_category
  BEFORE INSERT OR UPDATE OF market_category ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_product_market_category();

COMMIT;
