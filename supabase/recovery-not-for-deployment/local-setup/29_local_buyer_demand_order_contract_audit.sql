-- NEXORA Buyer Demand negotiation/order installed-contract audit.
-- LOCAL ONLY. Read-only; never applies migrations or changes data/schema.
-- Run only against nexora_test after the relevant schema and migration exist.
\set ON_ERROR_STOP on
\pset pager off

DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test, connected to %',current_database();
  END IF;
END
$guard$;

BEGIN TRANSACTION READ ONLY;

DO $audit$
DECLARE
  v_respond regprocedure := to_regprocedure('private.respond_to_demand_offer(uuid,text,numeric,numeric,text)');
  v_transition regprocedure := to_regprocedure('private.transition_buyer_demand_order(uuid,text,text)');
  v_respond_def text;
  v_transition_def text;
  v_missing text[] := ARRAY[]::text[];
BEGIN
  IF v_respond IS NULL OR v_transition IS NULL
     OR to_regclass('public.commerce_orders') IS NULL
     OR to_regclass('public.seller_offer_negotiations') IS NULL THEN
    RAISE NOTICE 'SKIP: full Buyer Demand order workflow is not installed in nexora_test; no checks requiring it were run';
    RETURN;
  END IF;

  v_respond_def := pg_get_functiondef(v_respond);
  v_transition_def := pg_get_functiondef(v_transition);

  IF position('p_action is null or p_action not in' in lower(v_respond_def))=0
    THEN v_missing := array_append(v_missing,'NULL/invalid negotiation action guard'); END IF;
  IF position('v_latest.actor_role=v_role' in lower(v_respond_def))=0
    THEN v_missing := array_append(v_missing,'reject turn-taking guard'); END IF;
  IF position('account_status=''active''' in lower(v_respond_def))=0
    THEN v_missing := array_append(v_missing,'active participant check in quotation RPC'); END IF;
  IF position('case when v_role=''seller'' then ''accepted'' else ''pending'' end' in lower(v_respond_def))=0
    THEN v_missing := array_append(v_missing,'Seller-accepted counter-offer order status'); END IF;
  IF position('accepted_at' in lower(v_respond_def))=0
    THEN v_missing := array_append(v_missing,'accepted_at handling for direct Seller acceptance'); END IF;
  IF position('account_status=''active''' in lower(v_transition_def))=0
    THEN v_missing := array_append(v_missing,'active participant check in order transition RPC'); END IF;
  IF position('p_action is null' in lower(v_transition_def))=0
    THEN v_missing := array_append(v_missing,'NULL order action guard'); END IF;

  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.seller_offer_negotiations'::regclass)
    THEN v_missing := array_append(v_missing,'negotiation history RLS enabled'); END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='seller_offer_negotiations'
      AND policyname='seller_offer_negotiations_participant_read'
  ) THEN v_missing := array_append(v_missing,'participant-only negotiation history SELECT policy'); END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='commerce_orders'
      AND indexname='commerce_orders_source_offer_unique_idx'
  ) THEN v_missing := array_append(v_missing,'one-order-per-source-offer unique index'); END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.commerce_orders'::regclass
      AND conname='commerce_orders_demand_source_check'
  ) THEN v_missing := array_append(v_missing,'Buyer Demand order source consistency constraint'); END IF;

  IF has_function_privilege('anon',v_respond,'EXECUTE')
     OR has_function_privilege('anon',v_transition,'EXECUTE') THEN
    v_missing := array_append(v_missing,'anon denied private workflow function execution');
  END IF;

  IF cardinality(v_missing)>0 THEN
    RAISE EXCEPTION 'FAIL: installed workflow contract missing: %',array_to_string(v_missing,', ');
  END IF;

  RAISE NOTICE 'PASS: installed Buyer Demand quotation/order SQL contract, participant history RLS, unique order source and anon function denial';
END
$audit$;

ROLLBACK;
\echo '=== LOCAL BUYER DEMAND ORDER CONTRACT AUDIT FINISHED (READ ONLY) ==='
