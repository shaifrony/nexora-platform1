-- RECOVERY-ONLY patch for the active Buyer Demand quotation SELECT policy.
-- Not a historical migration. Not an active migration. Not deployable.
-- Apply only to a disposable local PostgreSQL/Supabase database after all 38
-- active migrations and Foundation/Admin Governance recovery candidates.
--
-- The old SELECT policy directly queried buyer_demands.buyer_id. That column is
-- intentionally unavailable to authenticated API users, so policy evaluation
-- could fail while reading Seller offers. This helper returns only an ownership
-- boolean for one supplied Demand ID; it does not expose Buyer identity/contact.

CREATE OR REPLACE FUNCTION private.is_buyer_demand_owner(p_demand_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN (SELECT auth.uid()) IS NULL OR p_demand_id IS NULL THEN false
    ELSE EXISTS (
      SELECT 1
      FROM public.buyer_demands AS demand
      JOIN public.profiles AS buyer ON buyer.id=demand.buyer_id
      WHERE demand.id=p_demand_id
        AND demand.buyer_id=(SELECT auth.uid())
        AND buyer.role='buyer'
        AND buyer.account_status='active'
    )
  END;
$function$;

ALTER FUNCTION private.is_buyer_demand_owner(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.is_buyer_demand_owner(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.is_buyer_demand_owner(uuid) TO authenticated;

DROP POLICY IF EXISTS offers_select_buyer_seller_or_admin ON public.seller_offers;
CREATE POLICY offers_select_buyer_seller_or_admin
ON public.seller_offers FOR SELECT TO authenticated
USING (
  seller_id=(SELECT auth.uid())
  OR public.is_nexora_admin()
  OR private.is_buyer_demand_owner(demand_id)
);

-- Required local verification:
-- * Buyer owner sees the quotation; unrelated Buyer does not.
-- * Seller sees only its own quotation; unrelated Seller cannot submit one.
-- * anon has no EXECUTE; authenticated has EXECUTE.
-- * buyer_demands.buyer_id remains unselectable by anon/authenticated.

-- Negotiation history must use the same private owner helper; do not query
-- buyer_demands.buyer_id from an authenticated RLS policy.
DROP POLICY IF EXISTS seller_offer_negotiations_participant_read ON public.seller_offer_negotiations;
CREATE POLICY seller_offer_negotiations_participant_read
ON public.seller_offer_negotiations FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.seller_offers AS offer
    WHERE offer.id=seller_offer_negotiations.offer_id
      AND (
        offer.seller_id=(SELECT auth.uid())
        OR private.is_buyer_demand_owner(offer.demand_id)
      )
  )
);
