-- M3: UNIQUE constraint on orders(external_ref)
SET lock_timeout = 0;
SET statement_timeout = 0;
SET maintenance_work_mem = '1GB';

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

-- 1. Build the unique index without blocking writes (lock_timeout must be 0 here: CIC's waits
--    for older transactions/snapshots are lock waits).
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON public.orders (external_ref);

-- 2. Attach it as a constraint (brief ACCESS EXCLUSIVE, no scan).
SELECT pg_temp.run_ddl(ARRAY[
  'ALTER TABLE public.orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key'
]);
