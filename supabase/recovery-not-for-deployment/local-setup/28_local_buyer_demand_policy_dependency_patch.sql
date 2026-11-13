-- NEXORA LOCAL B-03 POLICY DEPENDENCY PATCH
-- Repairs the local-only fixture 25 permission boundary without exposing seller_id.
-- Guarded to nexora_test. This is NOT a migration and NOT deployable.


DO $guard$
BEGIN
  IF current_database()<>'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test';
  END IF;
  IF to_regclass('public.buyer_demands') IS NULL
     OR to_regclass('public.buyer_demand_inbox') IS NULL
     OR to_regclass('public.seller_offers') IS NULL
     OR to_regclass('public.public_businesses') IS NULL THEN
    RAISE EXCEPTION 'SAFETY STOP: local Demand and visibility fixtures must exist';
  END IF;
END
$guard$;

BEGIN;

-- Policy predicates need to test business eligibility without granting
-- authenticated users direct SELECT on the private seller_id column.
CREATE OR REPLACE FUNCTION private.has_public_business_for_seller(p_seller_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.public_businesses b
    WHERE b.seller_id=p_seller_id
  );
$function$;

GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE ALL ON FUNCTION private.has_public_business_for_seller(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.has_public_business_for_seller(uuid)
  TO authenticated;

DROP POLICY IF EXISTS demands_owner_inbox_admin_read ON public.buyer_demands;
CREATE POLICY demands_owner_inbox_admin_read
ON public.buyer_demands FOR SELECT TO authenticated
USING (
  buyer_id=(SELECT auth.uid())
  OR public.is_nexora_admin()
  OR (
    demand_status='open'
    AND EXISTS(SELECT 1 FROM public.profiles p
      WHERE p.id=(SELECT auth.uid()) AND p.role='seller' AND p.account_status='active')
    AND private.has_public_business_for_seller((SELECT auth.uid()))
    AND EXISTS(SELECT 1 FROM public.buyer_demand_inbox i
      WHERE i.demand_id=buyer_demands.id AND i.seller_id=(SELECT auth.uid()))
  )
);

DROP POLICY IF EXISTS buyer_demand_inbox_seller_read ON public.buyer_demand_inbox;
CREATE POLICY buyer_demand_inbox_seller_read
ON public.buyer_demand_inbox FOR SELECT TO authenticated
USING (
  public.is_nexora_admin()
  OR (
    seller_id=(SELECT auth.uid())
    AND EXISTS(SELECT 1 FROM public.profiles p
      WHERE p.id=(SELECT auth.uid()) AND p.role='seller' AND p.account_status='active')
    AND private.has_public_business_for_seller((SELECT auth.uid()))
  )
);

DROP POLICY IF EXISTS offers_approved_seller_inbox_insert ON public.seller_offers;
CREATE POLICY offers_approved_seller_inbox_insert
ON public.seller_offers FOR INSERT TO authenticated
WITH CHECK (
  seller_id=(SELECT auth.uid())
  AND offer_status='pending'
  AND EXISTS(SELECT 1 FROM public.profiles p
    WHERE p.id=(SELECT auth.uid()) AND p.role='seller' AND p.account_status='active')
  AND private.has_public_business_for_seller((SELECT auth.uid()))
  AND EXISTS(SELECT 1 FROM public.buyer_demand_inbox i
    JOIN public.buyer_demands d ON d.id=i.demand_id
    WHERE i.demand_id=seller_offers.demand_id
      AND i.seller_id=(SELECT auth.uid()) AND d.demand_status='open')
);

COMMIT;

DO $verify$
BEGIN
  IF NOT has_function_privilege('authenticated',
       'private.has_public_business_for_seller(uuid)','EXECUTE')
     OR has_function_privilege('anon',
       'private.has_public_business_for_seller(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: private helper ACL is not narrow';
  END IF;
  IF has_column_privilege('authenticated','public.public_businesses','seller_id','SELECT')
     OR has_column_privilege('anon','public.public_businesses','seller_id','SELECT') THEN
    RAISE EXCEPTION 'FAIL: seller_id was exposed to client roles';
  END IF;
  RAISE NOTICE 'PASS: authenticated policy dependency uses private boolean helper; seller_id remains unexposed';
END
$verify$;

