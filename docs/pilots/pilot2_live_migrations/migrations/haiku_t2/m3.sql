-- M3: UNIQUE(external_ref) built without blocking writes
SET lock_timeout = '100ms';

CREATE FUNCTION pg_temp.retry_ddl(stmt text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() >= deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- CONCURRENTLY must wait for the open analytics snapshot, so lock_timeout must be disabled here
SET lock_timeout = 0;
DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_key;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

SET lock_timeout = '100ms';
SELECT pg_temp.retry_ddl('ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key');
