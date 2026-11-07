-- WRONG (subtle): retries correctly but validates the FK inline (scan while holding SHARE ROW EXCLUSIVE, which blocks app writes).
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers(id); RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_customer_nn CHECK (customer_id IS NOT NULL) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_nn;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
