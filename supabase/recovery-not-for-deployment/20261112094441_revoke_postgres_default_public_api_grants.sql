-- NEXORA RECOVERY DRAFT — NOT AN ORIGINAL HISTORICAL FILE
-- Status: RECONSTRUCTED from pg_default_acl for owner postgres in schema public.
-- This draft is limited to future objects created by postgres; it does not revoke
-- explicit grants on existing tables. Confirm intended scope before execution.
BEGIN;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
COMMIT;
