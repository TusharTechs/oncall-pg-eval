-- M1: add orders.region text NOT NULL DEFAULT 'EU'
SET lock_timeout = 0;
SET statement_timeout = 0;

-- Helper: first take SHARE UPDATE EXCLUSIVE (does not conflict with the app or the analytics reader,
-- but makes a non-wraparound autovacuum get cancelled), then try the ACCESS EXCLUSIVE DDL with a short
-- lock_timeout so the app is never queued behind us for more than ~100 ms; retry until the
-- long-running analytics transaction has gone away.
CREATE FUNCTION pg_temp.run_ddl(stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '0', true);
  LOCK TABLE public.orders IN SHARE UPDATE EXCLUSIVE MODE;
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    attempt := attempt + 1;
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF attempt >= 300 THEN
        RAISE;
      END IF;
    END;
    PERFORM pg_sleep(0.1 + random() * 0.05);
  END LOOP;
END
$$;

-- Constant default => metadata-only (missing value), no rewrite and no NOT NULL scan.
SELECT pg_temp.run_ddl(ARRAY[
  $q$ALTER TABLE public.orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$q$
]);
