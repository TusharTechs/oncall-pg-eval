SET statement_timeout = 0;
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
            WHERE i.indrelid = 'orders'::regclass AND NOT i.indisvalid LOOP
    RAISE NOTICE 'invalid index left by previous attempt: %', r.relname;
  END LOOP;
END $$;
DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_key;
SET lock_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);
SET lock_timeout = '50ms';
DO $$ BEGIN
  FOR i IN 1..600 LOOP BEGIN
    ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP;
  RAISE EXCEPTION 'could not acquire lock';
END $$;
