```sql
-- H5: repair customer_id from legacy_customer_map, then enforce NOT NULL + validated FK
SET lock_timeout = 0;
SET statement_timeout = 0;

ANALYZE legacy_customer_map;

-- 1. Backfill in small committed batches (short row locks, no long transaction)
DO $$
DECLARE
  lo   bigint := 0;
  mx   bigint;
  step bigint := 20000;
BEGIN
  SELECT max(id) INTO mx FROM orders;
  WHILE lo <= mx LOOP
    UPDATE orders o
       SET customer_id = m.customer_id
      FROM legacy_customer_map m
     WHERE m.order_id = o.id
       AND m.order_id > lo AND m.order_id <= lo + step
       AND o.id       > lo AND o.id       <= lo + step
       AND o.customer_id IS NULL;
    COMMIT;
    lo := lo + step;
  END LOOP;
END $$;

-- sanity check: no NULLs may remain
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM orders WHERE customer_id IS NULL) THEN
    RAISE EXCEPTION 'backfill incomplete: NULL customer_id rows remain';
  END IF;
END $$;

-- 2. CHECK (customer_id IS NOT NULL) NOT VALID. Needs a brief ACCESS EXCLUSIVE lock,
--    so use a short lock_timeout and retry. Waiting behind the analytics transaction
--    must never stall the app.
DO $$
DECLARE i int := 0;
BEGIN
  SET LOCAL lock_timeout = '50ms';
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_nn_chk CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.3);
    END;
  END LOOP;
END $$;

-- Validation takes only SHARE UPDATE EXCLUSIVE, so it does not block app writes.
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn_chk;

-- 3. Foreign key as NOT VALID (no scan), retrying on lock timeout
DO $$
DECLARE i int := 0;
BEGIN
  SET LOCAL lock_timeout = '50ms';
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.3);
    END;
  END LOOP;
END $$;

-- Validate without blocking writes
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 4. SET NOT NULL. The validated CHECK lets PG skip the table scan, so the
--    ACCESS EXCLUSIVE lock is held only momentarily. Retry on lock timeout.
DO $$
DECLARE i int := 0;
BEGIN
  SET LOCAL lock_timeout = '50ms';
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.3);
    END;
  END LOOP;
END $$;
```
