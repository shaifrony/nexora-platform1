-- NEXORA Wholesale + Retail alignment
-- RECOVERY / REVIEW DRAFT ONLY — NOT A DEPLOYABLE MIGRATION.
-- Do not run against Live Supabase. Do not move into supabase/migrations/.
--
-- Intended rules:
-- 1) Buyer chooses one marketplace category at signup: wholesale OR retail.
-- 2) OAuth/social signup remains Buyer-only; category defaults to wholesale unless
--    trusted signup metadata supplies a valid category.
-- 3) Seller has no account-wide market category. Seller chooses market_category
--    independently for every product listing.
-- 4) Buyer can SELECT only approved products whose market_category matches
--    profiles.buyer_category. Seller can still see own listings; Admin retains review access.
--
-- IMPORTANT PRECONDITIONS:
-- - The real hosted schema and migration history have NOT been reconciled.
-- - The core marketplace migration inspected in this branch does not define
--   products.market_category. A later migration must be verified before this draft
--   can be adapted. This script deliberately aborts if the column is absent.
-- - Existing profile CHECK constraint names are discovered dynamically.
-- - BLOCKER: current Seller product INSERT and listing-edit RPC paths still consult
--   profiles.seller_categories. This draft empties that field for Sellers, so the
--   Seller phase must revise those policies/RPCs before this draft can ever be used.
-- - BLOCKER: verify the exact hosted auth.users provider metadata column and trigger
--   attachment; do not assume the local fixture matches Supabase Auth.
-- - Run only against a disposable local reconstruction after reviewing every section.

BEGIN;

DO $preflight$
DECLARE
  v_constraint_count integer;
BEGIN
  IF to_regclass('public.profiles') IS NULL
     OR to_regclass('public.products') IS NULL
     OR to_regclass('public.public_businesses') IS NULL THEN
    RAISE EXCEPTION 'Required NEXORA tables are missing; no changes made';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles'
      AND column_name IN ('buyer_category','seller_categories')
    GROUP BY table_name
    HAVING count(*)=2
  ) THEN
    RAISE EXCEPTION 'Expected profiles.buyer_category and profiles.seller_categories; no changes made';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='products'
      AND column_name='market_category'
  ) THEN
    RAISE EXCEPTION 'BLOCKED: products.market_category is absent in the inspected core schema. Verify the later schema migration first; no changes made';
  END IF;

  IF to_regprocedure('public.handle_new_user()') IS NULL THEN
    RAISE EXCEPTION 'public.handle_new_user() is missing; no changes made';
  END IF;

  IF to_regprocedure('private.create_product_inquiry(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'private.create_product_inquiry(uuid,text) is missing; inspect the inquiry workflow before proceeding';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='products'
      AND policyname='products_owner_approved_or_admin_read'
  ) THEN
    RAISE EXCEPTION 'Expected products read policy is missing; inspect current policy set; no changes made';
  END IF;

  SELECT count(*) INTO v_constraint_count
  FROM pg_constraint c
  JOIN pg_class t ON t.oid=c.conrelid
  JOIN pg_namespace n ON n.oid=t.relnamespace
  WHERE n.nspname='public' AND t.relname='profiles' AND c.contype='c'
    AND (pg_get_constraintdef(c.oid) ILIKE '%buyer_category%'
      OR pg_get_constraintdef(c.oid) ILIKE '%seller_categories%');

  IF v_constraint_count=0 THEN
    RAISE EXCEPTION 'No existing profile market-category CHECK constraint found; inspect schema before proceeding';
  END IF;
END
$preflight$;

-- Replace only profile CHECK constraints that govern buyer/seller market categories.
DO $constraints$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='public' AND t.relname='profiles' AND c.contype='c'
      AND (pg_get_constraintdef(c.oid) ILIKE '%buyer_category%'
        OR pg_get_constraintdef(c.oid) ILIKE '%seller_categories%')
  LOOP
    EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I',r.conname);
  END LOOP;
END
$constraints$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_market_categories_dual_market_check
  CHECK (
    (role='buyer'
      AND buyer_category IN ('wholesale','retail')
      AND seller_categories='{}'::text[])
    OR
    (role='seller'
      AND buyer_category IS NULL
      AND seller_categories='{}'::text[])
    OR
    (role IN ('porter','admin')
      AND buyer_category IS NULL
      AND seller_categories='{}'::text[])
  );

-- Keep the existing signup role allowlist and Porter approval gate.
-- Seller's market mode is intentionally not stored at account level.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_role text;
  v_name text;
  v_provider text;
  v_buyer_category text;
BEGIN
  v_provider:=lower(coalesce(NEW.raw_app_meta_data->>'provider',''));

  IF v_provider IN ('google','facebook') THEN
    v_role:='buyer';
  ELSE
    v_role:=lower(trim(coalesce(NEW.raw_user_meta_data->>'role','buyer')));
  END IF;

  IF v_role NOT IN ('buyer','seller','porter') THEN
    RAISE EXCEPTION 'Public signup role must be buyer, seller or porter';
  END IF;

  v_name:=nullif(btrim(coalesce(
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'name',
    ''
  )),'');
  IF v_name IS NOT NULL AND length(v_name)>150 THEN
    RAISE EXCEPTION 'Full name is too long';
  END IF;

  IF v_role='buyer' THEN
    v_buyer_category:=lower(trim(coalesce(
      NEW.raw_user_meta_data->>'buyer_category','wholesale'
    )));
    IF v_buyer_category NOT IN ('wholesale','retail') THEN
      RAISE EXCEPTION 'Buyer category must be wholesale or retail';
    END IF;

    INSERT INTO public.profiles(
      id,full_name,role,account_status,buyer_category,seller_categories
    )
    VALUES(NEW.id,v_name,'buyer','active',v_buyer_category,'{}'::text[]);

  ELSIF v_role='seller' THEN
    INSERT INTO public.profiles(
      id,full_name,role,account_status,buyer_category,seller_categories
    )
    VALUES(NEW.id,v_name,'seller','active',NULL,'{}'::text[]);

  ELSIF v_role='porter' THEN
    INSERT INTO public.profiles(
      id,full_name,role,account_status,buyer_category,seller_categories
    )
    VALUES(NEW.id,v_name,'porter','pending',NULL,'{}'::text[]);

    INSERT INTO public.porter_account_reviews(user_id,review_status)
    VALUES(NEW.id,'pending');
  END IF;

  RETURN NEW;
END;
$function$;

-- Preserve the existing function's trigger-only execution model.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;

-- Buyer visibility is enforced by RLS, not merely by the browser query.
DROP POLICY products_owner_approved_or_admin_read ON public.products;
CREATE POLICY products_owner_approved_or_admin_read
ON public.products
FOR SELECT TO authenticated
USING (
  seller_id=(SELECT auth.uid())
  OR public.is_nexora_admin()
  OR (
    listing_status='approved'
    AND EXISTS (
      SELECT 1
      FROM public.public_businesses b
      WHERE b.business_id=products.business_id
    )
    AND EXISTS (
      SELECT 1
      FROM public.profiles buyer_profile
      WHERE buyer_profile.id=(SELECT auth.uid())
        AND buyer_profile.role='buyer'
        AND buyer_profile.account_status='active'
        AND buyer_profile.buyer_category=products.market_category
    )
  )
);


-- The inquiry RPC is SECURITY DEFINER, so it must repeat the Buyer-category
-- authorization check rather than relying on products SELECT RLS.
CREATE OR REPLACE FUNCTION private.create_product_inquiry(
  p_product_id uuid,
  p_message text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_buyer_category text;
  v_product record;
  v_conversation_id uuid;
  v_title text;
  v_message text := left(btrim(coalesce(p_message,'')),500);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required' USING errcode='42501';
  END IF;

  SELECT p.buyer_category
    INTO v_buyer_category
  FROM public.profiles p
  WHERE p.id=v_user_id
    AND p.role='buyer'
    AND p.account_status='active';

  IF NOT FOUND OR v_buyer_category NOT IN ('wholesale','retail') THEN
    RAISE EXCEPTION 'An active Buyer account with a valid market category is required'
      USING errcode='42501';
  END IF;

  SELECT p.id,p.seller_id,p.product_code,p.product_name,p.market_category
    INTO v_product
  FROM public.products p
  JOIN public.business_profiles b ON b.id=p.business_id
  JOIN public.public_businesses pb ON pb.business_id=p.business_id
  WHERE p.id=p_product_id
    AND p.listing_status='approved'
    AND b.approval_status='approved'
    AND p.market_category=v_buyer_category;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product is unavailable or does not match your Buyer category'
      USING errcode='42501';
  END IF;

  IF v_product.seller_id=v_user_id THEN
    RAISE EXCEPTION 'You cannot send an inquiry to your own product'
      USING errcode='42501';
  END IF;

  v_title:=left(
    'Product Inquiry • '||v_product.product_code||' • '||
    v_product.product_name||
    CASE WHEN v_message<>'' THEN ' • Buyer note: '||v_message ELSE '' END,
    900
  );

  INSERT INTO public.conversations(conversation_type,created_by,title,status)
  VALUES('direct',v_user_id,v_title,'active')
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.conversation_participants(
    conversation_id,user_id,invited_by,invitation_status,joined_at
  )
  VALUES
    (v_conversation_id,v_user_id,v_user_id,'accepted',now()),
    (v_conversation_id,v_product.seller_id,v_user_id,'pending',NULL);

  RETURN v_conversation_id;
END;
$function$;

-- Verify expected metadata and policy definitions before committing this draft.
DO $verify$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.profiles'::regclass
      AND conname='profiles_market_categories_dual_market_check'
  ) THEN
    RAISE EXCEPTION 'Dual-market profile constraint verification failed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='products'
      AND policyname='products_owner_approved_or_admin_read'
      AND qual ILIKE '%buyer_category%'
      AND qual ILIKE '%market_category%'
  ) THEN
    RAISE EXCEPTION 'Buyer/product category RLS verification failed';
  END IF;
END
$verify$;

-- Keep this transaction open for review in disposable local testing.
-- COMMIT only after the schema, policy behavior, and signup-trigger tests pass.
-- For a rollback-only dry run, execute ROLLBACK instead.
