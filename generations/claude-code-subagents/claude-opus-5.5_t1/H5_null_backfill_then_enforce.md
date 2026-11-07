```sql
-- H5: backfill orders.customer_id from legacy_customer_map, then enforce NOT NULL + validated FK.
-- Strategy:
--   1. Backfill in small committed batches (short row locks only).
--   2. Add CHECK (customer_id IS NOT NULL) NOT VALID + FK NOT VALID in one short ACCESS EXCLUSIVE
--      lock, acquired with a short lock_timeout and retried (to slip into an analytics gap
--      without queueing app traffic behind us for long).
--   3. VALIDATE both (SHARE UPDATE EXCLUSIVE: does not block app or analytics).
--   4. SET NOT NULL (ACCESS EXCLUSIVE, retried) -- scan skipped thanks to the validated CHECK.

-- 1. Backfill in batches of 2000 rows, committing each batch.
DO $$
DECLARE
  last_id bigint := 0;
  hi_id   bigint;
BEGIN
  LOOP
    SELECT max(order_id) INTO hi_id
    FROM (SELECT order_id FROM legacy_customer_map
          WHERE order_id > last_id
          ORDER BY order_id
          LIMIT 2000) s;
    EXIT WHEN hi_id IS NULL;

    EXECUTE format(
      'UPDATE orders o
          SET customer_id = m.customer_id
         FROM legacy_customer_map m
        WHERE m.order_id > %s AND m.order_id <= %s
          AND o.id = m.order_id
          AND o.customer_id IS DISTINCT FROM m.customer_id',
      last_id, hi_id);

    last_id := hi_id;
    COMMIT;
  END LOOP;
END
$$;

-- 2. Add helper CHECK and the FK, both NOT VALID, under one brief lock (retry on lock timeout).
DO $$
DECLARE
  attempts int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '50ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_not_null_chk CHECK (customer_id IS NOT NULL) NOT VALID,
        ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts > 400 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

-- 3. Validate (SHARE UPDATE EXCLUSIVE on orders; does not conflict with app DML or analytics reads).
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null_chk;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 4. SET NOT NULL; the validated CHECK lets PostgreSQL skip the full-table scan.
DO $$
DECLARE
  attempts int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '50ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts > 400 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;
```
