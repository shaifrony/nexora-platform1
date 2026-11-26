-- RECOVERY-ONLY LOCAL TEST CANDIDATE. NOT HISTORICAL SQL. NOT FOR DEPLOYMENT.
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  ddl_command record;
  target_relation record;
BEGIN
  FOR ddl_command IN
    SELECT command_tag, schema_name, object_type, objid, in_extension
    FROM pg_catalog.pg_event_trigger_ddl_commands()
  LOOP
    IF ddl_command.command_tag NOT IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
       OR ddl_command.schema_name IS DISTINCT FROM 'public'
       OR ddl_command.objid IS NULL
       OR ddl_command.in_extension THEN
      CONTINUE;
    END IF;

    SELECT namespace.nspname, relation.relname
      INTO target_relation
      FROM pg_catalog.pg_class AS relation
      JOIN pg_catalog.pg_namespace AS namespace
        ON namespace.oid = relation.relnamespace
     WHERE relation.oid = ddl_command.objid
       AND namespace.nspname = 'public'
       AND relation.relkind IN ('r', 'p')
       AND NOT EXISTS (
         SELECT 1
           FROM pg_catalog.pg_depend AS dependency
          WHERE dependency.classid = 'pg_catalog.pg_class'::pg_catalog.regclass
            AND dependency.objid = relation.oid
            AND dependency.deptype = 'e'
       );

    IF FOUND THEN
      EXECUTE pg_catalog.format(
        'ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY',
        target_relation.nspname,
        target_relation.relname
      );
    END IF;
  END LOOP;
END;
$function$;
ALTER FUNCTION public.rls_auto_enable() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;
CREATE EVENT TRIGGER ensure_rls
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION public.rls_auto_enable();
ALTER EVENT TRIGGER ensure_rls OWNER TO postgres;
