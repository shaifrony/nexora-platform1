-- RECOVERY-ONLY CANDIDATE. Not an active migration and must not be applied to hosted databases.
-- Tested against a disposable PostgreSQL 18 fixture; full Supabase/RLS replay is still required.
BEGIN;

ALTER TABLE public.products ADD COLUMN market_category text;
UPDATE public.products SET market_category = 'legacy_unclassified' WHERE market_category IS NULL;
ALTER TABLE public.products ALTER COLUMN market_category SET DEFAULT 'legacy_unclassified';
ALTER TABLE public.products ALTER COLUMN market_category SET NOT NULL;
ALTER TABLE public.products ADD CONSTRAINT products_market_category_check
  CHECK (market_category IN ('wholesale','retail','legacy_unclassified'));
COMMENT ON COLUMN public.products.market_category IS
  'Per-listing sale channel. New listings must be wholesale or retail; legacy_unclassified preserves historical rows without guessing.';
CREATE INDEX products_market_category_status_created_idx
  ON public.products (market_category, listing_status, created_at DESC);
GRANT SELECT (market_category) ON public.products TO anon, authenticated;
GRANT UPDATE (market_category) ON public.products TO authenticated;

CREATE OR REPLACE FUNCTION private.guard_product_market_category()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.market_category IS NULL OR NEW.market_category NOT IN ('wholesale','retail') THEN
    RAISE EXCEPTION 'New or reclassified listings must use wholesale or retail market_category'
      USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.listing_status = 'approved'
     AND NEW.market_category IS DISTINCT FROM OLD.market_category THEN
    RAISE EXCEPTION 'Published listing market_category is immutable; create a separate listing'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.guard_product_market_category() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER products_guard_market_category
  BEFORE INSERT OR UPDATE OF market_category ON public.products
  FOR EACH ROW EXECUTE FUNCTION private.guard_product_market_category();

ALTER TABLE public.commerce_orders ADD COLUMN market_category_snapshot text;
UPDATE public.commerce_orders o
SET market_category_snapshot = COALESCE(p.market_category, 'legacy_unclassified')
FROM public.products p
WHERE o.listing_type = 'product' AND o.listing_id = p.id;
UPDATE public.commerce_orders
SET market_category_snapshot = 'legacy_unclassified'
WHERE listing_type = 'product' AND market_category_snapshot IS NULL;
ALTER TABLE public.commerce_orders ADD CONSTRAINT commerce_orders_market_category_snapshot_check
  CHECK ((listing_type = 'product' AND market_category_snapshot IN ('wholesale','retail','legacy_unclassified'))
      OR (listing_type = 'service' AND market_category_snapshot IS NULL));
GRANT SELECT (market_category_snapshot) ON public.commerce_orders TO authenticated;

CREATE OR REPLACE FUNCTION private.snapshot_commerce_order_market_category()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_market_category text;
BEGIN
  IF NEW.listing_type = 'product' THEN
    SELECT p.market_category INTO v_market_category
    FROM public.products AS p
    WHERE p.id = NEW.listing_id AND p.listing_status = 'approved';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Approved product listing is required for a product order'
        USING ERRCODE = '23503';
    END IF;
    NEW.market_category_snapshot := v_market_category;
  ELSE
    NEW.market_category_snapshot := NULL;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.snapshot_commerce_order_market_category() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER commerce_orders_snapshot_market_category
  BEFORE INSERT ON public.commerce_orders
  FOR EACH ROW EXECUTE FUNCTION private.snapshot_commerce_order_market_category();

CREATE OR REPLACE FUNCTION private.prevent_commerce_order_market_category_snapshot_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.market_category_snapshot IS DISTINCT FROM OLD.market_category_snapshot THEN
    RAISE EXCEPTION 'Order market_category_snapshot is immutable'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.prevent_commerce_order_market_category_snapshot_change() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER commerce_orders_market_category_snapshot_immutable
  BEFORE UPDATE OF market_category_snapshot ON public.commerce_orders
  FOR EACH ROW EXECUTE FUNCTION private.prevent_commerce_order_market_category_snapshot_change();

COMMIT;
