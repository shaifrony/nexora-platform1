-- NEXORA LOCAL BUYER DEMAND / SELLER INBOX / QUOTATION FIXTURE
-- Local-only companion to fixture 21 (Marketplace visibility).
-- This is a reconstructed test fixture, NOT a recovered migration and NOT deployable.
-- SAFETY: refuses every database except nexora_test and refuses existing Demand objects.
-- Does not connect to Supabase, apply migrations, or modify hosted data.

\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %',current_database();
  END IF;
  IF to_regclass('public.profiles') IS NULL
     OR to_regprocedure('auth.uid()') IS NULL
     OR to_regprocedure('public.is_nexora_admin()') IS NULL
     OR to_regclass('public.products') IS NULL
     OR to_regclass('public.public_businesses') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: run foundation fixture 06 and Marketplace visibility fixture 21 first';
  END IF;
  IF to_regclass('public.buyer_demands') IS NOT NULL
     OR to_regclass('public.seller_offers') IS NOT NULL
     OR to_regclass('public.buyer_demand_inbox') IS NOT NULL
     OR to_regclass('public.public_buyer_demands') IS NOT NULL
     OR to_regprocedure('private.route_new_buyer_demand_to_sellers()') IS NOT NULL
     OR to_regprocedure('private.route_new_approved_product_to_open_demands()') IS NOT NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: Demand objects already exist; inspect instead of overwriting';
  END IF;
END
$guard$;

BEGIN;

-- Product subcategory is product taxonomy. market_category remains per-product
-- descriptive sale type and is deliberately not used by Demand routing.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS subcategory text;
ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_subcategory_length_check,
  ADD CONSTRAINT products_subcategory_length_check
    CHECK (subcategory IS NULL OR length(btrim(subcategory)) BETWEEN 2 AND 120);

CREATE TABLE public.buyer_demands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  demand_code text NOT NULL UNIQUE DEFAULT
    ('NXD-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  product_name text NOT NULL CHECK (length(btrim(product_name)) BETWEEN 2 AND 180),
  category text NOT NULL,
  subcategory text,
  description text NOT NULL,
  specifications_quality text,
  required_quantity text NOT NULL,
  budget numeric(18,2) CHECK (budget IS NULL OR budget>=0),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  destination_country text NOT NULL,
  destination_city text NOT NULL,
  required_date date NOT NULL,
  demand_status text NOT NULL DEFAULT 'open'
    CHECK (demand_status IN ('open','closed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT buyer_demands_required_date_not_past CHECK (required_date>=current_date),
  CONSTRAINT buyer_demands_subcategory_length_check
    CHECK (subcategory IS NULL OR length(btrim(subcategory)) BETWEEN 2 AND 120)
);

CREATE TABLE public.seller_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  demand_id uuid NOT NULL REFERENCES public.buyer_demands(id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  offer_price numeric(18,2) NOT NULL CHECK (offer_price>=0),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  available_quantity text NOT NULL,
  message text,
  offer_status text NOT NULL DEFAULT 'pending'
    CHECK (offer_status IN ('pending','accepted','rejected','withdrawn')),
  product_brand text,
  product_model text,
  product_condition text CHECK (product_condition IS NULL OR product_condition IN ('new','refurbished','used','any')),
  price_basis text NOT NULL DEFAULT 'per_unit' CHECK (price_basis IN ('per_unit','total')),
  estimated_delivery_date date,
  warranty text,
  offer_valid_until date,
  delivery_charge numeric(18,2) CHECK (delivery_charge IS NULL OR delivery_charge>=0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seller_offers_one_per_seller_demand UNIQUE(demand_id,seller_id),
  CONSTRAINT seller_offers_brand_length_check CHECK (product_brand IS NULL OR length(product_brand)<=100),
  CONSTRAINT seller_offers_model_length_check CHECK (product_model IS NULL OR length(product_model)<=120),
  CONSTRAINT seller_offers_warranty_length_check CHECK (warranty IS NULL OR length(warranty)<=300)
);

CREATE TABLE public.buyer_demand_inbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  demand_id uuid NOT NULL REFERENCES public.buyer_demands(id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  match_reason text NOT NULL DEFAULT 'approved_product_category',
  created_at timestamptz NOT NULL DEFAULT now(),
  viewed_at timestamptz,
  CONSTRAINT buyer_demand_inbox_unique UNIQUE(demand_id,seller_id)
);

CREATE INDEX buyer_demands_buyer_status_idx
  ON public.buyer_demands(buyer_id,demand_status,created_at DESC);
CREATE INDEX buyer_demands_category_subcategory_status_idx
  ON public.buyer_demands(category,subcategory,demand_status,created_at DESC);
CREATE INDEX seller_offers_seller_created_idx
  ON public.seller_offers(seller_id,created_at DESC);
CREATE INDEX seller_offers_demand_created_idx
  ON public.seller_offers(demand_id,created_at);
CREATE INDEX buyer_demand_inbox_seller_created_idx
  ON public.buyer_demand_inbox(seller_id,created_at DESC);

ALTER TABLE public.buyer_demands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buyer_demand_inbox ENABLE ROW LEVEL SECURITY;

-- Demand identity is never granted to anon or authenticated clients.
REVOKE ALL ON public.buyer_demands FROM PUBLIC,anon,authenticated;
GRANT SELECT (
  id,demand_code,product_name,category,subcategory,description,specifications_quality,
  required_quantity,budget,currency,destination_country,destination_city,
  required_date,demand_status,created_at
) ON public.buyer_demands TO anon,authenticated;
GRANT INSERT (
  buyer_id,product_name,category,subcategory,description,specifications_quality,
  required_quantity,budget,currency,destination_country,destination_city,required_date
) ON public.buyer_demands TO authenticated;
GRANT UPDATE (
  product_name,category,subcategory,description,specifications_quality,
  required_quantity,budget,currency,destination_country,destination_city,required_date,
  demand_status,updated_at
) ON public.buyer_demands TO authenticated;

REVOKE ALL ON public.seller_offers FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.seller_offers TO authenticated;
GRANT INSERT (
  demand_id,seller_id,offer_price,currency,available_quantity,message,
  product_brand,product_model,product_condition,price_basis,
  estimated_delivery_date,warranty,offer_valid_until,delivery_charge
) ON public.seller_offers TO authenticated;

REVOKE ALL ON public.buyer_demand_inbox FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.buyer_demand_inbox TO authenticated;

-- Public visitors may see open Demands only through the safe view.
CREATE POLICY demands_public_open_read
ON public.buyer_demands FOR SELECT TO anon
USING (demand_status='open');

CREATE POLICY demands_owner_inbox_admin_read
ON public.buyer_demands FOR SELECT TO authenticated
USING (
  buyer_id=(SELECT auth.uid())
  OR public.is_nexora_admin()
  OR (
    demand_status='open'
    AND EXISTS(SELECT 1 FROM public.profiles p
      WHERE p.id=(SELECT auth.uid()) AND p.role='seller' AND p.account_status='active')
    AND EXISTS(SELECT 1 FROM public.public_businesses b WHERE b.seller_id=(SELECT auth.uid()))
    AND EXISTS(SELECT 1 FROM public.buyer_demand_inbox i
      WHERE i.demand_id=buyer_demands.id AND i.seller_id=(SELECT auth.uid()))
  )
);

CREATE POLICY demands_active_buyer_insert
ON public.buyer_demands FOR INSERT TO authenticated
WITH CHECK (
  buyer_id=(SELECT auth.uid())
  AND demand_status='open'
  AND EXISTS(SELECT 1 FROM public.profiles p
    WHERE p.id=(SELECT auth.uid()) AND p.role='buyer' AND p.account_status='active')
);

CREATE POLICY demands_owner_open_update
ON public.buyer_demands FOR UPDATE TO authenticated
USING (buyer_id=(SELECT auth.uid()) AND demand_status='open')
WITH CHECK (buyer_id=(SELECT auth.uid()));

CREATE POLICY demands_admin_all
ON public.buyer_demands FOR ALL TO authenticated
USING (public.is_nexora_admin())
WITH CHECK (public.is_nexora_admin());

CREATE POLICY buyer_demand_inbox_seller_read
ON public.buyer_demand_inbox FOR SELECT TO authenticated
USING (
  public.is_nexora_admin()
  OR (
    seller_id=(SELECT auth.uid())
    AND EXISTS(SELECT 1 FROM public.profiles p
      WHERE p.id=(SELECT auth.uid()) AND p.role='seller' AND p.account_status='active')
    AND EXISTS(SELECT 1 FROM public.public_businesses b WHERE b.seller_id=(SELECT auth.uid()))
  )
);

CREATE POLICY offers_buyer_seller_admin_read
ON public.seller_offers FOR SELECT TO authenticated
USING (
  seller_id=(SELECT auth.uid())
  OR public.is_nexora_admin()
  OR EXISTS(SELECT 1 FROM public.buyer_demands d
    WHERE d.id=seller_offers.demand_id AND d.buyer_id=(SELECT auth.uid()))
);

CREATE POLICY offers_approved_seller_inbox_insert
ON public.seller_offers FOR INSERT TO authenticated
WITH CHECK (
  seller_id=(SELECT auth.uid())
  AND offer_status='pending'
  AND EXISTS(SELECT 1 FROM public.profiles p
    WHERE p.id=(SELECT auth.uid()) AND p.role='seller' AND p.account_status='active')
  AND EXISTS(SELECT 1 FROM public.public_businesses b WHERE b.seller_id=(SELECT auth.uid()))
  AND EXISTS(SELECT 1 FROM public.buyer_demand_inbox i
    JOIN public.buyer_demands d ON d.id=i.demand_id
    WHERE i.demand_id=seller_offers.demand_id
      AND i.seller_id=(SELECT auth.uid()) AND d.demand_status='open')
);

-- Trigger-only Demand routing. No client role can execute these functions directly.
CREATE OR REPLACE FUNCTION private.route_new_buyer_demand_to_sellers()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF NEW.demand_status<>'open' THEN RETURN NEW; END IF;
  INSERT INTO public.buyer_demand_inbox(demand_id,seller_id,match_reason)
  SELECT DISTINCT NEW.id,pr.seller_id,'approved_product_category'
  FROM public.products pr
  JOIN public.profiles sp ON sp.id=pr.seller_id
  JOIN public.public_businesses pb
    ON pb.business_id=pr.business_id AND pb.seller_id=pr.seller_id
  WHERE pr.listing_status='approved'
    AND NEW.category=pr.category
    AND (NULLIF(BTRIM(NEW.subcategory),'') IS NULL
      OR lower(btrim(coalesce(pr.subcategory,'')))=lower(btrim(NEW.subcategory)))
    AND sp.role='seller' AND sp.account_status='active'
  ON CONFLICT(demand_id,seller_id) DO NOTHING;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.route_new_buyer_demand_to_sellers() FROM PUBLIC,anon,authenticated;

CREATE TRIGGER buyer_demand_route_to_sellers
AFTER INSERT ON public.buyer_demands
FOR EACH ROW EXECUTE FUNCTION private.route_new_buyer_demand_to_sellers();

CREATE OR REPLACE FUNCTION private.route_new_approved_product_to_open_demands()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF NEW.listing_status='approved' THEN
    INSERT INTO public.buyer_demand_inbox(demand_id,seller_id,match_reason)
    SELECT DISTINCT d.id,NEW.seller_id,'approved_product_category'
    FROM public.buyer_demands d
    JOIN public.profiles sp ON sp.id=NEW.seller_id
      AND sp.role='seller' AND sp.account_status='active'
    JOIN public.public_businesses pb
      ON pb.business_id=NEW.business_id AND pb.seller_id=NEW.seller_id
    WHERE d.demand_status='open'
      AND d.category=NEW.category
      AND (NULLIF(BTRIM(d.subcategory),'') IS NULL
        OR lower(btrim(coalesce(NEW.subcategory,'')))=lower(btrim(d.subcategory)))
    ON CONFLICT(demand_id,seller_id) DO NOTHING;
  END IF;

  DELETE FROM public.buyer_demand_inbox i
  USING public.buyer_demands d
  WHERE i.demand_id=d.id AND i.seller_id=NEW.seller_id
    AND d.demand_status='open'
    AND NOT EXISTS(SELECT 1 FROM public.seller_offers o
      WHERE o.demand_id=d.id AND o.seller_id=NEW.seller_id)
    AND NOT EXISTS(
      SELECT 1 FROM public.products pr
      JOIN public.profiles sp ON sp.id=pr.seller_id
        AND sp.role='seller' AND sp.account_status='active'
      JOIN public.public_businesses pb
        ON pb.business_id=pr.business_id AND pb.seller_id=pr.seller_id
      WHERE pr.seller_id=NEW.seller_id AND pr.listing_status='approved'
        AND pr.category=d.category
        AND (NULLIF(BTRIM(d.subcategory),'') IS NULL
          OR lower(btrim(coalesce(pr.subcategory,'')))=lower(btrim(d.subcategory)))
    );
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.route_new_approved_product_to_open_demands() FROM PUBLIC,anon,authenticated;

CREATE TRIGGER approved_product_route_open_demands
AFTER INSERT OR UPDATE OF listing_status,category,subcategory,market_category,business_id
ON public.products
FOR EACH ROW EXECUTE FUNCTION private.route_new_approved_product_to_open_demands();

-- Backfill already-open Demands for currently eligible approved Seller products.
INSERT INTO public.buyer_demand_inbox(demand_id,seller_id,match_reason)
SELECT DISTINCT d.id,pr.seller_id,'approved_product_category'
FROM public.buyer_demands d
JOIN public.products pr ON pr.category=d.category AND pr.listing_status='approved'
JOIN public.profiles sp ON sp.id=pr.seller_id AND sp.role='seller' AND sp.account_status='active'
JOIN public.public_businesses pb ON pb.business_id=pr.business_id AND pb.seller_id=pr.seller_id
WHERE d.demand_status='open'
  AND (NULLIF(BTRIM(d.subcategory),'') IS NULL
    OR lower(btrim(coalesce(pr.subcategory,'')))=lower(btrim(d.subcategory)))
ON CONFLICT(demand_id,seller_id) DO NOTHING;

CREATE OR REPLACE VIEW public.public_buyer_demands
WITH (security_invoker=true)
AS
SELECT id,demand_code,product_name,category,subcategory,description,
       specifications_quality,required_quantity,budget,currency,
       destination_country,destination_city,required_date,demand_status,created_at
FROM public.buyer_demands
WHERE demand_status='open';

REVOKE ALL ON public.public_buyer_demands FROM PUBLIC;
GRANT SELECT ON public.public_buyer_demands TO anon,authenticated;

COMMIT;

\echo 'LOCAL BUYER DEMAND FIXTURE CREATED.'
\echo 'Scope: Demand, Seller Inbox, quotations, RLS, safe public projection and trigger routing.'
\echo 'No test users or Demand rows inserted by this fixture.'
\echo 'NOT a recovered migration; NOT deployable; Hosted Supabase untouched.'
