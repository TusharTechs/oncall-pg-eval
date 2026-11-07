-- WRONG (probably): repair all 300k rows in ONE transaction; its row locks block app UPDATEs of those rows until commit.
SET lock_timeout = 0;
UPDATE orders o SET customer_id = m.customer_id FROM legacy_customer_map m WHERE o.id = m.order_id AND o.customer_id IS NULL;
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT fk;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT nn CHECK (customer_id IS NOT NULL) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT nn;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
