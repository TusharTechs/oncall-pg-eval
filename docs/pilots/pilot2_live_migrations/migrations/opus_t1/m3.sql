-- M3: UNIQUE constraint on orders(external_ref) backed by a concurrently built index.

CREATE FUNCTION pg_temp.ddl_with_retry(VARIADIC stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
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

SET maintenance_work_mem = '512MB';
-- session lock_timeout stays 0 here: CIC must be allowed to wait for the analytics
-- transaction's snapshot (lock_timeout would otherwise abort its virtual-xid waits).
SET lock_timeout = 0;

DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_key;

-- SHARE UPDATE EXCLUSIVE only: app reads/writes continue during the build.
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

-- Attach as a constraint: metadata-only, brief ACCESS EXCLUSIVE with retry.
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key'
);
