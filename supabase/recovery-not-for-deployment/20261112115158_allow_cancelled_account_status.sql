-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from current profiles_account_status_check.
-- Do not execute without isolated constraint tests and approval.
BEGIN;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_account_status_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_account_status_check
  CHECK (account_status = ANY (ARRAY['active','pending','suspended','cancelled']::text[]));
COMMIT;
