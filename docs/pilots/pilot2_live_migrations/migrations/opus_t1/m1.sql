-- M1: add region text NOT NULL DEFAULT 'EU' (PG11+ fast default: metadata-only, no rewrite).
-- The only risk is the ACCESS EXCLUSIVE lock queueing behind the open analytics
-- transaction and stalling the app, so acquire it with a short lock_timeout and retry.

CREATE FUNCTION pg_temp.ddl_with_retry(VARIADIC stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  -- transaction-local: only affects this call
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      attempt := attempt + 1;
      IF attempt >= 300 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

SELECT pg_temp.ddl_with_retry(
  $q$ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$q$
);
