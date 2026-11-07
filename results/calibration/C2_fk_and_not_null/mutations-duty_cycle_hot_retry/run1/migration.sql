-- WRONG (subtle): reference A with a hot retry loop (175 ms wait, 10 ms pause) -> lock-queue starvation.
SET lock_timeout = '175ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.01); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_fk;   -- SHARE UPDATE EXCLUSIVE: app DML continues
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_customer_nn CHECK (customer_id IS NOT NULL) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.01); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_nn;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.01); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders DROP CONSTRAINT orders_customer_nn; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.01); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
