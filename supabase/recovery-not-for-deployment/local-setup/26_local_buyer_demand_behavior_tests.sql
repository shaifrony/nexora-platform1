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
('25000000-0000-4000-8000-000000000011','b03-seller-a@nexora.invalid',
 '{"provider":"email"}','{"role":"seller","full_name":"B03 Seller A"}'),
('25000000-0000-4000-8000-000000000012','b03-seller-b@nexora.invalid',
 '{"provider":"email"}','{"role":"seller","full_name":"B03 Seller B"}'),
('25000000-0000-4000-8000-000000000013','b03-seller-late-match@nexora.invalid',
 '{"provider":"email"}','{"role":"seller","full_name":"B03 Late Match Seller"}'),
('25000000-0000-4000-8000-000000000014','b03-seller-no-match@nexora.invalid',
 '{"provider":"email"}','{"role":"seller","full_name":"B03 Unmatched Seller"}');

INSERT INTO public.business_profiles(
  id,seller_id,display_name,country,city,sales_center_address,approval_status
) VALUES
('25100000-0000-4000-8000-000000000011','25000000-0000-4000-8000-000000000011','B03 Seller A Business','Bangladesh','Dhaka','Local test address','approved'),
('25100000-0000-4000-8000-000000000012','25000000-0000-4000-8000-000000000012','B03 Seller B Business','Bangladesh','Dhaka','Local test address','approved'),
('25100000-0000-4000-8000-000000000013','25000000-0000-4000-8000-000000000013','B03 Late Match Business','Bangladesh','Dhaka','Local test address','approved'),
('25100000-0000-4000-8000-000000000014','25000000-0000-4000-8000-000000000014','B03 Unmatched Business','Bangladesh','Dhaka','Local test address','approved');



INSERT INTO public.products(
  id,slug,seller_id,business_id,product_name,category,subcategory,
  image_urls,description,origin,specifications_quality,price,currency,listing_status
) VALUES
('25200000-0000-4000-8000-000000000011','b03-wholesale-phone',
 '25000000-0000-4000-8000-000000000011','25100000-0000-4000-8000-000000000011',
 'B03 Phone A','Electronics','Mobile Phones',
 '{}','Local test product','Bangladesh','Test specification',10000,'BDT','approved'),
('25200000-0000-4000-8000-000000000012','b03-retail-phone',
 '25000000-0000-4000-8000-000000000012','25100000-0000-4000-8000-000000000012',
 'B03 Phone B','Electronics','Mobile Phones',
 '{}','Local test product','Bangladesh','Test specification',11000,'BDT','approved'),
('25200000-0000-4000-8000-000000000013','b03-late-sofa',
 '25000000-0000-4000-8000-000000000013','25100000-0000-4000-8000-000000000013',
 'B03 Sofa','Furniture','Sofas',
 '{}','Local test product','Bangladesh','Test specification',20000,'BDT','approved'),
('25200000-0000-4000-8000-000000000014','b03-no-match-shirt',
 '25000000-0000-4000-8000-000000000014','25100000-0000-4000-8000-000000000014',
 'B03 Shirt','Apparel','Shirts',
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
    RAISE EXCEPTION 'FAIL: expected exactly 3 matching Sellers (regardless of product sale channel); got %',v_count;
  END IF;
  IF EXISTS(SELECT 1 FROM public.buyer_demand_inbox
    WHERE demand_id='25300000-0000-4000-8000-000000000001'
      AND seller_id='25000000-0000-4000-8000-000000000014') THEN
    RAISE EXCEPTION 'FAIL: category-mismatched Seller was routed';
  END IF;
  RAISE NOTICE 'PASS: Demand trigger routes by category/subcategory, without sale-type gating, and product approval/update routing works';
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
  IF has_table_privilege('anon','public.buyer_demand_inbox','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon has SELECT privilege on Seller inbox';
  END IF;
  IF has_table_privilege('anon','public.seller_offers','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon has SELECT privilege on Seller offers';
  END IF;
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

-- Seller inbox isolation: both matching Sellers receive the same Demand.
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000011',true);
DO $seller_wholesale$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.buyer_demands;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: routed Seller A should see Demand'; END IF;
  SELECT count(*) INTO v_count FROM public.buyer_demand_inbox;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: Seller should see only own Inbox row'; END IF;
  RAISE NOTICE 'PASS: routed Seller A sees Demand and own Inbox';
END
$seller_wholesale$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000012',true);
DO $seller_retail$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.buyer_demands;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: routed Seller B should see same Demand'; END IF;
  RAISE NOTICE 'PASS: routed Seller B also receives the same Demand';
END
$seller_retail$;

-- Seller quotation is allowed only when the Seller owns a routed inbox row.
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000011',true);
INSERT INTO public.seller_offers(
  id,demand_id,seller_id,offer_price,currency,available_quantity,message,
  product_brand,product_model,product_condition,price_basis,delivery_charge
) VALUES (
  '25400000-0000-4000-8000-000000000001',
  '25300000-0000-4000-8000-000000000001',
  '25000000-0000-4000-8000-000000000011',
  9800,'BDT','100','B03 quotation','Nexora Test','Model A','new','per_unit',0
);

DO $negative_seller_tests$
DECLARE v_denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.seller_offers(demand_id,seller_id,offer_price,currency,available_quantity)
    VALUES('25300000-0000-4000-8000-000000000001',
      '25000000-0000-4000-8000-000000000014',9000,'BDT','10');
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
      '25000000-0000-4000-8000-000000000011',9700,'BDT','10');
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
  SELECT count(*) INTO v_count FROM public.seller_offer_negotiations
  WHERE offer_id='25400000-0000-4000-8000-000000000001';
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: Buyer owner should see own quotation history'; END IF;
  RAISE NOTICE 'PASS: Buyer owner sees received Seller quotation and negotiation history';
END
$buyer_offer_read$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000002',true);
DO $other_buyer_offer_read$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.seller_offers;
  IF v_count<>0 THEN RAISE EXCEPTION 'FAIL: unrelated Buyer saw another Buyer quotation'; END IF;
  SELECT count(*) INTO v_count FROM public.seller_offer_negotiations;
  IF v_count<>0 THEN RAISE EXCEPTION 'FAIL: unrelated Buyer saw another Buyer negotiation history'; END IF;
  RAISE NOTICE 'PASS: unrelated Buyer cannot see another Buyer quotation or negotiation history';
END
$other_buyer_offer_read$;

-- Negotiation turn-taking and both Buyer Demand order conversion paths.
-- The rollback test bumps created_at between simulated API calls to model separate RPC transactions.
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_counter_first$
BEGIN
  PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000001','counter',80,9500,'Buyer counter A');
  RAISE NOTICE 'PASS: Buyer counter is accepted as a new negotiation turn';
END
$buyer_counter_first$;
RESET ROLE;
UPDATE public.seller_offer_negotiations SET created_at=clock_timestamp()
WHERE offer_id='25400000-0000-4000-8000-000000000001' AND actor_id='25000000-0000-4000-8000-000000000001' AND action='counter';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_repeat_counter_denied$
DECLARE v_denied boolean:=false;
BEGIN
  BEGIN
    PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000001','counter',70,9400,'Second Buyer counter');
  EXCEPTION WHEN raise_exception THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: same Buyer countered twice without Seller response'; END IF;
  RAISE NOTICE 'PASS: same-side repeat counter is blocked';
END
$buyer_repeat_counter_denied$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000011',true);
DO $seller_accepts_buyer_counter$
DECLARE v_order uuid; v_status text; v_accepted timestamptz; v_total numeric;
BEGIN
  v_order:=private.respond_to_demand_offer('25400000-0000-4000-8000-000000000001','accept',null,null,'Seller accepts Buyer counter');
  SELECT order_status,accepted_at,source_offer_total INTO v_status,v_accepted,v_total FROM public.commerce_orders WHERE id=v_order;
  IF v_status<>'accepted' OR v_accepted IS NULL OR v_total<>760000 THEN RAISE EXCEPTION 'FAIL: Seller acceptance did not create correct accepted order'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.commerce_order_events WHERE order_id=v_order AND event_type='accepted') THEN RAISE EXCEPTION 'FAIL: accepted order event missing'; END IF;
  RAISE NOTICE 'PASS: Seller acceptance of Buyer counter creates accepted order and event';
END
$seller_accepts_buyer_counter$;

SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000012',true);
INSERT INTO public.seller_offers(id,demand_id,seller_id,offer_price,currency,available_quantity,message)
VALUES('25400000-0000-4000-8000-000000000002','25300000-0000-4000-8000-000000000001','25000000-0000-4000-8000-000000000012',12000,'BDT','100','Seller B initial quote');
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_counter_second$
BEGIN
  PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000002','counter',60,11500,'Buyer counter B');
END
$buyer_counter_second$;
RESET ROLE;
UPDATE public.seller_offer_negotiations SET created_at=clock_timestamp()
WHERE offer_id='25400000-0000-4000-8000-000000000002' AND actor_id='25000000-0000-4000-8000-000000000001' AND action='counter';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_repeat_counter_second_denied$
DECLARE v_denied boolean:=false;
BEGIN
  BEGIN
    PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000002','counter',50,11400,'Repeated Buyer counter');
  EXCEPTION WHEN raise_exception THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: Buyer sent a second counter before Seller response'; END IF;
END
$buyer_repeat_counter_second_denied$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000012',true);
DO $seller_counter_second$
BEGIN
  PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000002','counter',55,11000,'Seller counter B');
END
$seller_counter_second$;
RESET ROLE;
UPDATE public.seller_offer_negotiations SET created_at=clock_timestamp()
WHERE offer_id='25400000-0000-4000-8000-000000000002' AND actor_id='25000000-0000-4000-8000-000000000012' AND action='counter';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000012',true);
DO $seller_repeat_counter_denied$
DECLARE v_denied boolean:=false;
BEGIN
  BEGIN
    PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000002','counter',50,10900,'Repeated Seller counter');
  EXCEPTION WHEN raise_exception THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: same Seller countered twice without Buyer response'; END IF;
END
$seller_repeat_counter_denied$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_accepts_seller_counter$
DECLARE v_order uuid; v_status text; v_accepted timestamptz;
BEGIN
  v_order:=private.respond_to_demand_offer('25400000-0000-4000-8000-000000000002','accept',null,null,'Buyer accepts Seller counter');
  SELECT order_status,accepted_at INTO v_status,v_accepted FROM public.commerce_orders WHERE id=v_order;
  IF v_status<>'pending' OR v_accepted IS NOT NULL THEN RAISE EXCEPTION 'FAIL: Buyer acceptance must await Seller confirmation'; END IF;
  PERFORM set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000012',true);
  PERFORM private.transition_buyer_demand_order(v_order,'accept','Seller confirms Buyer order');
  SELECT order_status,accepted_at INTO v_status,v_accepted FROM public.commerce_orders WHERE id=v_order;
  IF v_status<>'accepted' OR v_accepted IS NULL THEN RAISE EXCEPTION 'FAIL: Seller confirmation did not accept pending order'; END IF;
  RAISE NOTICE 'PASS: Buyer/Seller counter turn-taking and pending-to-accepted order confirmation';
END
$buyer_accepts_seller_counter$;

SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000013',true);
INSERT INTO public.seller_offers(id,demand_id,seller_id,offer_price,currency,available_quantity,message)
VALUES('25400000-0000-4000-8000-000000000003','25300000-0000-4000-8000-000000000001','25000000-0000-4000-8000-000000000013',13000,'BDT','50','Seller C initial quote');
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_rejects$
BEGIN
  PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000003','reject',null,null,'Price not suitable');
  IF NOT EXISTS(SELECT 1 FROM public.seller_offers WHERE id='25400000-0000-4000-8000-000000000003' AND offer_status='rejected' AND negotiation_status='declined') THEN RAISE EXCEPTION 'FAIL: rejected quotation status not updated'; END IF;
  RAISE NOTICE 'PASS: Buyer can reject the Seller latest quotation';
END
$buyer_rejects$;

INSERT INTO public.buyer_demands(id,buyer_id,product_name,category,subcategory,description,required_quantity,currency,destination_country,destination_city,required_date)
VALUES('25300000-0000-4000-8000-000000000002','25000000-0000-4000-8000-000000000001','B03 Expired Quote Demand','Electronics','Mobile Phones','Expired quote test','10 units','BDT','Bangladesh','Dhaka',current_date+7);
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000013',true);
INSERT INTO public.seller_offers(id,demand_id,seller_id,offer_price,currency,available_quantity,offer_valid_until,message)
VALUES('25400000-0000-4000-8000-000000000004','25300000-0000-4000-8000-000000000002','25000000-0000-4000-8000-000000000013',13000,'BDT','20',current_date-1,'Expired quote');
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $expired_offer$
DECLARE v_denied boolean:=false;
BEGIN
  BEGIN
    PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000004','accept',null,null,'Attempt expired offer');
  EXCEPTION WHEN raise_exception THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: expired quotation was accepted'; END IF;
  IF EXISTS(SELECT 1 FROM public.commerce_orders WHERE source_offer_id='25400000-0000-4000-8000-000000000004') THEN RAISE EXCEPTION 'FAIL: expired quotation created an order'; END IF;
  RAISE NOTICE 'PASS: expired quotation cannot create an order';
END
$expired_offer$;

-- Inactive-account enforcement and the complete Buyer Demand order lifecycle.
RESET ROLE;
INSERT INTO public.buyer_demands(id,buyer_id,product_name,category,subcategory,description,required_quantity,currency,destination_country,destination_city,required_date)
VALUES('25300000-0000-4000-8000-000000000003','25000000-0000-4000-8000-000000000001','B03 Lifecycle Demand','Electronics','Mobile Phones','Lifecycle and state-transition test','100 units','BDT','Bangladesh','Dhaka',current_date+7);
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000013',true);
INSERT INTO public.seller_offers(id,demand_id,seller_id,offer_price,currency,available_quantity,message)
VALUES('25400000-0000-4000-8000-000000000005','25300000-0000-4000-8000-000000000003','25000000-0000-4000-8000-000000000013',12500,'BDT','40','Lifecycle quote');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $lifecycle_buyer_accepts$
DECLARE v_order uuid;
BEGIN
  v_order:=private.respond_to_demand_offer('25400000-0000-4000-8000-000000000005','accept',null,null,'Buyer accepts lifecycle quote');
  IF NOT EXISTS(SELECT 1 FROM public.commerce_orders WHERE id=v_order AND order_status='pending' AND listing_type='buyer_demand') THEN
    RAISE EXCEPTION 'FAIL: lifecycle order did not start pending';
  END IF;
  RAISE NOTICE 'PASS: lifecycle order created in pending state';
END
$lifecycle_buyer_accepts$;

RESET ROLE;
UPDATE public.profiles SET account_status='suspended'
WHERE id='25000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $inactive_buyer_denied$
DECLARE v_denied boolean:=false;
BEGIN
  BEGIN
    PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000005','counter',20,12000,'Inactive Buyer attempt');
  EXCEPTION WHEN raise_exception THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: inactive Buyer negotiated a quotation'; END IF;
  RAISE NOTICE 'PASS: inactive Buyer cannot negotiate';
END
$inactive_buyer_denied$;
RESET ROLE;
UPDATE public.profiles SET account_status='active'
WHERE id='25000000-0000-4000-8000-000000000001';
UPDATE public.profiles SET account_status='suspended'
WHERE id='25000000-0000-4000-8000-000000000013';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000013',true);
DO $inactive_seller_denied$
DECLARE v_order uuid; v_denied boolean:=false;
BEGIN
  SELECT id INTO v_order FROM public.commerce_orders
  WHERE source_offer_id='25400000-0000-4000-8000-000000000005';
  BEGIN
    PERFORM private.transition_buyer_demand_order(v_order,'accept','Inactive Seller attempt');
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: inactive Seller accepted a Buyer Demand order'; END IF;
  RAISE NOTICE 'PASS: inactive Seller cannot accept an order';
END
$inactive_seller_denied$;
RESET ROLE;
UPDATE public.profiles SET account_status='active'
WHERE id='25000000-0000-4000-8000-000000000013';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000013',true);
DO $lifecycle_seller_accepts$
DECLARE v_order uuid; v_status text; v_accepted timestamptz;
BEGIN
  SELECT id INTO v_order FROM public.commerce_orders
  WHERE source_offer_id='25400000-0000-4000-8000-000000000005';
  PERFORM private.transition_buyer_demand_order(v_order,'accept','Seller accepts lifecycle order');
  SELECT order_status,accepted_at INTO v_status,v_accepted FROM public.commerce_orders WHERE id=v_order;
  IF v_status<>'accepted' OR v_accepted IS NULL THEN RAISE EXCEPTION 'FAIL: Seller acceptance transition invalid'; END IF;
  PERFORM private.transition_buyer_demand_order(v_order,'ready','Seller marks order ready');
  SELECT order_status INTO v_status FROM public.commerce_orders WHERE id=v_order;
  IF v_status<>'ready_for_confirmation' THEN RAISE EXCEPTION 'FAIL: ready transition invalid'; END IF;
  RAISE NOTICE 'PASS: Seller transitions pending → accepted → ready_for_confirmation';
END
$lifecycle_seller_accepts$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $lifecycle_buyer_completes$
DECLARE v_order uuid; v_status text; v_completed timestamptz;
BEGIN
  SELECT id INTO v_order FROM public.commerce_orders
  WHERE source_offer_id='25400000-0000-4000-8000-000000000005';
  PERFORM private.transition_buyer_demand_order(v_order,'complete','Buyer confirms receipt');
  SELECT order_status,completed_at INTO v_status,v_completed FROM public.commerce_orders WHERE id=v_order;
  IF v_status<>'completed' OR v_completed IS NULL THEN RAISE EXCEPTION 'FAIL: Buyer completion transition invalid'; END IF;
  RAISE NOTICE 'PASS: Buyer completes ready order and completion timestamp is recorded';
END
$lifecycle_buyer_completes$;
-- Buyer cancellation is limited to pending orders.
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000012',true);
INSERT INTO public.seller_offers(id,demand_id,seller_id,offer_price,currency,available_quantity,message)
VALUES('25400000-0000-4000-8000-000000000006','25300000-0000-4000-8000-000000000003','25000000-0000-4000-8000-000000000012',12600,'BDT','25','Cancellation quote');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_cancels_pending$
DECLARE v_order uuid; v_status text; v_cancelled timestamptz;
BEGIN
  v_order:=private.respond_to_demand_offer('25400000-0000-4000-8000-000000000006','accept',null,null,'Buyer accepts then cancels');
  PERFORM private.transition_buyer_demand_order(v_order,'cancel','Buyer no longer needs this order');
  SELECT order_status,cancelled_at INTO v_status,v_cancelled FROM public.commerce_orders WHERE id=v_order;
  IF v_status<>'cancelled' OR v_cancelled IS NULL THEN RAISE EXCEPTION 'FAIL: Buyer cancellation transition invalid'; END IF;
  RAISE NOTICE 'PASS: Buyer can cancel a pending order';
END
$buyer_cancels_pending$;

-- Seller rejection requires a reason and applies only to pending orders.
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000011',true);
INSERT INTO public.seller_offers(id,demand_id,seller_id,offer_price,currency,available_quantity,message)
VALUES('25400000-0000-4000-8000-000000000007','25300000-0000-4000-8000-000000000003','25000000-0000-4000-8000-000000000011',12700,'BDT','30','Rejection quote');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000001',true);
DO $buyer_accepts_rejection_quote$
BEGIN
  PERFORM private.respond_to_demand_offer('25400000-0000-4000-8000-000000000007','accept',null,null,'Buyer accepts pending rejection test');
END
$buyer_accepts_rejection_quote$;
SELECT set_config('request.jwt.claim.sub','25000000-0000-4000-8000-000000000011',true);
DO $seller_rejects_pending$
DECLARE v_order uuid; v_denied boolean:=false; v_status text;
BEGIN
  SELECT id INTO v_order FROM public.commerce_orders
  WHERE source_offer_id='25400000-0000-4000-8000-000000000007';
  BEGIN
    PERFORM private.transition_buyer_demand_order(v_order,'reject','');
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: Seller rejection without reason was accepted'; END IF;
  PERFORM private.transition_buyer_demand_order(v_order,'reject','Supply unavailable');
  SELECT order_status INTO v_status FROM public.commerce_orders WHERE id=v_order;
  IF v_status<>'rejected' THEN RAISE EXCEPTION 'FAIL: Seller rejection transition invalid'; END IF;
  RAISE NOTICE 'PASS: Seller rejection requires a reason and rejects a pending order';
END
$seller_rejects_pending$;

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
  IF has_column_privilege('anon','public.buyer_demands','buyer_id','SELECT')
     OR has_column_privilege('authenticated','public.buyer_demands','buyer_id','SELECT') THEN
    RAISE EXCEPTION 'FAIL: Buyer ID is exposed to an API role';
  END IF;
  IF has_function_privilege('anon','private.is_buyer_demand_owner(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon can execute the private Buyer ownership helper';
  END IF;
  IF NOT has_function_privilege('authenticated','private.is_buyer_demand_owner(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated cannot execute the private Buyer ownership helper';
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
