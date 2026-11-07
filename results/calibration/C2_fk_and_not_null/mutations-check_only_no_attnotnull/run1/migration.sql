-- WRONG (end state): never sets attnotnull, only a CHECK.
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_fk;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT orders_customer_nn CHECK (customer_id IS NOT NULL) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; RAISE EXCEPTION 'could not acquire lock'; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_nn;
