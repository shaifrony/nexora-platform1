-- Revoke direct Data API execution of the internal DDL event-trigger function.
-- The function remains attached to the ensure_rls event trigger and is owned by postgres.
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;
