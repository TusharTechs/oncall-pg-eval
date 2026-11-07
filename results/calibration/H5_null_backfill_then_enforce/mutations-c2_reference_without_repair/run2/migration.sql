-- WRONG here: the C2 reference, which never repairs the NULL rows (VALIDATE of the NOT NULL check fails).
-- Reference A: NOT VALID constraints (brief locks, retried), validate without blocking writes, then SET NOT NULL using the validated CHECK.
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_fk;   -- SHARE UPDATE EXCLUSIVE: app DML continues
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_customer_nn CHECK (customer_id IS NOT NULL) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_nn;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders DROP CONSTRAINT orders_customer_nn; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
