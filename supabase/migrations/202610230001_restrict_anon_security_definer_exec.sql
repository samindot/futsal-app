-- Remove implicit PUBLIC/anon EXECUTE grants from SECURITY DEFINER routines.
-- Keep only the explicitly intended public read RPCs public; all other callable routines
-- require an authenticated user. Trigger functions are not API RPCs and receive no direct grants.
DO $$
DECLARE
  fn record;
BEGIN
  FOR fn IN
    SELECT p.oid, p.prorettype = 'trigger'::regtype AS is_trigger
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND p.proname NOT IN ('get_public_bookings', 'get_matchmaking_sessions')
  LOOP
    IF fn.is_trigger THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role', fn.oid::regprocedure);
    ELSE
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', fn.oid::regprocedure);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', fn.oid::regprocedure);
    END IF;
  END LOOP;
END
$$;
