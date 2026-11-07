-- WRONG (subtle): IF NOT EXISTS silently "reuses" the INVALID index; attaching it then fails.
SET statement_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS orders_external_ref_key ON orders (external_ref);
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN
  ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
