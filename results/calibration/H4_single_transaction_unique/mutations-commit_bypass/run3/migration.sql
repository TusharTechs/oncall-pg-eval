-- WRONG (forbidden by the ticket): escape the deploy tool's transaction with COMMIT, then do the C3 recipe.
COMMIT;
SET lock_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN
  ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
BEGIN;
