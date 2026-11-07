```sql
-- C2: orders.customer_id NOT NULL + validated FK to customers(id)
-- Pattern: add constraints NOT VALID (brief lock), validate them under
-- SHARE UPDATE EXCLUSIVE (does not block app DML or analytics), then SET NOT NULL,
-- which skips the table scan because a validated CHECK (customer_id IS NOT NULL) exists.
-- Every lock-taking step uses a short lock_timeout with retries so we never sit in the
-- lock queue behind the long analytics transactions (which would stall app writes).

SET statement_timeout = 0;
SET lock_timeout = 0;

-- 1. Helper CHECK constraint, NOT VALID (brief ACCESS EXCLUSIVE, no scan)
DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '25 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_not_null CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

-- 2. Validate the CHECK (SHARE UPDATE EXCLUSIVE: app reads/writes continue)
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;

-- 3. FK, NOT VALID (brief SHARE ROW EXCLUSIVE on orders and customers, no scan)
DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '15 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

-- 4. Validate the FK (SHARE UPDATE EXCLUSIVE on orders, ROW SHARE on customers)
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 5. SET NOT NULL (brief ACCESS EXCLUSIVE; scan skipped thanks to the validated CHECK),
--    then drop the now-redundant helper CHECK in the same short lock window.
DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '25 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_customer_id_not_null;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;
```
