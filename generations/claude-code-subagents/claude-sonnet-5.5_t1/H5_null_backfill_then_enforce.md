```sql
-- 1. Backfill in small committed batches (id ranges) so row locks are short-lived.
DO $$
DECLARE
  lo   bigint;
  mx   bigint;
  step bigint := 20000;
BEGIN
  SELECT min(order_id), max(order_id) INTO lo, mx FROM legacy_customer_map;
  WHILE lo <= mx LOOP
    UPDATE orders o
       SET customer_id = m.customer_id
      FROM legacy_customer_map m
     WHERE m.order_id = o.id
       AND m.order_id >= lo AND m.order_id < lo + step
       AND o.customer_id IS NULL;
    COMMIT;
    lo := lo + step;
  END LOOP;
END
$$;

-- 2. Metadata-only DDL with short lock_timeout and retry, so we never sit in the
--    lock queue (behind the analytics transaction) and stall application traffic.
SET lock_timeout = '50ms';

DO $$
BEGIN
  FOR i IN 1..1500 LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_nn_chk CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

DO $$
BEGIN
  FOR i IN 1..1500 LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- 3. Validation scans only take SHARE UPDATE EXCLUSIVE / ROW SHARE (no write blocking).
SET lock_timeout = '0';
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn_chk;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 4. SET NOT NULL skips the table scan because a validated CHECK proves it.
SET lock_timeout = '50ms';

DO $$
BEGIN
  FOR i IN 1..1500 LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
