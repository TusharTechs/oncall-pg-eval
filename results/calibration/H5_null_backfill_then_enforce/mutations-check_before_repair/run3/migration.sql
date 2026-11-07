-- WRONG (subtle, the C30 trap): adds the NOT VALID CHECK *before* the repair; it is enforced on app UPDATEs of still-NULL rows.
-- (was Reference A: repair the data FIRST in small committed batches (row locks held for milliseconds), and only then add
-- the constraints. A CHECK added earlier (even NOT VALID) would be enforced on the app's UPDATEs of still-NULL rows.
SET lock_timeout = '50ms';
CREATE FUNCTION pg_temp.retry(stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  FOR i IN 1..600 LOOP
    BEGIN EXECUTE stmt; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock: %', stmt;
END $$;
SELECT pg_temp.retry('ALTER TABLE orders ADD CONSTRAINT orders_customer_nn CHECK (customer_id IS NOT NULL) NOT VALID');
DO $$
DECLARE lo bigint := 0; mx bigint;
BEGIN
  SELECT max(order_id) INTO mx FROM legacy_customer_map;
  WHILE lo <= mx LOOP
    UPDATE orders o SET customer_id = m.customer_id
      FROM legacy_customer_map m
     WHERE m.order_id > lo AND m.order_id <= lo + 80000 AND o.id = m.order_id AND o.customer_id IS NULL;
    lo := lo + 80000;
    COMMIT;
  END LOOP;
END $$;
SELECT pg_temp.retry('ALTER TABLE orders ADD CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID');
SET lock_timeout = 0;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_fk;
SET lock_timeout = '50ms';
SET lock_timeout = 0;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_nn;
SET lock_timeout = '50ms';
SELECT pg_temp.retry('ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL');
SELECT pg_temp.retry('ALTER TABLE orders DROP CONSTRAINT orders_customer_nn');
