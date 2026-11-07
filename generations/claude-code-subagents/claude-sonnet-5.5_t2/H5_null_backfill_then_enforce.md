```sql
-- Migration for ticket H5: repair customer_id, then enforce NOT NULL and a validated FK.
-- Every lock-taking DDL runs with a short lock_timeout and retries, so it never queues
-- behind the analytics transaction while blocking the app.

-- 1. Backfill in small committed batches, keyed on the map's primary key.
DO $$
DECLARE
  lo bigint := 0;
  hi bigint;
BEGIN
  LOOP
    SELECT max(order_id) INTO hi
    FROM (SELECT order_id
          FROM legacy_customer_map
          WHERE order_id > lo
          ORDER BY order_id
          LIMIT 2000) s;
    EXIT WHEN hi IS NULL;

    UPDATE orders o
       SET customer_id = m.customer_id
      FROM legacy_customer_map m
     WHERE o.id = m.order_id
       AND m.order_id > lo
       AND m.order_id <= hi
       AND o.customer_id IS DISTINCT FROM m.customer_id;

    COMMIT;
    lo := hi;
  END LOOP;
END
$$;

-- 2. CHECK (customer_id IS NOT NULL) as NOT VALID.
--    The ACCESS EXCLUSIVE lock is held only briefly, with retry on lock timeout.
DO $$
DECLARE
  i int := 0;
BEGIN
  LOOP
    BEGIN
      SET LOCAL lock_timeout = '50ms';
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_nn_chk
        CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i >= 400 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

-- 3. Validate the CHECK (SHARE UPDATE EXCLUSIVE only, so writes continue).
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn_chk;

-- 4. Foreign key as NOT VALID, with retry on lock timeout.
DO $$
DECLARE
  i int := 0;
BEGIN
  LOOP
    BEGIN
      SET LOCAL lock_timeout = '50ms';
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i >= 400 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

-- 5. Validate the FK (SHARE UPDATE EXCLUSIVE on orders; writes continue).
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 6. SET NOT NULL. The validated CHECK lets PG skip the table scan, so the
--    ACCESS EXCLUSIVE lock is held only momentarily. Retry on lock timeout.
DO $$
DECLARE
  i int := 0;
BEGIN
  LOOP
    BEGIN
      SET LOCAL lock_timeout = '50ms';
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i >= 400 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;
```
