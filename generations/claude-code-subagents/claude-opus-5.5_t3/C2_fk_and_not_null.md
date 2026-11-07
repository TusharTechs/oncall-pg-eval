```sql
-- C2: orders.customer_id NOT NULL + validated FK to customers(id), online.
-- Plan:
--   1. (brief ACCESS EXCLUSIVE, retried) add CHECK (customer_id IS NOT NULL) NOT VALID
--      and FK NOT VALID in a single ALTER.
--   2. VALIDATE both (SHARE UPDATE EXCLUSIVE: does not block app or analytics).
--   3. (brief ACCESS EXCLUSIVE, retried) SET NOT NULL -- uses the validated CHECK, no scan.
-- Every lock that conflicts with app/analytics is taken with a short lock_timeout
-- inside a retry loop so we never sit in the lock queue behind the analytics txn.

SET statement_timeout = 0;
SET lock_timeout = '100ms';

-- Step 1: add NOT VALID constraints (metadata only)
DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '25 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_not_null CHECK (customer_id IS NOT NULL) NOT VALID,
        ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id)
            REFERENCES customers(id) NOT VALID;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- Step 2: validate (SHARE UPDATE EXCLUSIVE on orders, ROW SHARE on customers;
-- compatible with app writes and analytics reads)
DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '20 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '20 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- Step 3: SET NOT NULL; the validated CHECK constraint lets PG skip the table scan,
-- so the ACCESS EXCLUSIVE lock is held only momentarily.
DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '25 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- The helper CHECK constraint is now redundant; it is allowed to remain
-- (dropping it would need another ACCESS EXCLUSIVE lock for no benefit).

RESET lock_timeout;
```
