-- WRONG (subtle): plain CREATE UNIQUE INDEX with lock_timeout retry: once it gets the SHARE lock it blocks app writes for the whole build.
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN CREATE UNIQUE INDEX orders_external_ref_key ON orders (external_ref); RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
