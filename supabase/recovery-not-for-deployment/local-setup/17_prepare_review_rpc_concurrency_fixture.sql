-- NEXORA CONCURRENCY TEST FIXTURE
-- LOCAL ONLY: nexora_test. This script COMMITS two dedicated test identities/one request.
-- Run 19_cleanup_review_rpc_concurrency_fixture.sql after both sessions finish.
\set ON_ERROR_STOP on
\pset pager off
DO $guard$
BEGIN
  IF current_database() <> 'nexora_test' THEN
    RAISE EXCEPTION 'SAFETY STOP: expected nexora_test';
  END IF;
  IF to_regprocedure('public.rpc_review_role_request(uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Review RPC prototype is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id IN (
    '22000000-0000-4000-8000-000000000001',
    '22000000-0000-4000-8000-000000000002'
  )) OR EXISTS (SELECT 1 FROM public.role_requests WHERE id='32000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Fixture IDs already exist; run cleanup or inspect before proceeding';
  END IF;
END
$guard$;

BEGIN;
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('22000000-0000-4000-8000-000000000001','rpc-concurrency-reviewer@nexora.invalid','{"role":"buyer","full_name":"Concurrency Reviewer"}','{}'),
 ('22000000-0000-4000-8000-000000000002','rpc-concurrency-buyer@nexora.invalid','{"role":"buyer","full_name":"Concurrency Buyer"}','{}');

UPDATE public.profiles
SET role='admin', buyer_category=NULL, seller_categories='{}'::text[]
WHERE id='22000000-0000-4000-8000-000000000001';

INSERT INTO public.admin_staff(user_id,admin_code,admin_level,department_key,is_active,position_key)
VALUES ('22000000-0000-4000-8000-000000000001','LOCAL-CONCURRENCY-REVIEWER','assistant_admin','managing_director',true,'department_officer');

INSERT INTO public.admin_permission_grants(admin_user_id,permission_key,is_allowed)
VALUES ('22000000-0000-4000-8000-000000000001','users.role_requests.review',true);

INSERT INTO public.role_requests(id,user_id,requested_role,status)
VALUES ('32000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000002','seller','pending');
COMMIT;

SELECT 'READY' AS concurrency_fixture,
       'Reviewer UID: 22000000-0000-4000-8000-000000000001' AS reviewer,
       'Request ID: 32000000-0000-4000-8000-000000000001' AS request_id;
