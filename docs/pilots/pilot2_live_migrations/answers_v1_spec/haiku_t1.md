```sql
-- M1: orders.region text NOT NULL DEFAULT 'EU'
-- On PG17 a constant default is metadata-only (no table rewrite), but ADD COLUMN
-- needs ACCESS EXCLUSIVE, which queues behind the analytics transaction (up to 10 s)
-- and would stall app traffic. Use a short lock_timeout and retry until it gets the lock.

DO $$
DECLARE
  started timestamptz := clock_timestamp();
BEGIN
  LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() - started > interval '20 seconds' THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;
```

```sql
-- M2: orders.customer_id NOT NULL + validated FK to customers(id)
-- Plain SET NOT NULL would scan 5M rows under ACCESS EXCLUSIVE, and a plain
-- ADD FOREIGN KEY would validate under a blocking lock. So:
--   1. add a NOT VALID CHECK (brief lock, retried)
--   2. VALIDATE it (scan under SHARE UPDATE EXCLUSIVE, does not block DML)
--   3. SET NOT NULL (PG12+ trusts the validated CHECK and skips the scan)
--   4. add the FK NOT VALID (brief lock, retried)
--   5. VALIDATE the FK (scan under SHARE UPDATE EXCLUSIVE, does not block DML)
-- New rows from the app always satisfy both, so NOT VALID is safe during traffic.

-- Step 1
DO $$
DECLARE
  started timestamptz := clock_timestamp();
BEGIN
  LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_not_null
        CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() - started > interval '20 seconds' THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- Step 2
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;

-- Step 3
DO $$
DECLARE
  started timestamptz := clock_timestamp();
BEGIN
  LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() - started > interval '20 seconds' THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- Step 4
DO $$
DECLARE
  started timestamptz := clock_timestamp();
BEGIN
  LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() - started > interval '20 seconds' THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- Step 5
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;
```

```sql
-- M3: UNIQUE (external_ref) on orders, backed by a valid index
-- Build the index CONCURRENTLY so DML is not blocked. It cannot run inside a
-- transaction, so it is a top-level statement (autocommit). Then attach it as a
-- constraint with USING INDEX, which only needs a brief lock and no scan.

DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_key;

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

DO $$
DECLARE
  started timestamptz := clock_timestamp();
BEGIN
  LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key
        UNIQUE USING INDEX orders_external_ref_key;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() - started > interval '20 seconds' THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;
```
