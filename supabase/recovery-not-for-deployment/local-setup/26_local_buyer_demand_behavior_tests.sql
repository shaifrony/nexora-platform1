-- NEXORA LOCAL B-03 BUYER DEMAND / ROUTING / PRIVACY BEHAVIOR TESTS
-- SAFETY: local nexora_test only. Requires fixture 06 + 21 + 25.
-- All test Auth users, profiles, businesses, products, Demands and offers ROLLBACK.
-- This is a local PostgreSQL logic test, NOT real Supabase JWT/PostgREST testing.

\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database()<>'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %',current_database();
  END IF;
  IF to_regclass('public.buyer_demands') IS NULL
     OR to_regclass('public.seller_offers') IS NULL
     OR to_regclass('public.buyer_demand_inbox') IS NULL
     OR to_regclass('public.public_buyer_demands') IS NULL
     OR to_regprocedure('private.route_new_buyer_demand_to_sellers()') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: run local Demand fixture 25 first';
  END IF;
END
$guard$;

BEGIN;

-- Stable local-only test identities. Auth trigger creates profiles.
INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data) VALUES
('25000000-0000-4000-8000-000000000001','b03-buyer-one@nexora.invalid',
 '{"provider":"email"}','{"role":"buyer","full_name":"B03 Buyer One"}'),
('25000000-0000-4000-8000-000000000002','b03-buyer-two@nexora.invalid',
 '{"provider":"email"}','{"role":"buyer","full_name":"B03 Buyer Two"}'),
('25000000-0000-4000-8000-000000000011','b03-seller-wholesale@nexora.invalid',
 '{"provider":"email"}','{"role":"seller","full_name":"B03 Wholesale Seller"}'),
('25000000-0000-4000-8000-000000000012','b03-seller-retail@nexora.invalid',
 '{"provider":"email"}','{"role":"seller","full_name":"B03 Retail Seller"}'),
('25000000-0000-4000-8000-000000000013','b03-seller-late-match@nexora.invalid',
 '{"provider":"email"}','{"role":"seller","full_name":"B03 Late Match Seller"}'),
('25000000-0000-4000-8000-000000000014','b03-seller-no-match@nexora.invalid',
 '{"provider":"email"}','{"role":"seller","full_name":"B03 Unmatched Seller"}');

INSERT INTO public.public_businesses(business_id,seller_id,display_name,country,city) VALUES
('25100000-0000-4000-8000-000000000011','25000000-0000-4000-8000-000000000011','B03 Wholesale Business','Bangladesh','Dhaka'),
('25100000-0000-4000-8000-000000000012','25000000-0000-4000-8000-000000000012','B03 Retail Business','Bangladesh','Dhaka'),
('25100000-0000-4000-8000-000000000013','25000000-0000-4000-8000-000000000013','B03 Late Match Business','Bangladesh','Dhaka'),
('25100000-0000-4000-8000-000000000014','25000000-0000-4000-8000-000000000014','B03 Unmatched Business','Bangladesh','Dhaka');

INSERT INTO public.products(
  id,slug,seller_id,business_id,product_name,category,subcategory,market_category,
  image_urls,description,origin,specifications_quality,price,currency,listing_status
) VALUES
('25200000-0000-4000-8000-000000000011','b03-wholesale-phone',
 '25000000-0000-4000-8000-000000000011','25100000-0000-4000-8000-000000000011',
 'B03 Wholesale Phone','Electronics','Mobile Phones','wholesale',
 '{}','Local test product','Bangladesh','Test specification',10000,'BDT','approved'),
('25200000-0000-4000-8000-000000000012','b03-retail-phone',
 '25000000-0000-4000-8000-000000000012','25100000-0000-4000-8000-000000000012',
 'B03 Retail Phone','Electronics','Mobile Phones','retail',
 '{}','Local test product','Bangladesh','Test specification',11000,'BDT','approved'),
('25200000-0000-4000-8000-000000000013','b03-late-sofa',
 '25000000-0000-4000-8000-000000000013','25100000-0000-4000-8000-000000000013',
 'B03 Sofa','Furniture','Sofas','wholesale',
 '{}','Local test product','Bangladesh','Test specification',20000,'BDT','approved'),
('25200000-0000-4000-8000-000000000014','b03-no-match-shirt',
 '25000000-0000-4000-8000-000000000014','25100000-0000-4000-8000-000000000014',
 'B03 Shirt','Apparel','Shirts','retail',
 '{}','Local test product','Bangladesh','Test specification',500,'BDT','approved');

-- Creating an open Demand should route it to existing approved taxonomy matches.
INSERT INTO public.buyer_demands(
  id,buyer_id,product_name,category,subcategory,description,specifications_quality,
  required_quantity,budget,currency,destination_country,destination_city,required_date
) VALUES (
  '25300000-0000-4000-8000-000000000001',
  '25000000-0000-4000-8000-000000000001',
  'B03 Mobile Phone Demand','Electronics','Mobile Phones','Local test Demand',
  'Test specification','100 units',1200000,'BDT','Bangladesh','Dhaka',current_date+7
);

-- Changing a previously unmatched approved product to the Demand taxonomy should route it.
UPDATE public.products
SET category='Electronics',subcategory='Mobile Phones'
WHERE id='25200000-0000-4000-8000-000000000013';

DO $seed_checks$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.buyer_demand_inbox
  WHERE demand_id='25300000-0000-4000-8000-000000000001';
  IF v_count<>3 THEN
    RAISE EXCEPTION 'FAIL: expected exactly 3 matching Sellers (including Wholesale and Retail); got %',v_count;
  END IF;
  IF EXISTS(SELECT 1 FROM public.buyer_demand_inbox
    WHERE demand_id='25300000-0000-4000-8000-000000000001'
      AND seller_id='25000000-0000-4000-8000-000000000014') THEN
    RAISE EXCEPTION 'FAIL: category-mismatched Seller was routed';
  END IF;
  RAISE NOTICE 'PASS: Demand trigger routes by category/subcategory, independent of Wholesale/Retail, and product approval/update routing works';
END
$seed_checks$;

-- Public anonymous surface: open Demand projection only, no buyer_id or private tables.
SET LOCAL ROLE anon;
DO $anon_checks$
DECLARE v_count integer; v_denied boolean:=false;
BEGIN
  SELECT count(*) INTO v_count FROM public.public_buyer_demands;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: anonymous public Demand projection expected 1 row, got %',v_count; END IF;
  v_denied:=false;
  BEGIN
    EXECUTE 'SELECT buyer_id FROM public.buyer_demands LIMIT 1';
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: anon can read buyer_id'; END IF;
  v_denied:=false;
  BEGIN
    EXECUTE 'SELECT count(*) FROM public.buyer_demand_inbox';
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: anon can read Seller inbox'; END IF;
  v_denied:=false;
  BEGIN
    EXECUTE 'SELECT count(*) FROM public.seller_offers';
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: anon can read Seller offers'; END IF;
  RAISE NOTICE 'PASS: anon sees only safe open Demand projection; Buyer ID, inbox and quotations are denied';
END
$anon_checks$;
RESET ROLE;

-- Buyer ownership: Buyer One sees own Demand, Buyer Two cannot see it.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_one$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.buyer_demands;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: Demand owner should see exactly one own Demand, got %',v_count; END IF;
  RAISE NOTICE 'PASS: Buyer sees own Demand';
END
$buyer_one$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000002',true);
DO $buyer_two$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.buyer_demands;
  IF v_count<>0 THEN RAISE EXCEPTION 'FAIL: unrelated Buyer saw another Buyer Demand'; END IF;
  RAISE NOTICE 'PASS: unrelated Buyer cannot see another Buyer Demand';
END
$buyer_two$;

-- Seller inbox isolation: Wholesale and Retail Seller both receive the same Demand.
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000011',true);
DO $seller_wholesale$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.buyer_demands;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: routed Wholesale Seller should see Demand'; END IF;
  SELECT count(*) INTO v_count FROM public.buyer_demand_inbox;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: Seller should see only own Inbox row'; END IF;
  RAISE NOTICE 'PASS: routed Wholesale Seller sees Demand and own Inbox';
END
$seller_wholesale$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000012',true);
DO $seller_retail$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.buyer_demands;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: routed Retail Seller should see same Demand'; END IF;
  RAISE NOTICE 'PASS: Retail Seller also receives same Demand; no sale-type gate';
END
$seller_retail$;

-- Seller quotation is allowed only when the Seller owns a routed inbox row.
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000011',true);
INSERT INTO public.seller_offers(
  demand_id,seller_id,offer_price,currency,available_quantity,message,
  product_brand,product_model,product_condition,price_basis,delivery_charge
) VALUES (
  '25300000-0000-4000-8000-000000000001',
  '25000000-0000-4000-8000-000000000011',
  9800,'BDT','100 units','B03 quotation','Nexora Test','Model A','new','per_unit',0
);

DO $negative_seller_tests$
DECLARE v_denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.seller_offers(demand_id,seller_id,offer_price,currency,available_quantity)
    VALUES('25300000-0000-4000-8000-000000000001',
      '25000000-0000-4000-8000-000000000014',9000,'BDT','10 units');
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: unmatched Seller submitted quotation'; END IF;

  v_denied:=false;
  BEGIN
    INSERT INTO public.buyer_demand_inbox(demand_id,seller_id)
    VALUES('25300000-0000-4000-8000-000000000001',
      '25000000-0000-4000-8000-000000000014');
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: Seller directly wrote a routing row'; END IF;

  v_denied:=false;
  BEGIN
    INSERT INTO public.seller_offers(demand_id,seller_id,offer_price,currency,available_quantity)
    VALUES('25300000-0000-4000-8000-000000000001',
      '25000000-0000-4000-8000-000000000011',9700,'BDT','10 units');
  EXCEPTION WHEN unique_violation THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: duplicate Seller quotation was accepted'; END IF;
  RAISE NOTICE 'PASS: unmatched Seller denied, direct Inbox writes denied, duplicate quotation blocked';
END
$negative_seller_tests$;

-- Buyer can see received quotations; unrelated Buyer cannot.
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_offer_read$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.seller_offers;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: Buyer owner should see received quotation'; END IF;
  RAISE NOTICE 'PASS: Buyer owner sees received Seller quotation';
END
$buyer_offer_read$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000002',true);
DO $other_buyer_offer_read$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.seller_offers;
  IF v_count<>0 THEN RAISE EXCEPTION 'FAIL: unrelated Buyer saw another Buyer quotation'; END IF;
  RAISE NOTICE 'PASS: unrelated Buyer cannot see another Buyer quotation';
END
$other_buyer_offer_read$;

-- Buyer spoofing another owner ID must fail the INSERT policy.
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_spoof$
DECLARE v_denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.buyer_demands(
      buyer_id,product_name,category,subcategory,description,required_quantity,
      currency,destination_country,destination_city,required_date
    ) VALUES (
      '25000000-0000-4000-8000-000000000002',
      'Spoofed Demand','Electronics','Mobile Phones','Attempt to spoof owner',
      '1 unit','BDT','Bangladesh','Dhaka',current_date+2
    );
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: Buyer spoofed another Buyer ID'; END IF;
  RAISE NOTICE 'PASS: Buyer cannot create Demand for another account';
END
$buyer_spoof$;

RESET ROLE;

DO $required_date_test$
DECLARE v_rejected boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.buyer_demands(
      buyer_id,product_name,category,subcategory,description,required_quantity,
      currency,destination_country,destination_city,required_date
    ) VALUES (
      '25000000-0000-4000-8000-000000000001',
      'Past-date Demand','Electronics','Mobile Phones','Invalid past date',
      '1 unit','BDT','Bangladesh','Dhaka',current_date-1
    );
  EXCEPTION WHEN check_violation THEN v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: past required_date was accepted'; END IF;
  RAISE NOTICE 'PASS: required_date cannot be in the past';
END
$required_date_test$;

DO $catalog_assertions$
BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.buyer_demands'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.seller_offers'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.buyer_demand_inbox'::regclass) THEN
    RAISE EXCEPTION 'FAIL: Demand RLS missing';
  END IF;
  IF has_column_privilege('anon','public.buyer_demands','buyer_id','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon has buyer_id SELECT';
  END IF;
  IF has_any_column_privilege('authenticated','public.buyer_demand_inbox','INSERT')
     OR has_any_column_privilege('authenticated','public.buyer_demand_inbox','UPDATE')
     OR has_table_privilege('authenticated','public.buyer_demand_inbox','DELETE') THEN
    RAISE EXCEPTION 'FAIL: authenticated can directly modify Inbox';
  END IF;
  RAISE NOTICE 'PASS: RLS enabled and private Buyer ID / routing ACL boundaries retained';
END
$catalog_assertions$;

ROLLBACK;
\echo '=== LOCAL B-03 DEMAND BEHAVIOR TESTS PASSED; ALL TEST DATA ROLLED BACK ==='
